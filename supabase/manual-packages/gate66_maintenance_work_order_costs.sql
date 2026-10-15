-- ONEXA Gate 66: completed maintenance work-order cost -> project cost -> GL.
-- Manual rollout only. Costs already posted by purchasing, payroll or inventory
-- must never be entered again through this accrual/clearing route.
begin;

do $preflight$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
     or to_regclass('public.onexa_business_documents') is null
     or to_regclass('public.onexa_journal_headers') is null
     or to_regclass('public.onexa_project_cost_centers') is null
     or to_regclass('public.ops_work_orders') is null
     or to_regprocedure('public.ops_has_company_access(uuid)') is null then
    raise exception 'ONEXA_GATE66_FOUNDATION_REQUIRED';
  end if;
  if to_regprocedure('public.onexa_approval_separation_required(text,text)') is null
     or to_regprocedure('onexa_private.guard_approval_posting()') is null
     or not exists (select 1 from pg_trigger
       where tgname='onexa_guard_approval_posting'
         and tgrelid=to_regclass('public.onexa_business_documents')
         and tgenabled<>'D' and not tgisinternal) then
    raise exception 'ONEXA_GATE64_APPROVAL_POSTING_BRIDGE_REQUIRED';
  end if;
end;
$preflight$;

create table if not exists public.onexa_maintenance_work_order_scopes (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  work_order_id uuid not null unique references public.ops_work_orders(id) on delete restrict,
  project_cost_center_id uuid not null references public.onexa_project_cost_centers(id) on delete restrict,
  is_active boolean not null default true,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, work_order_id)
);

create table if not exists public.onexa_maintenance_work_order_cost_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  scope_id uuid not null references public.onexa_maintenance_work_order_scopes(id) on delete restrict,
  work_order_id uuid not null references public.ops_work_orders(id) on delete restrict,
  cost_source text not null check (cost_source in ('material','subcontract','labor','other')),
  external_reference text not null check (length(btrim(external_reference))>0),
  amount numeric(20,4) not null check (amount>0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision>0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, external_reference)
);

create index if not exists onexa_maintenance_cost_postings_work_order_idx
  on public.onexa_maintenance_work_order_cost_postings (tenant_id,work_order_id,posted_at desc);

create or replace function public.onexa_guard_posted_maintenance_scope()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if exists (select 1 from public.onexa_maintenance_work_order_cost_postings p where p.scope_id=old.id) then
    if tg_op='DELETE' then raise exception 'ONEXA_POSTED_MAINTENANCE_SCOPE_IMMUTABLE'; end if;
    if row(new.tenant_id,new.legal_entity_id,new.branch_id,new.work_order_id,new.project_cost_center_id)
       is distinct from row(old.tenant_id,old.legal_entity_id,old.branch_id,old.work_order_id,old.project_cost_center_id) then
      raise exception 'ONEXA_POSTED_MAINTENANCE_SCOPE_IMMUTABLE';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  new.updated_at:=now();
  return new;
end;
$$;
drop trigger if exists onexa_guard_posted_maintenance_scope on public.onexa_maintenance_work_order_scopes;
create trigger onexa_guard_posted_maintenance_scope before update or delete
on public.onexa_maintenance_work_order_scopes for each row
execute function public.onexa_guard_posted_maintenance_scope();

alter table public.onexa_maintenance_work_order_scopes enable row level security;
alter table public.onexa_maintenance_work_order_cost_postings enable row level security;
drop policy if exists onexa_maintenance_work_order_scopes_read on public.onexa_maintenance_work_order_scopes;
create policy onexa_maintenance_work_order_scopes_read
on public.onexa_maintenance_work_order_scopes for select to authenticated
using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'projects','read'));
drop policy if exists onexa_maintenance_work_order_cost_postings_read on public.onexa_maintenance_work_order_cost_postings;
create policy onexa_maintenance_work_order_cost_postings_read
on public.onexa_maintenance_work_order_cost_postings for select to authenticated
using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'projects','read'));

