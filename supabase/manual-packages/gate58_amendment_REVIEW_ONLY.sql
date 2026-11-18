-- ONEXA Gate 58 draft/rejected amendment — REVIEW ONLY.
-- Never auto-execute. First prove isolated Staging, restorable backup, and
-- finance/security approval. This package cannot be deployed against the
-- legacy, uncorrected Gate 58 foundation.
begin;

do $preflight$
declare
  _create regprocedure := to_regprocedure(
    'public.onexa_create_manual_journal(uuid,uuid,date,text,text,text,text,jsonb)'
  );
  _transition regprocedure := to_regprocedure(
    'public.onexa_transition_manual_journal(uuid,text,text)'
  );
  _definition text;
  _balance text;
begin
  if current_database() = 'onexa_gate_test' then
    raise exception 'ONEXA_GATE58_REVIEW_ONLY_NOT_FOR_TEST_FIXTURES';
  end if;
  if to_regprocedure('public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)') is not null then
    raise exception 'ONEXA_GATE58_AMENDMENT_ALREADY_EXISTS_STOP_REVIEW_REQUIRED';
  end if;
  if _create is null or _transition is null
    or to_regclass('public.onexa_manual_journals') is null
    or to_regclass('public.onexa_manual_journal_lines') is null
    or to_regclass('public.onexa_manual_journal_events') is null then
    raise exception 'ONEXA_GATE58_AMENDMENT_DEPENDENCIES_MISSING';
  end if;
  _definition := pg_get_functiondef(_create::oid);
  if position('or debit is null or credit is null' in _definition) = 0
    or position('_period_code <> to_char(_accounting_date,' in _definition) = 0
    or position('_total_debit <> _total_credit' in _definition) = 0 then
    raise exception 'ONEXA_GATE58_CREATE_RPC_NOT_HARDENED_STOP';
  end if;
  _definition := pg_get_functiondef(_transition::oid);
  if position('_to_status in (''approved'',''rejected'') then ''approve''' in _definition) = 0 then
    raise exception 'ONEXA_GATE58_REVIEWER_PERMISSIONS_NOT_HARDENED_STOP';
  end if;
  select pg_get_constraintdef(c.oid,true) into _balance
  from pg_constraint c
  where c.conrelid='public.onexa_manual_journals'::regclass
    and c.conname='onexa_manual_journals_balanced';
  if _balance is distinct from 'CHECK (total_debit = total_credit)' then
    raise exception 'ONEXA_GATE58_EXACT_BALANCE_CONSTRAINT_REQUIRED';
  end if;
end;
$preflight$;

