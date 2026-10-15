-- Gate 42 manual package: project direct-cost accrual to B4.
-- Only new, independently incurred and unpaid costs belong here. Never rebook
-- payroll, purchase invoices or inventory issues already recognized in GL.
begin;
do $$ begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
    or to_regclass('public.onexa_business_documents') is null
    or to_regclass('public.onexa_journal_headers') is null
    or to_regclass('public.onexa_account_role_mappings') is null
    or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE42_FOUNDATION_REQUIRED';
  end if;
end $$;

create table if not exists public.onexa_project_cost_centers (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  project_code text not null check (length(btrim(project_code)) > 0),
  project_name text not null check (length(btrim(project_name)) > 0),
  cost_center_code text not null check (length(btrim(cost_center_code)) > 0),
  is_active boolean not null default true,
  unique (tenant_id, legal_entity_id, branch_id, project_code, cost_center_code)
);

create table if not exists public.onexa_project_cost_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  project_cost_center_id uuid not null references public.onexa_project_cost_centers(id) on delete restrict,
  external_reference text not null check (length(btrim(external_reference)) > 0),
  amount numeric(20,4) not null check (amount > 0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision > 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, external_reference)
);

create or replace function public.onexa_guard_posted_project_cost_center()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if exists (select 1 from public.onexa_project_cost_postings p where p.project_cost_center_id = old.id) then
    if tg_op = 'DELETE' then raise exception 'ONEXA_POSTED_PROJECT_CENTER_IMMUTABLE'; end if;
    if row(new.tenant_id,new.legal_entity_id,new.branch_id,new.project_code,new.cost_center_code)
       is distinct from row(old.tenant_id,old.legal_entity_id,old.branch_id,old.project_code,old.cost_center_code) then
      raise exception 'ONEXA_POSTED_PROJECT_CENTER_IMMUTABLE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists onexa_guard_posted_project_cost_center on public.onexa_project_cost_centers;
create trigger onexa_guard_posted_project_cost_center before update or delete
on public.onexa_project_cost_centers for each row execute function public.onexa_guard_posted_project_cost_center();

alter table public.onexa_project_cost_centers enable row level security;
alter table public.onexa_project_cost_postings enable row level security;
drop policy if exists onexa_project_cost_centers_read on public.onexa_project_cost_centers;
create policy onexa_project_cost_centers_read on public.onexa_project_cost_centers
for select to authenticated using (tenant_id = onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(), 'projects', 'read'));
drop policy if exists onexa_project_cost_postings_read on public.onexa_project_cost_postings;
create policy onexa_project_cost_postings_read on public.onexa_project_cost_postings
for select to authenticated using (tenant_id = onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(), 'projects', 'read'));

create or replace view public.onexa_project_cost_reconciliation
with (security_invoker = true) as
select d.id as document_id, d.tenant_id, d.legal_entity_id, d.document_number,
  d.status, d.gross_total, p.journal_id, p.amount as posted_amount,
  c.project_code, c.cost_center_code,
  case when d.status <> 'posted' then 'not_posted'
    when p.journal_id is distinct from d.posted_journal_id then 'journal_mismatch'
    when j.id is null then 'journal_reversed_or_missing'
    when j.source_document_type is distinct from 'project_cost'
      or j.source_document_id is distinct from d.id::text
      or j.total_debit is distinct from d.gross_total
      or j.total_credit is distinct from d.gross_total
      or j.currency is distinct from d.currency then 'journal_source_or_amount_mismatch'
    when p.amount is distinct from d.gross_total then 'amount_mismatch'
    when c.id is null then 'project_missing'
    when c.legal_entity_id is distinct from d.legal_entity_id
      or c.branch_id is distinct from d.branch_id then 'project_scope_mismatch'
    else 'reconciled' end as reconciliation_status
from public.onexa_business_documents d
left join public.onexa_project_cost_postings p on p.document_id = d.id and p.tenant_id = d.tenant_id
  and p.legal_entity_id = d.legal_entity_id