create or replace function public.onexa_save_maintenance_work_order_scope(
  _work_order_id uuid,
  _project_cost_center_id uuid
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _work_order public.ops_work_orders%rowtype;
  _center public.onexa_project_cost_centers%rowtype;
  _scope_id uuid;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'projects','create') then
    raise exception 'ONEXA_MAINTENANCE_SCOPE_NOT_AUTHORIZED'; end if;
  select * into _work_order from public.ops_work_orders where id=_work_order_id for update;
  if not found or not public.ops_has_company_access(_work_order.company_id) then
    raise exception 'ONEXA_MAINTENANCE_WORK_ORDER_NOT_ACCESSIBLE'; end if;
  if _work_order.status not in ('completed','accepted') then
    raise exception 'ONEXA_MAINTENANCE_WORK_ORDER_MUST_BE_COMPLETED'; end if;
  select * into _center from public.onexa_project_cost_centers
  where id=_project_cost_center_id and tenant_id=_tenant and is_active for update;
  if not found then raise exception 'ONEXA_PROJECT_CENTER_REQUIRED'; end if;
  insert into public.onexa_maintenance_work_order_scopes
    (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id,created_by)
  values (_tenant,_center.legal_entity_id,_center.branch_id,_work_order.id,_center.id,_actor)
  on conflict (work_order_id) do update set
    tenant_id=excluded.tenant_id,legal_entity_id=excluded.legal_entity_id,
    branch_id=excluded.branch_id,project_cost_center_id=excluded.project_cost_center_id,
    is_active=true,updated_at=now()
  returning id into _scope_id;
  return _scope_id;
end;
$$;

create or replace view public.onexa_maintenance_work_order_cost_scopes
with (security_invoker=true) as
select scope.id,scope.tenant_id,scope.legal_entity_id,scope.branch_id,
  scope.work_order_id,work_order.work_order_no,work_order.title as work_order_title,
  work_order.status as work_order_status,work_order.asset_id,
  center.project_code,center.project_name,center.cost_center_code,scope.is_active
from public.onexa_maintenance_work_order_scopes scope
join public.ops_work_orders work_order on work_order.id=scope.work_order_id
join public.onexa_project_cost_centers center
  on center.id=scope.project_cost_center_id and center.tenant_id=scope.tenant_id
where scope.is_active and center.is_active and work_order.status in ('completed','accepted');

create or replace view public.onexa_maintenance_work_order_cost_reconciliation
with (security_invoker=true) as
select document.id as document_id,document.tenant_id,document.legal_entity_id,
  document.document_number,document.status,document.gross_total,
  posting.amount as posted_amount,posting.cost_source,posting.journal_id,
  work_order.work_order_no,center.project_code,center.cost_center_code,
  case when document.status<>'posted' then 'not_posted'
    when posting.journal_id is distinct from document.posted_journal_id then 'journal_mismatch'
    when journal.id is null then 'journal_reversed_or_missing'
    when journal.source_document_type is distinct from 'maintenance_work_order_cost'
      or journal.source_document_id is distinct from document.id::text
      or journal.total_debit is distinct from document.gross_total
      or journal.total_credit is distinct from document.gross_total
      or journal.currency is distinct from document.currency
      then 'journal_source_or_amount_mismatch'
    when posting.amount is distinct from document.gross_total then 'amount_mismatch'
    when scope.id is null or work_order.id is null or center.id is null then 'scope_missing'
    when scope.legal_entity_id is distinct from document.legal_entity_id
      or scope.branch_id is distinct from document.branch_id
      or center.legal_entity_id is distinct from document.legal_entity_id
      or center.branch_id is distinct from document.branch_id
      then 'scope_entity_branch_mismatch'
    else 'reconciled' end as reconciliation_status
