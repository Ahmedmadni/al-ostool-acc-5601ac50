-- ONEXA Gate 58: governed manual journal workflow.
-- Production execution is operator-authorized; run the full transaction atomically.
-- Requires verified Gate 34, B3 authorization, and B4 journal posting foundation.

begin;

do $preflight$
begin
  if to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE58_B3_AUTHORIZATION_REQUIRED';
  end if;
  if to_regprocedure(
    'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'
  ) is null then
    raise exception 'ONEXA_GATE58_B4_POST_JOURNAL_REQUIRED';
  end if;
  if to_regprocedure('public.onexa_reverse_journal(uuid,date,text,text)') is null then
    raise exception 'ONEXA_GATE58_B4_REVERSE_JOURNAL_REQUIRED';
  end if;
  if to_regclass('public.chart_of_accounts') is null
     or to_regclass('public.onexa_legal_entities') is null
     or to_regclass('public.onexa_branches') is null then
    raise exception 'ONEXA_GATE58_ACCOUNTING_FOUNDATION_REQUIRED';
  end if;
end;
$preflight$;

create table if not exists public.onexa_manual_journal_sequences (
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  fiscal_year integer not null check (fiscal_year between 2000 and 2200),
  next_number bigint not null default 1 check (next_number > 0),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, legal_entity_id, fiscal_year)
);

create table if not exists public.onexa_manual_journals (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  journal_number text not null,
  accounting_date date not null,
  period_code text not null check (period_code ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  currency text not null default 'SAR' check (currency ~ '^[A-Z]{3}$'),
  memo text not null check (length(btrim(memo)) > 0),
  external_reference text,
  status text not null default 'draft' check (
    status in ('draft','submitted','approved','posted','rejected','cancelled','reversed')
  ),
  revision integer not null default 1 check (revision > 0),
  total_debit numeric(20,4) not null check (total_debit > 0),
  total_credit numeric(20,4) not null check (total_credit > 0),
  posted_journal_id uuid,
  reversal_journal_id uuid,
  created_by uuid not null,
  submitted_by uuid,
  approved_by uuid,
  posted_by uuid,
  rejected_by uuid,
  cancelled_by uuid,
  reversed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  approved_at timestamptz,
  posted_at timestamptz,
  rejected_at timestamptz,
  cancelled_at timestamptz,
  reversed_at timestamptz,
  constraint onexa_manual_journals_balanced check (abs(total_debit - total_credit) <= 0.005),
  unique (tenant_id, legal_entity_id, journal_number, revision)
);

create table if not exists public.onexa_manual_journal_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  manual_journal_id uuid not null references public.onexa_manual_journals(id) on delete cascade,
  line_number integer not null check (line_number > 0),
  account_code text not null check (length(btrim(account_code)) > 0),
  debit numeric(20,4) not null default 0 check (debit >= 0),
  credit numeric(20,4) not null default 0 check (credit >= 0),
  description text,
  dimensions jsonb not null default '{}'::jsonb check (jsonb_typeof(dimensions) = 'object'),
  created_at timestamptz not null default now(),
  constraint onexa_manual_journal_lines_one_side check ((debit > 0) <> (credit > 0)),
  unique (manual_journal_id, line_number)
);

create table if not exists public.onexa_manual_journal_events (
  id bigint generated always as identity primary key,
  tenant_id text not null,
  manual_journal_id uuid not null references public.onexa_manual_journals(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  actor_id uuid not null,
  reason text,
  event_data jsonb not null default '{}'::jsonb check (jsonb_typeof(event_data) = 'object'),
  created_at timestamptz not null default now()
);

create index if not exists onexa_manual_journals_status_date_idx
  on public.onexa_manual_journals (tenant_id, legal_entity_id, status, accounting_date desc);
create index if not exists onexa_manual_journal_lines_account_idx
  on public.onexa_manual_journal_lines (tenant_id, account_code);
create index if not exists onexa_manual_journal_events_journal_idx
  on public.onexa_manual_journal_events (tenant_id, manual_journal_id, created_at);

alter table public.onexa_manual_journal_sequences enable row level security;
alter table public.onexa_manual_journals enable row level security;
alter table public.onexa_manual_journal_lines enable row level security;
alter table public.onexa_manual_journal_events enable row level security;

drop policy if exists onexa_manual_journals_select_tenant on public.onexa_manual_journals;
create policy onexa_manual_journals_select_tenant
  on public.onexa_manual_journals for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'finance', 'read')
  );

drop policy if exists onexa_manual_journal_lines_select_tenant on public.onexa_manual_journal_lines;
create policy onexa_manual_journal_lines_select_tenant
  on public.onexa_manual_journal_lines for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'finance', 'read')
  );

