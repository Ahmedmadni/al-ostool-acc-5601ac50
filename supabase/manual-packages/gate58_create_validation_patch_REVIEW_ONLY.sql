-- ONEXA Gate 58 — precision/date/required amount drift correction (REVIEW ONLY).
-- NOT A DEPLOYMENT INSTRUCTION. Run only after independent Staging tests,
-- verified restore and finance authorization. No data or flags should be changed
-- as part of CI. Production and Staging are not automatically touched.
--
-- The digest is from READ-ONLY catalog inspection of the observed Lovable
-- production function on 2026-11-16 (PostgreSQL 17.6). Exact match is required.
-- Any later live edit, version variation or unexpected schema = STOP and re-review.
begin;

do $gate58_preflight$
declare
  _func regprocedure := to_regprocedure(
    'public.onexa_create_manual_journal(uuid,uuid,date,text,text,text,text,jsonb)'
  );
begin
  if _func is null then
    raise exception 'ONEXA_GATE58_CREATE_RPC_MISSING';
  end if;
  if md5(pg_get_functiondef(_func::oid)) <> '0a8e73d608b3642837209b5334c7477a' then
    raise exception 'ONEXA_GATE58_LIVE_FUNCTION_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
  if to_regclass('public.onexa_manual_journals') is null
    or to_regclass('public.onexa_manual_journal_lines') is null
    or to_regclass('public.chart_of_accounts') is null
    or to_regclass('public.onexa_manual_journal_sequences') is null then
    raise exception 'ONEXA_GATE58_ACCOUNTING_SCHEMA_REQUIRED';
  end if;
end;
$gate58_preflight$;

create or replace function public.onexa_create_manual_journal(
  _legal_entity_id uuid,
  _branch_id uuid,
  _accounting_date date,
  _period_code text,
  _currency text,
  _memo text,
  _external_reference text,
  _lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _id uuid;
  _year integer := extract(year from _accounting_date)::integer;
  _issued bigint;
  _journal_number text;
  _line_count integer;
  _distinct_line_count integer;
  _total_debit numeric(20,4);
  _total_credit numeric(20,4);
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'create') then
    raise exception 'ONEXA_MANUAL_JOURNAL_CREATE_NOT_AUTHORIZED';
  end if;
  if _accounting_date is null or _period_code is null
     or _period_code !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or _period_code <> to_char(_accounting_date, 'YYYY-MM') then
    raise exception 'ONEXA_MANUAL_JOURNAL_PERIOD_INVALID';
  end if;
  if upper(coalesce(_currency, '')) !~ '^[A-Z]{3}$' then
    raise exception 'ONEXA_MANUAL_JOURNAL_CURRENCY_INVALID';
  end if;
  if nullif(btrim(_memo), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_MEMO_REQUIRED';
  end if;
  if _lines is null or jsonb_typeof(_lines) <> 'array' or jsonb_array_length(_lines) < 2 then
    raise exception 'ONEXA_MANUAL_JOURNAL_REQUIRES_TWO_LINES';
  end if;

  perform 1 from public.onexa_legal_entities
  where id = _legal_entity_id and tenant_id = _tenant_id and is_active = true;
  if not found then raise exception 'ONEXA_LEGAL_ENTITY_NOT_AVAILABLE'; end if;

  perform 1 from public.onexa_branches
  where id = _branch_id and tenant_id = _tenant_id
    and legal_entity_id = _legal_entity_id and is_active = true;
  if not found then raise exception 'ONEXA_BRANCH_NOT_AVAILABLE'; end if;

  select count(*), count(distinct line_number),
         coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into _line_count, _distinct_line_count, _total_debit, _total_credit
  from jsonb_to_recordset(_lines) as line(
    line_number integer, account_code text, debit numeric, credit numeric,
    description text, dimensions jsonb
  );

  if _line_count <> _distinct_line_count
     or exists (
       select 1 from jsonb_to_recordset(_lines) as line(
         line_number integer, account_code text, debit numeric, credit numeric,
         description text, dimensions jsonb
       )
       where line_number is null or line_number < 1
          or nullif(btrim(account_code), '') is null
          or debit is null or credit is null
          or debit < 0 or credit < 0
          or not ((debit > 0) <> (credit > 0))
          or dimensions is not null and jsonb_typeof(dimensions) <> 'object'
     ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_LINE_INVALID';
  end if;

  -- Do not silently round source amounts when storing numeric(20,4) lines.
  -- SAR journals additionally use halalas (two decimal places).
  if exists (
    select 1 from jsonb_to_recordset(_lines) as line(debit numeric, credit numeric)
    where debit <> round(debit, 4) or credit <> round(credit, 4)
  ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_AMOUNT_PRECISION_INVALID';
  end if;

  if upper(_currency) = 'SAR' and exists (
    select 1 from jsonb_to_recordset(_lines) as line(debit numeric, credit numeric)
    where debit <> round(debit, 2) or credit <> round(credit, 2)
  ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_SAR_PRECISION_INVALID';
  end if;

  if _total_debit <= 0 or _total_debit <> _total_credit then
    raise exception 'ONEXA_MANUAL_JOURNAL_NOT_BALANCED';
  end if;

  perform 1
  from jsonb_to_recordset(_lines) as line(account_code text)
  left join public.chart_of_accounts account
    on account.tenant_id = _tenant_id
   and account.code = btrim(line.account_code)
   and account.is_active is true
   and account.account_type::text = 'detail'
  where account.id is null;
  if found then raise exception 'ONEXA_MANUAL_JOURNAL_ACCOUNT_INVALID'; end if;

  insert into public.onexa_manual_journal_sequences (
    tenant_id, legal_entity_id, fiscal_year, next_number
  ) values (
    _tenant_id, _legal_entity_id, _year, 2
  )
  on conflict (tenant_id, legal_entity_id, fiscal_year)
  do update set next_number = public.onexa_manual_journal_sequences.next_number + 1,
                updated_at = now()
  returning next_number - 1 into _issued;

  _journal_number := format('MJ-%s-%s', _year, lpad(_issued::text, 6, '0'));

  insert into public.onexa_manual_journals (
    tenant_id, legal_entity_id, branch_id, journal_number, accounting_date,
    period_code, currency, memo, external_reference, total_debit, total_credit, created_by
  ) values (
    _tenant_id, _legal_entity_id, _branch_id, _journal_number, _accounting_date,
    _period_code, upper(_currency), btrim(_memo), nullif(btrim(_external_reference), ''),
    _total_debit, _total_credit, _actor
  ) returning id into _id;

  insert into public.onexa_manual_journal_lines (
    tenant_id, manual_journal_id, line_number, account_code,
    debit, credit, description, dimensions
  )
  select
    _tenant_id, _id, line_number, btrim(account_code),
    debit, credit, nullif(btrim(description), ''), coalesce(dimensions, '{}'::jsonb)
  from jsonb_to_recordset(_lines) as line(
    line_number integer, account_code text, debit numeric, credit numeric,
    description text, dimensions jsonb
  )
  order by line_number;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, to_status, actor_id, event_data
  ) values (
    _tenant_id, _id, 'created', 'draft', _actor,
    jsonb_build_object('journal_number', _journal_number, 'total', _total_debit)
  );

  return _id;
end;
$function$;

-- Do not change function grants here. Existing EXECUTE privileges must remain.
-- The matching read-only postcheck must be run after any approved execution.
commit;