from public.onexa_business_documents document
left join public.onexa_maintenance_work_order_cost_postings posting
  on posting.document_id=document.id and posting.tenant_id=document.tenant_id
  and posting.legal_entity_id=document.legal_entity_id
left join public.onexa_journal_headers journal
  on journal.id=posting.journal_id and journal.tenant_id=document.tenant_id
 and journal.legal_entity_id=document.legal_entity_id
 and journal.state='posted' and journal.reversal_journal_id is null
left join public.onexa_maintenance_work_order_scopes scope
  on scope.id=posting.scope_id and scope.tenant_id=document.tenant_id
left join public.ops_work_orders work_order on work_order.id=posting.work_order_id
left join public.onexa_project_cost_centers center on center.id=scope.project_cost_center_id
where document.document_type='maintenance_work_order_cost';

create or replace view public.onexa_maintenance_posting_configuration_gaps
with (security_invoker=true) as
with required_roles(account_role) as (values
  ('maintenance_project_cost'::text),('maintenance_material_clearing'::text),
  ('maintenance_subcontract_clearing'::text),('maintenance_labor_clearing'::text),
  ('maintenance_other_clearing'::text)
)
select entity.tenant_id,entity.id as legal_entity_id,entity.code as legal_entity_code,required.account_role
from public.onexa_legal_entities entity cross join required_roles required
left join public.onexa_account_role_mappings mapping
  on mapping.tenant_id=entity.tenant_id and mapping.legal_entity_id=entity.id
 and mapping.account_role=required.account_role and mapping.is_active
left join public.chart_of_accounts account
  on account.tenant_id=mapping.tenant_id and account.code=mapping.account_code
 and account.is_active and account.account_type::text='detail'
 and ((required.account_role='maintenance_project_cost'
       and account.category::text in ('assets','expenses','cost_of_revenue'))
   or (required.account_role<>'maintenance_project_cost'
       and account.category::text='liabilities'))
where entity.is_active and (mapping.id is null or account.code is null);