drop policy if exists onexa_manual_journal_events_select_tenant on public.onexa_manual_journal_events;
create policy onexa_manual_journal_events_select_tenant
  on public.onexa_manual_journal_events for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'finance', 'read')
  );

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
  if _accounting_date is null or _period_code !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
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
       where line_number < 1
          or nullif(btrim(account_code), '') is null
          or debit < 0 or credit < 0
          or not ((debit > 0) <> (credit > 0))
          or dimensions is not null and jsonb_typeof(dimensions) <> 'object'
     ) then
    raise exception 'ONEXA_MANUAL_JOURNAL_LINE_INVALID';
  end if;

  if _total_debit <= 0 or abs(_total_debit - _total_credit) > 0.005 then
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

create or replace function public.onexa_transition_manual_journal(
  _journal_id uuid,
  _to_status text,
  _reason text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _allowed boolean := false;
  _action text;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;

  select * into _journal from public.onexa_manual_journals
  where id = _journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;

  _allowed := (_journal.status = 'draft' and _to_status in ('submitted','cancelled'))
    or (_journal.status = 'submitted' and _to_status in ('approved','rejected','cancelled'))
    or (_journal.status = 'rejected' and _to_status in ('draft','cancelled'));
  if not _allowed then
    raise exception 'ONEXA_MANUAL_JOURNAL_TRANSITION_INVALID:%->%', _journal.status, _to_status;
  end if;

  _action := case when _to_status = 'approved' then 'approve'
                  when _to_status = 'submitted' then 'submit'
                  else 'create' end;
  if not onexa_private.has_module_action(_actor, 'finance', _action) then
    raise exception 'ONEXA_MANUAL_JOURNAL_TRANSITION_NOT_AUTHORIZED:%', _action;
  end if;

  if _to_status in ('submitted','draft') and _actor <> _journal.created_by then
    raise exception 'ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_SUBMIT';
  end if;
  if _to_status = 'approved' and _actor = _journal.created_by then
    raise exception 'ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_APPROVE';
  end if;
  if _to_status = 'rejected' and nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_REJECTION_REASON_REQUIRED';
  end if;

  update public.onexa_manual_journals
  set status = _to_status,
      submitted_by = case when _to_status = 'submitted' then _actor else submitted_by end,
      submitted_at = case when _to_status = 'submitted' then now() else submitted_at end,
      approved_by = case when _to_status = 'approved' then _actor else approved_by end,
      approved_at = case when _to_status = 'approved' then now() else approved_at end,
      rejected_by = case when _to_status = 'rejected' then _actor else rejected_by end,
      rejected_at = case when _to_status = 'rejected' then now() else rejected_at end,
      cancelled_by = case when _to_status = 'cancelled' then _actor else cancelled_by end,
      cancelled_at = case when _to_status = 'cancelled' then now() else cancelled_at end,
      updated_at = now()
  where id = _journal_id and tenant_id = _tenant_id;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, from_status, to_status, actor_id, reason
  ) values (
    _tenant_id, _journal_id, 'status_changed', _journal.status, _to_status,
    _actor, nullif(btrim(_reason), '')
  );

  return _to_status;
end;
$function$;

create or replace function public.onexa_post_manual_journal(_journal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _lines jsonb;
  _journal_id_result uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'post') then
    raise exception 'ONEXA_MANUAL_JOURNAL_POST_NOT_AUTHORIZED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(_tenant_id || ':manual-journal:' || _journal_id::text, 0));

  select * into _journal from public.onexa_manual_journals
  where id = _journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;
  if _journal.status = 'posted' and _journal.posted_journal_id is not null then
    return _journal.posted_journal_id;
  end if;
  if _journal.status <> 'approved' then
    raise exception 'ONEXA_MANUAL_JOURNAL_MUST_BE_APPROVED';
  end if;
  if _actor = _journal.created_by then
    raise exception 'ONEXA_MANUAL_JOURNAL_POSTER_MUST_DIFFER_FROM_CREATOR';
  end if;

  select jsonb_agg(jsonb_build_object(
    'account_code', line.account_code,
    'debit', line.debit,
    'credit', line.credit,
    'description', line.description,
    'dimensions', line.dimensions || jsonb_build_object(
      'legalEntity', _journal.legal_entity_id,
      'branch', _journal.branch_id
    )
  ) order by line.line_number)
  into _lines
  from public.onexa_manual_journal_lines line
  where line.manual_journal_id = _journal.id and line.tenant_id = _tenant_id;

  if _lines is null or jsonb_array_length(_lines) < 2 then
    raise exception 'ONEXA_MANUAL_JOURNAL_REQUIRES_TWO_LINES';
  end if;

  _journal_id_result := public.onexa_post_journal(
    _legal_entity_id => _journal.legal_entity_id,
    _source_document_type => 'manual_journal',
    _source_document_id => _journal.id::text,
    _source_revision => _journal.revision,
    _source_status => 'approved',
    _source_snapshot => jsonb_build_object(
      'manual_journal_number', _journal.journal_number,
      'external_reference', _journal.external_reference,
      'approved_by', _journal.approved_by,
      'posting_contract_version', 'manual-journal-v1'
    ),
    _accounting_date => _journal.accounting_date,
    _period_code => _journal.period_code,
    _currency => _journal.currency,
    _memo => _journal.memo,
    _lines => _lines
  )::uuid;

  if _journal_id_result is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  update public.onexa_manual_journals
  set status = 'posted', posted_journal_id = _journal_id_result,
      posted_by = _actor, posted_at = now(), updated_at = now()
  where id = _journal.id and tenant_id = _tenant_id and status = 'approved';
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_POST_STATUS_UPDATE_FAILED'; end if;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, from_status, to_status, actor_id, event_data
  ) values (
    _tenant_id, _journal.id, 'posting_completed', 'approved', 'posted', _actor,
    jsonb_build_object('journal_id', _journal_id_result, 'posting_contract_version', 'manual-journal-v1')
  );

  return _journal_id_result;
