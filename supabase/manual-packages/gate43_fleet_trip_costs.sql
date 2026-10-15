-- ONEXA Gate 43 manual package: new unpaid cost of a completed fleet trip.
-- Existing fuel, maintenance, payroll, procurement and project costs must not
-- be entered again as a fleet trip charge.
begin;
do $$ begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
    or to_regclass('public.fleet_trips') is null
    or to_regclass('public.fleet_vehicles') is null
    or to_regclass('public.onexa_business_documents') is null
    or to_regclass('public.onexa_journal_headers') is null
    or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE43_FOUNDATION_REQUIRED';
  end if;
  if not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='fleet_trips' and column_name='tenant_id')
    or not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='fleet_vehicles' and column_name='tenant_id') then
    raise exception 'ONEXA_GATE43_TENANT_SCOPED_FLEET_REQUIRED'; end if;
end $$;

create table if not exists public.onexa_fleet_trip_scopes (
  trip_id uuid primary key references public.fleet_trips(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  vehicle_id uuid not null references public.fleet_vehicles(id) on delete restrict,
  trip_label text not null check (length(btrim(trip_label))>0),
  vehicle_label text not null check (length(btrim(vehicle_label))>0),
  cost_center_code text not null check (length(btrim(cost_center_code))>0),
  is_active boolean not null default true
);

create table if not exists public.onexa_fleet_trip_cost_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  trip_id uuid not null references public.onexa_fleet_trip_scopes(trip_id) on delete restrict,
  external_reference text not null check (length(btrim(external_reference))>0),
  amount numeric(20,4) not null check (amount>0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision>0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  unique (tenant_id,legal_entity_id,external_reference)
);

create or replace function public.onexa_guard_posted_fleet_trip_scope()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if exists (select 1 from public.onexa_fleet_trip_cost_postings p where p.trip_id=old.trip_id) then
    if tg_op='DELETE' then raise exception 'ONEXA_POSTED_FLEET_TRIP_SCOPE_IMMUTABLE'; end if;
    if row(new.tenant_id,new.legal_entity_id,new.branch_id,new.vehicle_id,new.cost_center_code)
      is distinct from row(old.tenant_id,old.legal_entity_id,old.branch_id,old.vehicle_id,old.cost_center_code)
    then raise exception 'ONEXA_POSTED_FLEET_TRIP_SCOPE_IMMUTABLE'; end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists onexa_guard_posted_fleet_trip_scope on public.onexa_fleet_trip_scopes;
create trigger onexa_guard_posted_fleet_trip_scope before update or delete
on public.onexa_fleet_trip_scopes for each row execute function public.onexa_guard_posted_fleet_trip_scope();

alter table public.onexa_fleet_trip_scopes enable row level security;
alter table public.onexa_fleet_trip_cost_postings enable row level security;
drop policy if exists onexa_fleet_trip_scopes_read on public.onexa_fleet_trip_scopes;
create policy onexa_fleet_trip_scopes_read on public.onexa_fleet_trip_scopes
for select to authenticated using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'logistics','read'));
drop policy if exists onexa_fleet_trip_cost_postings_read on public.onexa_fleet_trip_cost_postings;
create policy onexa_fleet_trip_cost_postings_read on public.onexa_fleet_trip_cost_postings
for select to authenticated using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'logistics','read'));

create or replace view public.onexa_fleet_trip_cost_reconciliation
with (security_invoker=true) as
select d.id as document_id,d.tenant_id,d.legal_entity_id,d.document_number,
  d.status,d.gross_total,p.journal_id,p.amount as posted_amount,s.trip_label,s.vehicle_label,
  case when d.status<>'posted' then 'not_posted'
    when p.journal_id is distinct from d.posted_journal_id then 'journal_mismatch'
    when j.id is null then 'journal_reversed_or_missing'
    when j.source_document_type is distinct from 'fleet_trip_cost'
      or j.source_document_id is distinct from d.id::text
      or j.total_debit is distinct from d.gross_total
      or j.total_credit is distinct from d.gross_total
      or j.currency is distinct from d.currency then 'journal_source_or_amount_mismatch'
    when p.amount is distinct from d.gross_total then 'amount_mismatch'
    when s.trip_id is null then 'trip_missing'
    when s.legal_entity_id is distinct from d.legal_entity_id
      or s.branch_id is distinct from d.branch_id then 'trip_scope_mismatch'
    else 'reconciled' end as reconciliation_status