create or replace function public.onexa_post_maintenance_work_order_cost(
  _document_id uuid,
  _period_code text
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _document public.onexa_business_documents%rowtype;
  _line public.onexa_business_document_lines%rowtype;
  _scope public.onexa_maintenance_work_order_scopes%rowtype;
  _center public.onexa_project_cost_centers%rowtype;
  _work_order public.ops_work_orders%rowtype;
  _posting public.onexa_maintenance_work_order_cost_postings%rowtype;
  _cost_source text;
  _credit_role text;
  _debit text;
  _credit text;
  _reference text;
  _dimensions jsonb;
  _journal uuid;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'projects','post') then
    raise exception 'ONEXA_MAINTENANCE_COST_POST_NOT_AUTHORIZED'; end if;
  if coalesce(btrim(_period_code),'') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'ONEXA_MAINTENANCE_COST_PERIOD_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant||':maintenance-cost:'||_document_id::text,0));
  select * into _document from public.onexa_business_documents
  where id=_document_id and tenant_id=_tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  select * into _posting from public.onexa_maintenance_work_order_cost_postings
  where document_id=_document.id and tenant_id=_tenant;
  if _document.status='posted' then
    if _document.posted_journal_id is not null
       and _posting.journal_id is not distinct from _document.posted_journal_id then
      perform 1 from public.onexa_journal_headers journal
        where journal.id=_document.posted_journal_id and journal.tenant_id=_tenant
          and journal.legal_entity_id=_document.legal_entity_id
          and journal.state='posted' and journal.reversal_journal_id is null;
      if not found then raise exception 'ONEXA_MAINTENANCE_JOURNAL_REVERSED_OR_MISSING'; end if;
      return _document.posted_journal_id;
    end if;
    raise exception 'ONEXA_MAINTENANCE_COST_RETRY_STATE_INVALID';
  end if;
  if _document.document_type<>'maintenance_work_order_cost' or _document.module_key<>'projects' then
    raise exception 'ONEXA_MAINTENANCE_COST_DOCUMENT_REQUIRED'; end if;
  if _document.status<>'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _actor=_document.created_by
     and public.onexa_approval_separation_required(_document.document_type,'post') then
    raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _document.branch_id is null or _document.currency<>'SAR'
    or _document.party_id is not null or _document.party_type is not null
    or _document.origin<>'native' or _document.gross_total<=0
    or _document.tax_total<>0 or _document.discount_total<>0
    or _document.subtotal<>_document.gross_total then
    raise exception 'ONEXA_MAINTENANCE_COST_DOCUMENT_INVALID'; end if;
  select * into _line from public.onexa_business_document_lines
  where document_id=_document.id and tenant_id=_tenant;
  if not found or (select count(*) from public.onexa_business_document_lines where document_id=_document.id)<>1
    or _line.item_id is not null or _line.tax_amount<>0
    or _line.net_amount<>_document.gross_total or _line.gross_amount<>_document.gross_total then
    raise exception 'ONEXA_MAINTENANCE_COST_LINE_MISMATCH'; end if;
  if _document.source_snapshot->>'source_kind' is distinct from 'unpaid_maintenance_cost' then
    raise exception 'ONEXA_MAINTENANCE_COST_SOURCE_KIND_INVALID'; end if;
  _cost_source:=nullif(_document.source_snapshot->>'cost_source','');
  _credit_role:=case _cost_source
    when 'material' then 'maintenance_material_clearing'
    when 'subcontract' then 'maintenance_subcontract_clearing'
    when 'labor' then 'maintenance_labor_clearing'
    when 'other' then 'maintenance_other_clearing'
    else null end;
  if _credit_role is null or _line.account_role is distinct from _credit_role then
    raise exception 'ONEXA_MAINTENANCE_COST_SOURCE_INVALID'; end if;
  if nullif(_document.source_snapshot->>'maintenance_scope_id','') is null then
    raise exception 'ONEXA_MAINTENANCE_SCOPE_REQUIRED'; end if;
  select * into _scope from public.onexa_maintenance_work_order_scopes
  where id=(_document.source_snapshot->>'maintenance_scope_id')::uuid
    and tenant_id=_tenant for update;
  if not found or not _scope.is_active
    or _scope.legal_entity_id is distinct from _document.legal_entity_id
    or _scope.branch_id is distinct from _document.branch_id then
    raise exception 'ONEXA_MAINTENANCE_SCOPE_INVALID'; end if;
  select * into _center from public.onexa_project_cost_centers
  where id=_scope.project_cost_center_id and tenant_id=_tenant and is_active for update;
  select * into _work_order from public.ops_work_orders where id=_scope.work_order_id for update;
  if _center.id is null or _work_order.id is null
    or _center.legal_entity_id is distinct from _scope.legal_entity_id
    or _center.branch_id is distinct from _scope.branch_id
    or not public.ops_has_company_access(_work_order.company_id)
    or _work_order.status not in ('completed','accepted')
    or _document.source_snapshot->>'work_order_id' is distinct from _work_order.id::text
    or _document.dimensions->>'project' is distinct from _center.project_code
    or _document.dimensions->>'costCenter' is distinct from _center.cost_center_code
    or (_work_order.asset_id is not null
      and _document.dimensions->>'asset' is distinct from _work_order.asset_id::text) then
    raise exception 'ONEXA_MAINTENANCE_WORK_ORDER_SCOPE_MISMATCH'; end if;
  _reference:=nullif(btrim(_document.external_reference),'');
  if _reference is null then raise exception 'ONEXA_MAINTENANCE_COST_EXTERNAL_REFERENCE_REQUIRED'; end if;
  if exists (select 1 from public.onexa_maintenance_work_order_cost_postings
    where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
      and external_reference=_reference) then
    raise exception 'ONEXA_MAINTENANCE_COST_REFERENCE_ALREADY_POSTED'; end if;
  select account_code into _debit from public.onexa_account_role_mappings
  where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
    and account_role='maintenance_project_cost' and is_active;
  select account_code into _credit from public.onexa_account_role_mappings
  where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
    and account_role=_credit_role and is_active;
  if _debit is null or _credit is null or _debit=_credit
    or not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant
      and code=_debit and is_active and account_type::text='detail'
      and category::text in ('assets','expenses','cost_of_revenue'))
    or not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant
      and code=_credit and is_active and account_type::text='detail'
      and category::text='liabilities') then
    raise exception 'ONEXA_MAINTENANCE_COST_ACCOUNT_MAPPING_REQUIRED'; end if;
  _dimensions:=_document.dimensions||jsonb_build_object(
    'legalEntity',_document.legal_entity_id,'branch',_document.branch_id,
    'workOrder',_work_order.work_order_no);
  _journal:=public.onexa_post_journal(
    _document.legal_entity_id,'maintenance_work_order_cost',_document.id::text,
    _document.revision,'approved',_document.source_snapshot||jsonb_build_object(
      'document_number',_document.document_number,'external_reference',_reference,
      'posting_contract_version','maintenance-work-order-cost-v1'),
    _document.accounting_date,btrim(_period_code),'SAR',
    coalesce(_document.memo,'Maintenance work-order cost '||_document.document_number),
    jsonb_build_array(
      jsonb_build_object('account_code',_debit,'debit',_document.gross_total,'credit',0,
        'description','Maintenance project cost - '||_work_order.work_order_no,'dimensions',_dimensions),
      jsonb_build_object('account_code',_credit,'debit',0,'credit',_document.gross_total,
        'description','Maintenance cost clearing - '||_cost_source,'dimensions',_dimensions)
    ));
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;
  insert into public.onexa_maintenance_work_order_cost_postings
    (document_id,tenant_id,legal_entity_id,scope_id,work_order_id,cost_source,
     external_reference,amount,journal_id,source_revision,posted_by)
  values (_document.id,_tenant,_document.legal_entity_id,_scope.id,_work_order.id,
    _cost_source,_reference,_document.gross_total,_journal,_document.revision,_actor);
  perform set_config('onexa.transition_authorized','true',true);
  perform set_config('onexa.transition_reason','posted_from_maintenance_work_order_cost',true);
  update public.onexa_business_documents set status='posted',posted_by=_actor,
    posted_at=now(),posted_journal_id=_journal,posting_error=null
  where id=_document.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id,document_id,event_type,from_status,to_status,actor_id,event_data)
  values (_tenant,_document.id,'posting_completed','approved','posted',_actor,
    jsonb_build_object('journal_id',_journal,'work_order_id',_work_order.id,
      'cost_source',_cost_source,'posting_contract_version','maintenance-work-order-cost-v1'));
  return _journal;
end;
$$;

revoke all on public.onexa_maintenance_work_order_scopes,
  public.onexa_maintenance_work_order_cost_postings from anon,authenticated;
grant select on public.onexa_maintenance_work_order_scopes,
  public.onexa_maintenance_work_order_cost_postings to authenticated;
grant select on public.onexa_maintenance_work_order_cost_scopes,
  public.onexa_maintenance_work_order_cost_reconciliation,
  public.onexa_maintenance_posting_configuration_gaps to authenticated;
revoke all on function public.onexa_save_maintenance_work_order_scope(uuid,uuid) from public,anon;
grant execute on function public.onexa_save_maintenance_work_order_scope(uuid,uuid) to authenticated;
revoke all on function public.onexa_post_maintenance_work_order_cost(uuid,text) from public,anon;
grant execute on function public.onexa_post_maintenance_work_order_cost(uuid,text) to authenticated;
revoke all on function public.onexa_guard_posted_maintenance_scope() from public,anon,authenticated;
commit;