end;
$function$;

create or replace function public.onexa_reverse_manual_journal(
  _manual_journal_id uuid,
  _accounting_date date,
  _period_code text,
  _reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _reversal_id uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'reverse') then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVERSE_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVERSAL_REASON_REQUIRED';
  end if;

  select * into _journal from public.onexa_manual_journals
  where id = _manual_journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;
  if _journal.status = 'reversed' and _journal.reversal_journal_id is not null then
    return _journal.reversal_journal_id;
  end if;
  if _journal.status <> 'posted' or _journal.posted_journal_id is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_MUST_BE_POSTED';
  end if;

  _reversal_id := public.onexa_reverse_journal(
    _journal_id => _journal.posted_journal_id,
    _accounting_date => _accounting_date,
    _period_code => _period_code,
    _reason => btrim(_reason)
  )::uuid;

  update public.onexa_manual_journals
  set status = 'reversed', reversal_journal_id = _reversal_id,
      reversed_by = _actor, reversed_at = now(), updated_at = now()
  where id = _journal.id and tenant_id = _tenant_id;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, from_status, to_status, actor_id, reason, event_data
  ) values (
    _tenant_id, _journal.id, 'reversal_completed', 'posted', 'reversed', _actor,
    btrim(_reason), jsonb_build_object('reversal_journal_id', _reversal_id)
  );

  return _reversal_id;
end;
$function$;

create or replace view public.onexa_manual_journal_reconciliation
with (security_invoker = true)
as
select
  manual.id as manual_journal_id,
  manual.tenant_id,
  manual.legal_entity_id,
  manual.branch_id,
  manual.journal_number,
  manual.accounting_date,
  manual.period_code,
  manual.currency,
  manual.memo,
  manual.status,
  manual.total_debit,
  manual.total_credit,
  manual.posted_journal_id,
  manual.reversal_journal_id,
  header.journal_number as ledger_journal_number,
  header.total_debit as ledger_total_debit,
  header.total_credit as ledger_total_credit,
  case
    when manual.status in ('draft','submitted','approved','rejected','cancelled') then 'not_posted'
    when manual.status = 'posted' and header.id is null then 'journal_missing'
    when manual.status = 'reversed' and manual.reversal_journal_id is null then 'reversal_missing'
    when abs(manual.total_debit - coalesce(header.total_debit, 0)) > 0.005
      or abs(manual.total_credit - coalesce(header.total_credit, 0)) > 0.005 then 'amount_mismatch'
    else 'reconciled'
  end as reconciliation_status
from public.onexa_manual_journals manual
left join public.onexa_journal_headers header
  on header.id = manual.posted_journal_id
 and header.tenant_id = manual.tenant_id;

revoke all on table public.onexa_manual_journal_sequences from public, anon, authenticated;
revoke all on table public.onexa_manual_journals from public, anon, authenticated;
revoke all on table public.onexa_manual_journal_lines from public, anon, authenticated;
revoke all on table public.onexa_manual_journal_events from public, anon, authenticated;
grant select on table public.onexa_manual_journals to authenticated;
grant select on table public.onexa_manual_journal_lines to authenticated;
grant select on table public.onexa_manual_journal_events to authenticated;
grant select on table public.onexa_manual_journal_reconciliation to authenticated;

revoke all on function public.onexa_create_manual_journal(uuid,uuid,date,text,text,text,text,jsonb) from public, anon;
revoke all on function public.onexa_transition_manual_journal(uuid,text,text) from public, anon;
revoke all on function public.onexa_post_manual_journal(uuid) from public, anon;
revoke all on function public.onexa_reverse_manual_journal(uuid,date,text,text) from public, anon;
grant execute on function public.onexa_create_manual_journal(uuid,uuid,date,text,text,text,text,jsonb) to authenticated;
grant execute on function public.onexa_transition_manual_journal(uuid,text,text) to authenticated;
grant execute on function public.onexa_post_manual_journal(uuid) to authenticated;
grant execute on function public.onexa_reverse_manual_journal(uuid,date,text,text) to authenticated;

commit;
