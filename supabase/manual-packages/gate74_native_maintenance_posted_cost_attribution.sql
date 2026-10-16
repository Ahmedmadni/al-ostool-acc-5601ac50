-- Gate 74: native maintenance cost attribution of EXISTING Gate 42 postings.
-- Source-only manual package. NEVER creates an additional journal/accrual.
-- G42 source costs must not have already been recorded by invoice, stock, payroll
-- or legacy Gate66; attribution only labels one existing posted journal.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_native_maintenance_cost_scopes') is not null
     or to_regclass('public.onexa_native_maintenance_cost_attributions') is not null
     or to_regclass('public.onexa_native_maintenance_cost_reconciliation') is not null
     or to_regprocedure('public.onexa_save_native_maintenance_cost_scope(uuid,uuid)') is not null
     or to_regprocedure('public.onexa_attribute_posted_project_cost(uuid,uuid)') is not null then
    raise exception 'ONEXA_GATE74_PARTIAL_OR_ALREADY_INSTALLED_STOP';
  end if;
  if to_regclass('public.onexa_operations_work_orders') is null
     or to_regclass('public.onexa_operations_sites') is null
     or to_regclass('public.onexa_company_module_scopes') is null
     or to_regclass('public.onexa_project_cost_centers') is null
     or to_regclass('public.onexa_project_cost_postings') is null
     or to_regclass('public.onexa_business_documents') is null
     or to_regclass('public.onexa_journal_headers') is null
     or to_regprocedure('public.onexa_has_company_module_access(text,text)') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null then
    raise exception 'ONEXA_GATE74_G42_G71_G72_G73_AND_B4_REQUIRED';
  end if;
end
$preflight$;

-- Referenced composite identities: a source posted for company B cannot be
-- attributed to a work order / project center of company A.
-- Creating these indexes on existing customer tables requires a reviewed lock
-- budget, a restorable backup and a successful disposable-clone preflight.
create unique index if not exists onexa_native_wo_tenant_entity_branch_id_uq
  on public.onexa_operations_work_orders(tenant_id,legal_entity_id,branch_id,id);
create unique index if not exists onexa_project_center_tenant_entity_branch_id_uq
  on public.onexa_project_cost_centers(tenant_id,legal_entity_id,branch_id,id);
create unique index if not exists onexa_project_posting_tenant_entity_center_document_uq
  on public.onexa_project_cost_postings(tenant_id,legal_entity_id,project_cost_center_id,document_id);

create table public.onexa_native_maintenance_cost_scopes (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null references public.onexa_tenants(tenant_id) on delete restrict,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  work_order_id uuid not null,
  project_cost_center_id uuid not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint onexa_native_cost_scope_work_order_fk
    foreign key (tenant_id,legal_entity_id,branch_id,work_order_id)
    references public.onexa_operations_work_orders(tenant_id,legal_entity_id,branch_id,id)
    on delete restrict,
  constraint onexa_native_cost_scope_center_fk
    foreign key (tenant_id,legal_entity_id,branch_id,project_cost_center_id)
    references public.onexa_project_cost_centers(tenant_id,legal_entity_id,branch_id,id)
    on delete restrict,
  constraint onexa_native_cost_scope_one_per_order_uq
    unique(tenant_id,work_order_id),
  constraint onexa_native_cost_scope_composite_uq
    unique(tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)
);

create table public.onexa_native_maintenance_cost_attributions (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  work_order_id uuid not null,
  project_cost_center_id uuid not null,
  document_id uuid not null,
  journal_id uuid not null,
  amount numeric(20,4) not null check(amount>0),
  source_revision integer not null check(source_revision>0),
  attributed_by uuid not null references auth.users(id),
  attributed_at timestamptz not null default now(),
  constraint onexa_native_cost_attr_scope_fk
    foreign key (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)
    references public.onexa_native_maintenance_cost_scopes
      (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)
    on delete restrict,
  constraint onexa_native_cost_attr_posted_source_fk
    foreign key (tenant_id,legal_entity_id,project_cost_center_id,document_id)
    references public.onexa_project_cost_postings
      (tenant_id,legal_entity_id,project_cost_center_id,document_id)
    on delete restrict,
  constraint onexa_native_cost_attr_document_once_uq
    unique(tenant_id,document_id)
);