left join public.onexa_journal_headers j on j.id = p.journal_id
  and j.tenant_id = d.tenant_id and j.legal_entity_id = d.legal_entity_id
  and j.state = 'posted' and j.reversal_journal_id is null
left join public.onexa_project_cost_centers c on c.id = p.project_cost_center_id and c.tenant_id = d.tenant_id
where d.document_type = 'project_cost';

create or replace function public.onexa_post_project_cost(_document_id uuid, _period_code text)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
  _center public.onexa_project_cost_centers%rowtype;
  _debit text;
  _credit text;
  _reference text;
  _journal uuid;
  _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'projects','post') then
    raise exception 'ONEXA_PROJECT_COST_POST_NOT_AUTHORIZED'; end if;
  if coalesce(btrim(_period_code),'') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'ONEXA_PROJECT_COST_PERIOD_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':project-cost:' || _document_id::text,0));
  select * into _document from public.onexa_business_documents
    where id = _document_id and tenant_id = _tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _document.document_type <> 'project_cost' or _document.module_key <> 'projects' then
    raise exception 'ONEXA_PROJECT_COST_DOCUMENT_REQUIRED'; end if;
  if _document.status = 'posted' and _document.posted_journal_id is not null then
    select journal_id into _journal from public.onexa_project_cost_postings
      where document_id = _document.id and tenant_id = _tenant;
    if _journal is distinct from _document.posted_journal_id then
      raise exception 'ONEXA_PROJECT_COST_RETRY_JOURNAL_MISMATCH'; end if;
    perform 1 from public.onexa_journal_headers
      where id = _journal and tenant_id = _tenant
        and legal_entity_id = _document.legal_entity_id
        and state = 'posted' and reversal_journal_id is null;
    if not found then raise exception 'ONEXA_PROJECT_COST_JOURNAL_REVERSED_OR_MISSING'; end if;
    return _journal;
  end if;
  if _document.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.created_by = _actor then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _document.branch_id is null or _document.currency <> 'SAR'
    or _document.party_id is not null or _document.party_type is not null
    or _document.origin <> 'native' or _document.gross_total <= 0
    or _document.tax_total <> 0 or _document.discount_total <> 0
    or _document.subtotal <> _document.gross_total then
    raise exception 'ONEXA_PROJECT_COST_DOCUMENT_INVALID'; end if;
  if (select count(*) from public.onexa_business_document_lines where document_id = _document.id) <> 1
    or not exists (select 1 from public.onexa_business_document_lines
      where document_id = _document.id and tenant_id = _tenant and item_id is null
        and tax_amount = 0 and net_amount = _document.gross_total
        and gross_amount = _document.gross_total) then
    raise exception 'ONEXA_PROJECT_COST_LINE_MISMATCH'; end if;
  if nullif(_document.source_snapshot->>'project_cost_center_id','') is null then
    raise exception 'ONEXA_PROJECT_CENTER_REQUIRED'; end if;
  if _document.source_snapshot->>'source_kind' is distinct from 'unpaid_direct_cost' then
    raise exception 'ONEXA_PROJECT_COST_SOURCE_KIND_INVALID'; end if;
  select * into _center from public.onexa_project_cost_centers
    where id = (_document.source_snapshot->>'project_cost_center_id')::uuid
      and tenant_id = _tenant for update;
  if not found or not _center.is_active
    or _center.legal_entity_id is distinct from _document.legal_entity_id
    or _center.branch_id is distinct from _document.branch_id
    or _document.dimensions->>'project' is distinct from _center.project_code
    or _document.dimensions->>'costCenter' is distinct from _center.cost_center_code then
    raise exception 'ONEXA_PROJECT_CENTER_SCOPE_INVALID'; end if;
  _reference := nullif(btrim(_document.external_reference),'');
  if _reference is null then raise exception 'ONEXA_PROJECT_COST_EXTERNAL_REFERENCE_REQUIRED'; end if;
  -- The unique index is the definitive race-safe duplicate control.
  if exists (select 1 from public.onexa_project_cost_postings
    where tenant_id = _tenant and legal_entity_id = _document.legal_entity_id
      and external_reference = _reference) then
    raise exception 'ONEXA_PROJECT_COST_REFERENCE_ALREADY_POSTED'; end if;
  select m.account_code into _debit from public.onexa_account_role_mappings m
    where m.tenant_id = _tenant and m.legal_entity_id = _document.legal_entity_id
      and m.account_role = 'project_wip_or_expense' and m.is_active;
  select m.account_code into _credit from public.onexa_account_role_mappings m
    where m.tenant_id = _tenant and m.legal_entity_id = _document.legal_entity_id
      and m.account_role = 'cost_source_or_clearing' and m.is_active;
  if _debit is null or _credit is null or _debit = _credit
    or not exists (select 1 from public.chart_of_accounts a
      where a.tenant_id=_tenant and a.code=_debit and a.is_active
        and a.account_type::text='detail'
        and a.category::text in ('assets','expenses','cost_of_revenue'))
    or not exists (select 1 from public.chart_of_accounts a
      where a.tenant_id=_tenant and a.code=_credit and a.is_active
        and a.account_type::text='detail' and a.category::text='liabilities')
    or (select count(*) from public.chart_of_accounts a
      where a.tenant_id = _tenant and a.code in (_debit,_credit)
        and a.account_type::text = 'detail' and a.is_active) <> 2 then
    raise exception 'ONEXA_PROJECT_COST_ACCOUNT_MAPPING_REQUIRED'; end if;
  _dimensions := _document.dimensions || jsonb_build_object(
    'legalEntity',_document.legal_entity_id,'branch',_document.branch_id);
  select public.onexa_post_journal(
    _legal_entity_id => _document.legal_entity_id,
    _source_document_type => 'project_cost',
    _source_document_id => _document.id::text,
    _source_revision => _document.revision,
    _source_status => 'approved',
    _source_snapshot => _document.source_snapshot || jsonb_build_object(
      'document_number',_document.document_number,
      'external_reference',_reference,'posting_contract_version','project-cost-v1'),
    _accounting_date => _document.accounting_date,
    _period_code => btrim(_period_code),
    _currency => 'SAR',
    _memo => coalesce(_document.memo,'Project cost ' || _document.document_number),
    _lines => jsonb_build_array(
      jsonb_build_object('account_code',_debit,'debit',_document.gross_total,'credit',0,
        'description','Project cost','dimensions',_dimensions),
      jsonb_build_object('account_code',_credit,'debit',0,'credit',_document.gross_total,
        'description','Unpaid project cost accrual','dimensions',_dimensions)
    ))::uuid into _journal;
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;
  insert into public.onexa_project_cost_postings
    (document_id,tenant_id,legal_entity_id,project_cost_center_id,
     external_reference,amount,journal_id,source_revision,posted_by)
  values (_document.id,_tenant,_document.legal_entity_id,_center.id,
    _reference,_document.gross_total,_journal,_document.revision,_actor);
  perform set_config('onexa.transition_authorized','true',true);
  perform set_config('onexa.transition_reason','posted_from_project_cost',true);
  update public.onexa_business_documents set status='posted',posted_by=_actor,
    posted_at=now(),posted_journal_id=_journal,posting_error=null
    where id=_document.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id,document_id,event_type,from_status,to_status,actor_id,event_data)
  values (_tenant,_document.id,'posting_completed','approved','posted',_actor,
    jsonb_build_object('journal_id',_journal,'posting_contract_version','project-cost-v1'));
  return _journal;
end $$;

revoke all on public.onexa_project_cost_centers, public.onexa_project_cost_postings from anon, authenticated;
grant select on public.onexa_project_cost_centers, public.onexa_project_cost_postings to authenticated;
grant select on public.onexa_project_cost_reconciliation to authenticated;
revoke all on function public.onexa_post_project_cost(uuid,text) from public, anon;
grant execute on function public.onexa_post_project_cost(uuid,text) to authenticated;
revoke all on function public.onexa_guard_posted_project_cost_center() from public, anon, authenticated;
commit;