create or replace function public.onexa_amend_manual_journal(
  _journal_id uuid,
  _expected_revision integer,
  _memo text,
  _external_reference text,
  _lines jsonb
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _old_lines jsonb;
  _new_lines jsonb;
  _line_count integer;
  _distinct_line_count integer;
  _total_debit numeric(20,4);
  _total_credit numeric(20,4);
  _new_revision integer;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'create') then
    raise exception 'ONEXA_MANUAL_JOURNAL_AMEND_NOT_AUTHORIZED';
  end if;

  select * into _journal
  from public.onexa_manual_journals
  where id = _journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;
  if _journal.created_by <> _actor then
    raise exception 'ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_AMEND';
  end if;
  if _journal.status not in ('draft', 'rejected')
    or _journal.posted_journal_id is not null
    or _journal.reversal_journal_id is not null then
    raise exception 'ONEXA_MANUAL_JOURNAL_AMEND_STATUS_INVALID';
  end if;
  -- Reject stale tabs and concurrent edits; no automatic last-write-wins.
  if _expected_revision is null or _expected_revision <> _journal.revision then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVISION_CONFLICT';
  end if;
  if nullif(btrim(_memo), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_MEMO_REQUIRED';
  end if;
  if _lines is null or jsonb_typeof(_lines) <> 'array'
    or jsonb_array_length(_lines) < 2 then
    raise exception 'ONEXA_MANUAL_JOURNAL_REQUIRES_TWO_LINES';
  end if;

  -- The legal entity, branch, accounting date, period and currency are
  -- immutable on this revision. Corrections to those fields require a new journal.
  perform 1 from public.onexa_legal_entities
  where id = _journal.legal_entity_id
    and tenant_id = _tenant_id and is_active is true;
  if not found then raise exception 'ONEXA_LEGAL_ENTITY_NOT_AVAILABLE'; end if;
  perform 1 from public.onexa_branches
  where id = _journal.branch_id and legal_entity_id = _journal.legal_entity_id
    and tenant_id = _tenant_id and is_active is true;
  if not found then raise exception 'ONEXA_BRANCH_NOT_AVAILABLE'; end if;

  select count(*), count(distinct line_number),
         coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into _line_count, _distinct_line_count, _total_debit, _total_credit
  from jsonb_to_recordset(_lines) as line(
    line_number integer, account_code text, debit numeric, credit numeric,
    description text, dimensions jsonb
  );

  if _line_count <> _distinct_line_count or exists (
    select 1 from jsonb_to_recordset(_lines) as line(
      line_number integer, account_code text, debit numeric, credit numeric,
      description text, dimensions jsonb
    )
    where line_number is null or line_number < 1
      or nullif(btrim(account_code), '') is null
      or debit is null or credit is null
      or debit < 0 or credit < 0
      or not ((debit > 0) <> (credit > 0))
      or (dimensions is not null and jsonb_typeof(dimensions) <> 'object')
  ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_LINE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(_lines) as line(debit numeric, credit numeric)
    where debit <> round(debit, 4) or credit <> round(credit, 4)
  ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_AMOUNT_PRECISION_INVALID';
  end if;
  if _journal.currency = 'SAR' and exists (
    select 1 from jsonb_to_recordset(_lines) as line(debit numeric, credit numeric)
    where debit <> round(debit, 2) or credit <> round(credit, 2)
  ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_SAR_PRECISION_INVALID';
  end if;
  if _total_debit <= 0 or _total_debit <> _total_credit then
    raise exception 'ONEXA_MANUAL_JOURNAL_NOT_BALANCED';
  end if;
  perform 1 from jsonb_to_recordset(_lines) as line(account_code text)
  left join public.chart_of_accounts account
    on account.tenant_id = _tenant_id
   and account.code = btrim(line.account_code)
   and account.is_active is true
   and account.account_type::text = 'detail'
  where account.id is null;
  if found then raise exception 'ONEXA_MANUAL_JOURNAL_ACCOUNT_INVALID'; end if;
  if _journal.revision >= 2147483647 then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVISION_LIMIT';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'line_number', line_number, 'account_code', account_code,
    'debit', debit, 'credit', credit, 'description', description,
    'dimensions', dimensions
  ) order by line_number), '[]'::jsonb)
  into _old_lines
  from public.onexa_manual_journal_lines
  where tenant_id = _tenant_id and manual_journal_id = _journal_id;

  delete from public.onexa_manual_journal_lines
  where tenant_id = _tenant_id and manual_journal_id = _journal_id;

  insert into public.onexa_manual_journal_lines (
    tenant_id, manual_journal_id, line_number, account_code,
    debit, credit, description, dimensions
  )
  select _tenant_id, _journal_id, line_number, btrim(account_code),
         debit, credit, nullif(btrim(description), ''), coalesce(dimensions,'{}'::jsonb)
  from jsonb_to_recordset(_lines) as line(
    line_number integer, account_code text, debit numeric, credit numeric,
    description text, dimensions jsonb
  )
  order by line_number;

  update public.onexa_manual_journals
    set memo = btrim(_memo),
        external_reference = nullif(btrim(_external_reference), ''),
        total_debit = _total_debit,
        total_credit = _total_credit,
        status = 'draft',
        revision = revision + 1,
        submitted_by = null, submitted_at = null,
        approved_by = null, approved_at = null,
        rejected_by = null, rejected_at = null,
        updated_at = now()
  where id = _journal_id and tenant_id = _tenant_id
    and revision = _expected_revision and status in ('draft', 'rejected')
  returning revision into _new_revision;
  if _new_revision is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVISION_CONFLICT';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'line_number', line_number, 'account_code', account_code,
    'debit', debit, 'credit', credit, 'description', description,
    'dimensions', dimensions
  ) order by line_number), '[]'::jsonb)
  into _new_lines
  from public.onexa_manual_journal_lines
  where tenant_id = _tenant_id and manual_journal_id = _journal_id;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type,
    from_status, to_status, actor_id, event_data
  ) values (
    _tenant_id, _journal_id, 'amended', _journal.status, 'draft', _actor,
    jsonb_build_object(
      'previous_revision', _journal.revision,
      'new_revision', _new_revision,
      'before', jsonb_build_object('memo', _journal.memo,
        'external_reference', _journal.external_reference,
        'total_debit', _journal.total_debit, 'total_credit', _journal.total_credit,
        'lines', _old_lines),
      'after', jsonb_build_object('memo', btrim(_memo),
        'external_reference', nullif(btrim(_external_reference), ''),
        'total_debit', _total_debit, 'total_credit', _total_credit,
        'lines', _new_lines)
    )
  );
  return _new_revision;
end;
$function$;

revoke all on function public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)
  from public, anon;
grant execute on function public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)
  to authenticated;

-- No existing rows, RLS policies or other function bodies are changed.
commit;