create index onexa_native_cost_attr_work_order_idx
  on public.onexa_native_maintenance_cost_attributions(tenant_id,work_order_id,attributed_at desc);

alter table public.onexa_native_maintenance_cost_scopes enable row level security;
alter table public.onexa_native_maintenance_cost_attributions enable row level security;

create policy onexa_native_maintenance_scopes_read
  on public.onexa_native_maintenance_cost_scopes for select to authenticated
  using (tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null and onexa_private.is_active_member(auth.uid())
    and onexa_private.has_module_action(auth.uid(),'projects','read')
    and exists (select 1 from public.onexa_operations_work_orders w
      where w.id=work_order_id and w.tenant_id=onexa_native_maintenance_cost_scopes.tenant_id
        and w.legal_entity_id=onexa_native_maintenance_cost_scopes.legal_entity_id
        and w.branch_id=onexa_native_maintenance_cost_scopes.branch_id));

create policy onexa_native_maintenance_attributions_read
  on public.onexa_native_maintenance_cost_attributions for select to authenticated
  using (tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null and onexa_private.is_active_member(auth.uid())
    and onexa_private.has_module_action(auth.uid(),'projects','read')
    and exists (select 1 from public.onexa_native_maintenance_cost_scopes s
      where s.work_order_id=onexa_native_maintenance_cost_attributions.work_order_id
        and s.tenant_id=onexa_native_maintenance_cost_attributions.tenant_id
        and s.legal_entity_id=onexa_native_maintenance_cost_attributions.legal_entity_id
        and s.branch_id=onexa_native_maintenance_cost_attributions.branch_id
        and s.project_cost_center_id=onexa_native_maintenance_cost_attributions.project_cost_center_id));

-- Immutable records; only independently authorized, audited RPC entry points
-- can create mappings. No UPDATE or DELETE, even via service-role DML.
create function onexa_private.guard_native_maintenance_attribution_write()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  if tg_op<>'INSERT' then
    raise exception 'ONEXA_GATE74_FINANCE_ATTRIBUTION_IMMUTABLE';
  end if;
  if coalesce(current_setting('onexa.gate74_write_authorized',true),'')<>'true' then
    raise exception 'ONEXA_GATE74_AUTHORIZED_RPC_REQUIRED';
  end if;
  return new;
end;
$$;

create trigger onexa_guard_native_maintenance_cost_scope_write
  before insert or update or delete on public.onexa_native_maintenance_cost_scopes
  for each row execute function onexa_private.guard_native_maintenance_attribution_write();
create trigger onexa_guard_native_maintenance_cost_attr_write
  before insert or update or delete on public.onexa_native_maintenance_cost_attributions
  for each row execute function onexa_private.guard_native_maintenance_attribution_write();