from public.onexa_business_documents d
left join public.onexa_fleet_trip_cost_postings p on p.document_id=d.id
  and p.tenant_id=d.tenant_id and p.legal_entity_id=d.legal_entity_id
left join public.onexa_journal_headers j on j.id=p.journal_id
  and j.tenant_id=d.tenant_id and j.legal_entity_id=d.legal_entity_id
  and j.state='posted' and j.reversal_journal_id is null
left join public.onexa_fleet_trip_scopes s on s.trip_id=p.trip_id and s.tenant_id=d.tenant_id
where d.document_type='fleet_trip_cost';

create or replace function public.onexa_post_fleet_trip_cost(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
  _scope public.onexa_fleet_trip_scopes%rowtype;
  _trip public.fleet_trips%rowtype;
  _vehicle public.fleet_vehicles%rowtype;
  _debit text;
  _credit text;
  _reference text;
  _journal uuid;
  _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'logistics','post') then
    raise exception 'ONEXA_FLEET_TRIP_POST_NOT_AUTHORIZED'; end if;
  if coalesce(btrim(_period_code),'') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'ONEXA_FLEET_TRIP_PERIOD_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':fleet-trip-cost:' || _document_id::text,0));
  select * into _document from public.onexa_business_documents
    where id=_document_id and tenant_id=_tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _document.document_type<>'fleet_trip_cost' or _document.module_key<>'logistics' then
    raise exception 'ONEXA_FLEET_TRIP_DOCUMENT_REQUIRED'; end if;
  if _document.status='posted' and _document.posted_journal_id is not null then
    select journal_id into _journal from public.onexa_fleet_trip_cost_postings
      where document_id=_document.id and tenant_id=_tenant;
    if _journal is distinct from _document.posted_journal_id then
      raise exception 'ONEXA_FLEET_TRIP_RETRY_JOURNAL_MISMATCH'; end if;
    perform 1 from public.onexa_journal_headers
      where id=_journal and tenant_id=_tenant
        and legal_entity_id=_document.legal_entity_id
        and state='posted' and reversal_journal_id is null;
    if not found then raise exception 'ONEXA_FLEET_TRIP_JOURNAL_REVERSED_OR_MISSING'; end if;
    return _journal;
  end if;
  if _document.status<>'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.created_by=_actor then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _document.branch_id is null or _document.currency<>'SAR' or _document.origin<>'native'
    or _document.party_id is not null or _document.party_type is not null
    or _document.gross_total<=0 or _document.tax_total<>0
    or _document.discount_total<>0 or _document.subtotal<>_document.gross_total then
    raise exception 'ONEXA_FLEET_TRIP_DOCUMENT_INVALID'; end if;
  if (select count(*) from public.onexa_business_document_lines where document_id=_document.id)<>1
    or not exists (select 1 from public.onexa_business_document_lines
      where document_id=_document.id and tenant_id=_tenant and item_id is null
        and tax_amount=0 and net_amount=_document.gross_total
        and gross_amount=_document.gross_total) then
    raise exception 'ONEXA_FLEET_TRIP_LINE_MISMATCH'; end if;
  if _document.source_snapshot->>'source_kind' is distinct from 'unpaid_trip_charge'
    or nullif(_document.source_snapshot->>'trip_id','') is null then
    raise exception 'ONEXA_FLEET_TRIP_SOURCE_INVALID'; end if;
  select * into _scope from public.onexa_fleet_trip_scopes
    where trip_id=(_document.source_snapshot->>'trip_id')::uuid and tenant_id=_tenant for update;
  if not found or not _scope.is_active
    or _scope.legal_entity_id is distinct from _document.legal_entity_id
    or _scope.branch_id is distinct from _document.branch_id
    or _document.dimensions->>'vehicle' is distinct from _scope.vehicle_id::text
    or _document.dimensions->>'costCenter' is distinct from _scope.cost_center_code then
    raise exception 'ONEXA_FLEET_TRIP_SCOPE_INVALID'; end if;
  select * into _trip from public.fleet_trips where id=_scope.trip_id and tenant_id=_tenant for share;
  select * into _vehicle from public.fleet_vehicles where id=_scope.vehicle_id and tenant_id=_tenant for share;
  if _trip.id is null or _vehicle.id is null or _trip.status::text<>'completed'
    or _trip.vehicle_id is distinct from _scope.vehicle_id then
    raise exception 'ONEXA_FLEET_TRIP_NOT_COMPLETED_OR_VEHICLE_MISMATCH'; end if;
  _reference:=nullif(btrim(_document.external_reference),'');
  if _reference is null then raise exception 'ONEXA_FLEET_TRIP_REFERENCE_REQUIRED'; end if;
  if exists (select 1 from public.onexa_fleet_trip_cost_postings
    where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
      and external_reference=_reference) then
    raise exception 'ONEXA_FLEET_TRIP_REFERENCE_ALREADY_POSTED'; end if;
  select account_code into _debit from public.onexa_account_role_mappings
    where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
      and account_role='logistics_or_project_cost' and is_active;
  select account_code into _credit from public.onexa_account_role_mappings
    where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
      and account_role='cash_ap_or_clearing' and is_active;
  if _debit is null or _credit is null or _debit=_credit
    or not exists (select 1 from public.chart_of_accounts a where a.tenant_id=_tenant
      and a.code=_debit and a.is_active and a.account_type::text='detail'
      and a.category::text in ('assets','expenses','cost_of_revenue'))
    or not exists (select 1 from public.chart_of_accounts a where a.tenant_id=_tenant
      and a.code=_credit and a.is_active and a.account_type::text='detail'
      and a.category::text='liabilities') then
    raise exception 'ONEXA_FLEET_TRIP_ACCOUNT_MAPPING_REQUIRED'; end if;
  _dimensions:=_document.dimensions || jsonb_build_object(
    'legalEntity',_document.legal_entity_id,'branch',_document.branch_id);
  select public.onexa_post_journal(
    _legal_entity_id=>_document.legal_entity_id,
    _source_document_type=>'fleet_trip_cost',
    _source_document_id=>_document.id::text,
    _source_revision=>_document.revision,
    _source_status=>'approved',
    _source_snapshot=>_document.source_snapshot || jsonb_build_object(
      'document_number',_document.document_number,'external_reference',_reference,
      'posting_contract_version','fleet-trip-cost-v1'),
    _accounting_date=>_document.accounting_date,
    _period_code=>btrim(_period_code),
    _currency=>'SAR',
    _memo=>coalesce(_document.memo,'Fleet trip cost ' || _document.document_number),
    _lines=>jsonb_build_array(
      jsonb_build_object('account_code',_debit,'debit',_document.gross_total,'credit',0,
        'description','Fleet trip direct cost','dimensions',_dimensions),
      jsonb_build_object('account_code',_credit,'debit',0,'credit',_document.gross_total,
        'description','Unpaid trip charge','dimensions',_dimensions)))::uuid into _journal;
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;
  insert into public.onexa_fleet_trip_cost_postings
    (document_id,tenant_id,legal_entity_id,trip_id,external_reference,
     amount,journal_id,source_revision,posted_by)
  values (_document.id,_tenant,_document.legal_entity_id,_scope.trip_id,_reference,
    _document.gross_total,_journal,_document.revision,_actor);
  perform set_config('onexa.transition_authorized','true',true);
  perform set_config('onexa.transition_reason','posted_from_fleet_trip_cost',true);
  update public.onexa_business_documents set status='posted',posted_by=_actor,
    posted_at=now(),posted_journal_id=_journal,posting_error=null
    where id=_document.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id,document_id,event_type,from_status,to_status,actor_id,event_data)
  values (_tenant,_document.id,'posting_completed','approved','posted',_actor,
    jsonb_build_object('journal_id',_journal,'posting_contract_version','fleet-trip-cost-v1'));
  return _journal;
end $$;

revoke all on public.onexa_fleet_trip_scopes,public.onexa_fleet_trip_cost_postings from anon,authenticated;
grant select on public.onexa_fleet_trip_scopes,public.onexa_fleet_trip_cost_postings to authenticated;
grant select on public.onexa_fleet_trip_cost_reconciliation to authenticated;
revoke all on function public.onexa_post_fleet_trip_cost(uuid,text) from public,anon;
grant execute on function public.onexa_post_fleet_trip_cost(uuid,text) to authenticated;
revoke all on function public.onexa_guard_posted_fleet_trip_scope() from public,anon,authenticated;
commit;