-- One independently approved center per accepted maintenance work order.
-- No auto-reassignment; mis-mappings require controlled correction workflow,
-- rather than altering existing attribution metadata or financial history.
create function public.onexa_save_native_maintenance_cost_scope(
  _work_order_id uuid,_project_cost_center_id uuid
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _work public.onexa_operations_work_orders%rowtype;
  _center public.onexa_project_cost_centers%rowtype;
  _scope_id uuid;
begin
  if _actor is null or nullif(_tenant,'') is null
    or not onexa_private.is_active_member(_actor)
    or not onexa_private.has_module_action(_actor,'projects','create')
    or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_GATE74_SCOPE_NOT_AUTHORIZED';
  end if;
  select * into _work from public.onexa_operations_work_orders
    where id=_work_order_id and tenant_id=_tenant for update;
  if _work.id is null or _work.status<>'accepted' then
    raise exception 'ONEXA_GATE74_ACCEPTED_NATIVE_WORK_ORDER_REQUIRED';
  end if;
  if not exists (
    select 1 from public.onexa_operations_sites site
    join public.onexa_company_module_scopes company
      on company.id=site.company_scope_id and company.tenant_id=site.tenant_id
     and company.legal_entity_id=site.legal_entity_id
    join public.onexa_branches branch
      on branch.id=site.branch_id and branch.tenant_id=site.tenant_id
     and branch.legal_entity_id=site.legal_entity_id
    join public.onexa_legal_entities entity
      on entity.id=site.legal_entity_id and entity.tenant_id=site.tenant_id
    where site.id=_work.site_id and site.tenant_id=_tenant
      and site.legal_entity_id=_work.legal_entity_id
      and site.branch_id=_work.branch_id
      and site.is_active and company.is_active and branch.is_active and entity.is_active
      and company.legacy_company_code='OM' and company.module_key='projects'
  ) then
    raise exception 'ONEXA_GATE74_WORK_ORDER_COMPANY_SCOPE_INVALID';
  end if;
  select * into _center from public.onexa_project_cost_centers
    where id=_project_cost_center_id and tenant_id=_tenant for update;
  if _center.id is null or not _center.is_active
     or _center.legal_entity_id is distinct from _work.legal_entity_id
     or _center.branch_id is distinct from _work.branch_id then
    raise exception 'ONEXA_GATE74_COST_CENTER_SCOPE_MISMATCH';
  end if;

  select id into _scope_id from public.onexa_native_maintenance_cost_scopes
    where tenant_id=_tenant and work_order_id=_work.id for update;
  if _scope_id is not null then
    if not exists (
      select 1 from public.onexa_native_maintenance_cost_scopes
      where id=_scope_id and tenant_id=_tenant
        and project_cost_center_id=_center.id
    ) then
      raise exception 'ONEXA_GATE74_COST_CENTER_REASSIGNMENT_FORBIDDEN';
    end if;
    return _scope_id;
  end if;
  perform set_config('onexa.gate74_write_authorized','true',true);
  insert into public.onexa_native_maintenance_cost_scopes
    (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id,created_by)
  values (_tenant,_work.legal_entity_id,_work.branch_id,_work.id,_center.id,_actor)
  returning id into _scope_id;
  perform set_config('onexa.gate74_write_authorized','',true);
  return _scope_id;
end;
$$;

-- Attribution of already posted Gate42 project cost. Never creates a new
-- journal; never posts Gate66 cost, supplier invoice, payroll or stock again.
create function public.onexa_attribute_posted_project_cost(
  _work_order_id uuid,_document_id uuid
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _work public.onexa_operations_work_orders%rowtype;
  _scope public.onexa_native_maintenance_cost_scopes%rowtype;
  _document public.onexa_business_documents%rowtype;
  _posting public.onexa_project_cost_postings%rowtype;
  _journal public.onexa_journal_headers%rowtype;
  _existing public.onexa_native_maintenance_cost_attributions%rowtype;
  _attr_id uuid;
begin
  if _actor is null or nullif(_tenant,'') is null
    or not onexa_private.is_active_member(_actor)
    or not onexa_private.has_module_action(_actor,'projects','approve')
    or not onexa_private.has_module_action(_actor,'finance','read')
    or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_GATE74_ATTRIBUTION_NOT_AUTHORIZED';
  end if;
  select * into _work from public.onexa_operations_work_orders
    where id=_work_order_id and tenant_id=_tenant for update;
  if _work.id is null or _work.status<>'accepted' then
    raise exception 'ONEXA_GATE74_ACCEPTED_NATIVE_WORK_ORDER_REQUIRED';
  end if;
  if _actor=_work.created_by or _actor=_work.completed_by then
    raise exception 'ONEXA_GATE74_FINANCE_ATTRIBUTION_SEPARATION_REQUIRED';
  end if;
  select * into _scope from public.onexa_native_maintenance_cost_scopes
    where tenant_id=_tenant and work_order_id=_work.id for update;
  if _scope.id is null or _scope.legal_entity_id is distinct from _work.legal_entity_id
    or _scope.branch_id is distinct from _work.branch_id
    or not exists (select 1 from public.onexa_project_cost_centers center
      where center.id=_scope.project_cost_center_id and center.tenant_id=_tenant
        and center.legal_entity_id=_work.legal_entity_id
        and center.branch_id=_work.branch_id and center.is_active)
    or not exists (select 1 from public.onexa_operations_sites site
      join public.onexa_company_module_scopes company
        on company.id=site.company_scope_id and company.tenant_id=site.tenant_id
       and company.legal_entity_id=site.legal_entity_id
      join public.onexa_branches branch
        on branch.id=site.branch_id and branch.tenant_id=site.tenant_id
       and branch.legal_entity_id=site.legal_entity_id
      join public.onexa_legal_entities entity
        on entity.id=site.legal_entity_id and entity.tenant_id=site.tenant_id
      where site.id=_work.site_id and site.tenant_id=_tenant
        and site.legal_entity_id=_work.legal_entity_id and site.branch_id=_work.branch_id
        and site.is_active and company.is_active and branch.is_active and entity.is_active
        and company.legacy_company_code='OM' and company.module_key='projects') then
    raise exception 'ONEXA_GATE74_WORK_ORDER_COST_SCOPE_INVALID';
  end if;

  select * into _document from public.onexa_business_documents
    where id=_document_id and tenant_id=_tenant for update;
  if _document.id is null or _document.document_type<>'project_cost'
    or _document.module_key<>'projects'
    or _document.status<>'posted' or _document.posted_journal_id is null
    or _document.legal_entity_id is distinct from _work.legal_entity_id
    or _document.branch_id is distinct from _work.branch_id
    or _document.currency<>'SAR'
    or _document.source_snapshot->>'source_kind' is distinct from 'unpaid_direct_cost'
    or _document.gross_total<=0
    or _document.tax_total<>0 or _document.discount_total<>0
    or _document.subtotal is distinct from _document.gross_total then
    raise exception 'ONEXA_GATE74_SOURCE_DOCUMENT_NOT_POSTED_PROJECT_COST';
  end if;
  select * into _posting from public.onexa_project_cost_postings
    where document_id=_document.id and tenant_id=_tenant
      and legal_entity_id=_work.legal_entity_id for update;
  if _posting.document_id is null
    or _posting.project_cost_center_id is distinct from _scope.project_cost_center_id
    or _posting.amount is distinct from _document.gross_total
    or _posting.source_revision is distinct from _document.revision
    or _posting.journal_id is distinct from _document.posted_journal_id then
    raise exception 'ONEXA_GATE74_PROJECT_COST_POSTING_NOT_RECONCILED';
  end if;
  if _actor=_posting.posted_by then
    raise exception 'ONEXA_GATE74_ATTRIBUTOR_MUST_DIFFER_FROM_POSTER';
  end if;
  select * into _journal from public.onexa_journal_headers
    where id=_posting.journal_id and tenant_id=_tenant
      and legal_entity_id=_work.legal_entity_id for update;
  if _journal.id is null or _journal.state<>'posted'
     or _journal.reversal_journal_id is not null or _journal.reversal_of_id is not null
     or _journal.source_document_type is distinct from 'project_cost'
     or _journal.source_document_id is distinct from _document.id::text
     or _journal.source_revision is distinct from _document.revision
     or _journal.currency is distinct from _document.currency
     or _journal.total_debit is distinct from _document.gross_total
     or _journal.total_credit is distinct from _document.gross_total then
    raise exception 'ONEXA_GATE74_ORIGINAL_GL_JOURNAL_REVERSED_OR_MISMATCHED';
  end if;
  select * into _existing from public.onexa_native_maintenance_cost_attributions
    where tenant_id=_tenant and document_id=_document.id for update;
  if _existing.id is not null then
    if _existing.work_order_id is distinct from _work.id
      or _existing.project_cost_center_id is distinct from _scope.project_cost_center_id
      or _existing.journal_id is distinct from _journal.id
      or _existing.amount is distinct from _document.gross_total
      or _existing.source_revision is distinct from _document.revision then
      raise exception 'ONEXA_GATE74_PROJECT_COST_ALREADY_ATTRIBUTED_ELSEWHERE';
    end if;
    return _existing.id;
  end if;
  perform set_config('onexa.gate74_write_authorized','true',true);
  insert into public.onexa_native_maintenance_cost_attributions
    (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id,
     document_id,journal_id,amount,source_revision,attributed_by)
  values (_tenant,_work.legal_entity_id,_work.branch_id,_work.id,
    _scope.project_cost_center_id,_document.id,_journal.id,_document.gross_total,
    _document.revision,_actor)
  returning id into _attr_id;
  perform set_config('onexa.gate74_write_authorized','',true);
  return _attr_id;
end;
$$;

-- Current book-based reconciliation: historical-as-of is separately scoped.
-- Do not count reversed/missing GL sources as currently attributable costs.
create view public.onexa_native_maintenance_cost_reconciliation
with (security_invoker=true) as
select a.id as attribution_id,a.tenant_id,a.legal_entity_id,a.branch_id,
  a.work_order_id,a.project_cost_center_id,a.document_id,a.journal_id,
  a.amount as attributed_amount,
  d.document_number,d.status as document_status,
  j.state as journal_state,
  case
    when w.id is null or w.status<>'accepted' then 'work_order_not_accepted'
    when s.id is null or s.project_cost_center_id is distinct from a.project_cost_center_id
      then 'scope_missing_or_mismatched'
    when center.id is null or not center.is_active then 'cost_center_inactive_or_missing'
    when d.id is null or d.status<>'posted' or d.document_type<>'project_cost'
      then 'document_not_posted_project_cost'
    when p.document_id is null or p.journal_id is distinct from a.journal_id
      or p.amount is distinct from a.amount
      or p.source_revision is distinct from a.source_revision then 'project_posting_mismatch'
    when j.id is null or j.state<>'posted' or j.reversal_journal_id is not null
      or j.reversal_of_id is not null then 'journal_reversed_or_missing'
    when j.source_document_type is distinct from 'project_cost'
      or j.source_document_id is distinct from a.document_id::text
      or j.source_revision is distinct from a.source_revision
      or j.currency is distinct from d.currency
      or j.total_debit is distinct from a.amount
      or j.total_credit is distinct from a.amount
      or d.posted_journal_id is distinct from a.journal_id
      or d.gross_total is distinct from a.amount
      then 'journal_source_or_amount_mismatch'
    else 'reconciled'
  end as reconciliation_status
from public.onexa_native_maintenance_cost_attributions a
left join public.onexa_native_maintenance_cost_scopes s
  on s.tenant_id=a.tenant_id and s.work_order_id=a.work_order_id
  and s.legal_entity_id=a.legal_entity_id and s.branch_id=a.branch_id
left join public.onexa_operations_work_orders w
  on w.tenant_id=a.tenant_id and w.id=a.work_order_id
  and w.legal_entity_id=a.legal_entity_id and w.branch_id=a.branch_id
left join public.onexa_project_cost_centers center
  on center.tenant_id=a.tenant_id and center.id=a.project_cost_center_id
  and center.legal_entity_id=a.legal_entity_id and center.branch_id=a.branch_id
left join public.onexa_business_documents d
  on d.tenant_id=a.tenant_id and d.id=a.document_id
  and d.legal_entity_id=a.legal_entity_id and d.branch_id=a.branch_id
left join public.onexa_project_cost_postings p
  on p.tenant_id=a.tenant_id and p.legal_entity_id=a.legal_entity_id
  and p.project_cost_center_id=a.project_cost_center_id and p.document_id=a.document_id
left join public.onexa_journal_headers j
  on j.id=a.journal_id and j.tenant_id=a.tenant_id
  and j.legal_entity_id=a.legal_entity_id;

create view public.onexa_native_maintenance_work_order_cost_totals
with (security_invoker=true) as
select r.tenant_id,r.legal_entity_id,r.branch_id,r.work_order_id,
  count(*) filter(where r.reconciliation_status='reconciled') as reconciled_documents,
  count(*) filter(where r.reconciliation_status<>'reconciled') as anomaly_documents,
  coalesce(sum(r.attributed_amount) filter(where r.reconciliation_status='reconciled'),0)
    as reconciled_project_cost_total
from public.onexa_native_maintenance_cost_reconciliation r
group by r.tenant_id,r.legal_entity_id,r.branch_id,r.work_order_id;

revoke all on public.onexa_native_maintenance_cost_scopes,
  public.onexa_native_maintenance_cost_attributions from public,anon,authenticated;
grant select on public.onexa_native_maintenance_cost_scopes,
  public.onexa_native_maintenance_cost_attributions to authenticated;
grant all on public.onexa_native_maintenance_cost_scopes,
  public.onexa_native_maintenance_cost_attributions to service_role;
revoke all on public.onexa_native_maintenance_cost_reconciliation,
  public.onexa_native_maintenance_work_order_cost_totals from public,anon;
grant select on public.onexa_native_maintenance_cost_reconciliation,
  public.onexa_native_maintenance_work_order_cost_totals to authenticated;
revoke all on function public.onexa_save_native_maintenance_cost_scope(uuid,uuid),
  public.onexa_attribute_posted_project_cost(uuid,uuid) from public,anon;
grant execute on function public.onexa_save_native_maintenance_cost_scope(uuid,uuid),
  public.onexa_attribute_posted_project_cost(uuid,uuid) to authenticated;
revoke all on function onexa_private.guard_native_maintenance_attribution_write()
  from public,anon,authenticated;

commit;
