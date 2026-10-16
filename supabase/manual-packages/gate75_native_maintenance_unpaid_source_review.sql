-- ONEXA Gate 75: evidence/review for NEW, genuinely unpaid maintenance sources.
-- MANUAL ROLLOUT ONLY: this package DOES NOT create a project-cost document,
-- recognize an expense, call onexa_post_journal, move stock, or post payroll.
-- Approved sources go through the existing G42/G64 finance workflow, then G74.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_native_maintenance_unpaid_sources') is not null
     or to_regclass('public.onexa_native_maintenance_source_reconciliation') is not null
     or to_regprocedure('public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text)') is not null
     or to_regprocedure('public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text)') is not null
     or to_regprocedure('public.onexa_link_native_unpaid_maintenance_source(uuid,uuid)') is not null then
    raise exception 'ONEXA_GATE75_PARTIAL_OR_ALREADY_INSTALLED_STOP';
  end if;
  if to_regclass('public.onexa_native_maintenance_cost_scopes') is null
     or to_regclass('public.onexa_native_maintenance_cost_attributions') is null
     or to_regclass('public.onexa_project_cost_centers') is null
     or to_regclass('public.onexa_project_cost_postings') is null
     or to_regclass('public.onexa_business_documents') is null
     or to_regclass('public.onexa_journal_headers') is null
     or to_regclass('public.onexa_operations_work_orders') is null
     or to_regclass('public.onexa_operations_sites') is null
     or to_regclass('public.onexa_company_module_scopes') is null
     or to_regprocedure('public.onexa_has_company_module_access(text,text)') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE75_G42_G71_TO_G74_AND_RBAC_REQUIRED';
  end if;
end
$preflight$;

-- Composite reference prevents a privileged link from pointing at a business
-- document of another tenant/entity. Review index creation and lock timing
-- against a cloned data plane before any approved production DDL.
create unique index if not exists onexa_bizdoc_tenant_entity_id_uq
 on public.onexa_business_documents(tenant_id,legal_entity_id,id);

-- Reserve exactly one active G42 document per reviewed maintenance source.
-- Existing business documents are left unchanged; verify index impact first.
create unique index if not exists onexa_gate75_one_active_document_per_claim_uq
on public.onexa_business_documents(
  tenant_id, (source_snapshot->>'maintenance_source_claim_id'))
where document_type='project_cost'
  and status not in ('cancelled','rejected')
  and source_snapshot->>'maintenance_source_claim_id' is not null;

create table public.onexa_native_maintenance_unpaid_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null references public.onexa_tenants(tenant_id) on delete restrict,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  work_order_id uuid not null,
  project_cost_center_id uuid not null,
  source_kind text not null
    check (source_kind in ('unbilled_subcontract','other_unpaid_direct')),
  -- No material issue / already-posted invoice / payroll source can be
  -- registered as a fresh unpaid cost through this restricted path.
  source_reference text not null
    check (length(btrim(source_reference)) between 5 and 120
      and source_reference=upper(btrim(source_reference))),
  evidence_reference text not null check (length(btrim(evidence_reference)) between 5 and 200),
  amount numeric(20,4) not null check (amount>0),
  status text not null default 'pending_review'
    check (status in ('pending_review','approved','rejected','linked')),
  created_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_reason text,
  linked_document_id uuid,
  linked_by uuid references auth.users(id),
  linked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onexa_native_unpaid_claim_scope_fk
    foreign key(tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)
    references public.onexa_native_maintenance_cost_scopes
     (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)
    on delete restrict,
  constraint onexa_native_unpaid_claim_document_fk
    foreign key(tenant_id,legal_entity_id,linked_document_id)
    references public.onexa_business_documents(tenant_id,legal_entity_id,id)
    on delete restrict,
  constraint onexa_native_unpaid_claim_tenant_source_unique
    unique(tenant_id,legal_entity_id,source_reference),
  constraint onexa_native_unpaid_claim_document_once
    unique(tenant_id,linked_document_id),
  constraint onexa_native_unpaid_claim_review_consistency
    check (
      (status='pending_review' and reviewed_by is null and reviewed_at is null
        and linked_document_id is null and linked_at is null and linked_by is null)
      or
      (status='rejected' and reviewed_by is not null and reviewed_at is not null
        and nullif(btrim(review_reason),'') is not null
        and linked_document_id is null and linked_at is null and linked_by is null)
      or
      (status='approved' and reviewed_by is not null and reviewed_at is not null
        and nullif(btrim(review_reason),'') is not null
        and linked_document_id is null and linked_at is null and linked_by is null)
      or
      (status='linked' and reviewed_by is not null and reviewed_at is not null
        and linked_document_id is not null and linked_at is not null and linked_by is not null)
    )
);

create index onexa_native_unpaid_claim_queue_idx
  on public.onexa_native_maintenance_unpaid_sources
  (tenant_id,legal_entity_id,status,created_at desc);
create index onexa_native_unpaid_claim_order_idx
  on public.onexa_native_maintenance_unpaid_sources(tenant_id,work_order_id,created_at desc);

alter table public.onexa_native_maintenance_unpaid_sources enable row level security;
create policy onexa_native_unpaid_claims_member_read
on public.onexa_native_maintenance_unpaid_sources for select to authenticated
using (
  tenant_id=onexa_private.claim_tenant_id()
  and auth.uid() is not null
  and onexa_private.is_active_member(auth.uid())
  and onexa_private.has_module_action(auth.uid(),'projects','read')
  and exists (
    select 1 from public.onexa_native_maintenance_cost_scopes scope
    where scope.tenant_id=onexa_native_maintenance_unpaid_sources.tenant_id
      and scope.legal_entity_id=onexa_native_maintenance_unpaid_sources.legal_entity_id
      and scope.branch_id=onexa_native_maintenance_unpaid_sources.branch_id
      and scope.work_order_id=onexa_native_maintenance_unpaid_sources.work_order_id
      and scope.project_cost_center_id=onexa_native_maintenance_unpaid_sources.project_cost_center_id
  )
);

-- Both direct client writes and service-role reassignment attempts are
-- rejected. Only controlled SECURITY DEFINER entry points can transition.
create function onexa_private.guard_native_unpaid_source_write()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if tg_op='DELETE' then
    raise exception 'ONEXA_GATE75_SOURCE_APPEND_ONLY';
  end if;
  if coalesce(current_setting('onexa.gate75_authorized_write',true),'')<>'true' then
    raise exception 'ONEXA_GATE75_AUTHORIZED_RPC_REQUIRED';
  end if;
  if tg_op='UPDATE' and
     row(new.tenant_id,new.legal_entity_id,new.branch_id,new.work_order_id,
       new.project_cost_center_id,new.source_kind,new.source_reference,
       new.evidence_reference,new.amount,new.created_by,new.created_at)
     is distinct from
     row(old.tenant_id,old.legal_entity_id,old.branch_id,old.work_order_id,
       old.project_cost_center_id,old.source_kind,old.source_reference,
       old.evidence_reference,old.amount,old.created_by,old.created_at) then
    raise exception 'ONEXA_GATE75_SOURCE_IDENTITY_IMMUTABLE';
  end if;
  if tg_op='UPDATE' then
    if old.status in ('linked','rejected') then
      raise exception 'ONEXA_GATE75_SOURCE_TERMINAL_IMMUTABLE';
    end if;
    if not (old.status='pending_review' and new.status in ('approved','rejected')
       or old.status='approved' and new.status='linked') then
      raise exception 'ONEXA_GATE75_SOURCE_INVALID_TRANSITION';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

create trigger onexa_guard_native_unpaid_source_write
before insert or update or delete on public.onexa_native_maintenance_unpaid_sources
for each row execute function onexa_private.guard_native_unpaid_source_write();

-- Evidence reservation is not expense recognition and does not imply
-- the underlying supplier/labor source has been checked by a third party.
create function public.onexa_register_native_unpaid_maintenance_source(
  _work_order_id uuid,_source_kind text,_source_reference text,
  _amount numeric,_evidence_reference text
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _scope public.onexa_native_maintenance_cost_scopes%rowtype;
  _work public.onexa_operations_work_orders%rowtype;
  _normalized text:=upper(btrim(_source_reference));
  _id uuid;
begin
  if _actor is null or nullif(_tenant,'') is null
    or not onexa_private.is_active_member(_actor)
    or not onexa_private.has_module_action(_actor,'projects','create')
    or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_GATE75_SOURCE_REGISTRATION_NOT_AUTHORIZED';
  end if;
  if _source_kind not in ('unbilled_subcontract','other_unpaid_direct')
    or length(_normalized) not between 5 and 120
    or length(btrim(_evidence_reference)) not between 5 and 200
    or _amount is null or _amount<=0 then
    raise exception 'ONEXA_GATE75_NEW_UNPAID_EVIDENCE_REQUIRED';
  end if;
  select * into _work from public.onexa_operations_work_orders
    where id=_work_order_id and tenant_id=_tenant for update;
  select * into _scope from public.onexa_native_maintenance_cost_scopes
    where work_order_id=_work.id and tenant_id=_tenant for update;
  if _work.id is null or _work.status<>'accepted'
    or _scope.id is null or _scope.legal_entity_id is distinct from _work.legal_entity_id
    or _scope.branch_id is distinct from _work.branch_id
    or not exists (
      select 1 from public.onexa_project_cost_centers center
      join public.onexa_operations_sites site
        on site.tenant_id=center.tenant_id and site.legal_entity_id=center.legal_entity_id
       and site.branch_id=center.branch_id and site.id=_work.site_id
      join public.onexa_company_module_scopes company
        on company.id=site.company_scope_id and company.tenant_id=site.tenant_id
       and company.legal_entity_id=site.legal_entity_id
      join public.onexa_branches branch
        on branch.id=site.branch_id and branch.tenant_id=site.tenant_id
       and branch.legal_entity_id=site.legal_entity_id
      join public.onexa_legal_entities entity
        on entity.id=site.legal_entity_id and entity.tenant_id=site.tenant_id
      where center.id=_scope.project_cost_center_id and center.tenant_id=_tenant
        and center.is_active and site.is_active and company.is_active
        and branch.is_active and entity.is_active
        and company.legacy_company_code='OM' and company.module_key='projects'
    ) then
    raise exception 'ONEXA_GATE75_ACCEPTED_WORK_ORDER_AND_COST_CENTER_REQUIRED';
  end if;
  -- Conservative reference collision check across all active modules, not
  -- just Gate42; retrying a rejected document still requires manual review.
  if exists (
    select 1 from public.onexa_business_documents d
    where d.tenant_id=_tenant and d.legal_entity_id=_work.legal_entity_id
      and upper(btrim(d.external_reference))=_normalized
  ) then
    raise exception 'ONEXA_GATE75_SOURCE_REFERENCE_ALREADY_EXISTS_IN_DOCUMENTS';
  end if;
  perform set_config('onexa.gate75_authorized_write','true',true);
  insert into public.onexa_native_maintenance_unpaid_sources
    (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id,
     source_kind,source_reference,evidence_reference,amount,created_by)
  values (_tenant,_work.legal_entity_id,_work.branch_id,_work.id,
    _scope.project_cost_center_id,_source_kind,_normalized,
    btrim(_evidence_reference),_amount,_actor)
  returning id into _id;
  perform set_config('onexa.gate75_authorized_write','',true);
  return _id;
end;
$$;

-- The approver must be a distinct finance-capable user; no automatic
-- approval/GL posting and no inference that an external invoice is unpaid.
create function public.onexa_review_native_unpaid_maintenance_source(
  _source_id uuid,_approve boolean,_reason text
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _claim public.onexa_native_maintenance_unpaid_sources%rowtype;
  _work public.onexa_operations_work_orders%rowtype;
begin
  if _actor is null or nullif(_tenant,'') is null or _approve is null
    or not onexa_private.is_active_member(_actor)
    or not onexa_private.has_module_action(_actor,'projects','approve')
    or not onexa_private.has_module_action(_actor,'finance','read')
    or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_GATE75_SOURCE_REVIEW_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_reason),'') is null then
    raise exception 'ONEXA_GATE75_SOURCE_REVIEW_REASON_REQUIRED';
  end if;
  select * into _claim from public.onexa_native_maintenance_unpaid_sources
    where id=_source_id and tenant_id=_tenant for update;
  if _claim.id is null or _claim.status<>'pending_review' then
    raise exception 'ONEXA_GATE75_SOURCE_NOT_PENDING_REVIEW';
  end if;
  select * into _work from public.onexa_operations_work_orders
    where id=_claim.work_order_id and tenant_id=_tenant for update;
  if _work.id is null or _work.status<>'accepted'
    or _work.legal_entity_id is distinct from _claim.legal_entity_id
    or _work.branch_id is distinct from _claim.branch_id
    or _actor in (_claim.created_by,_work.created_by,_work.completed_by) then
    raise exception 'ONEXA_GATE75_INDEPENDENT_FINANCE_REVIEW_REQUIRED';
  end if;
  if _approve and exists (
    select 1 from public.onexa_business_documents d
    where d.tenant_id=_tenant and d.legal_entity_id=_claim.legal_entity_id
      and upper(btrim(d.external_reference))=_claim.source_reference
  ) then
    raise exception 'ONEXA_GATE75_SOURCE_REFERENCE_ALREADY_EXISTS_IN_DOCUMENTS';
  end if;
  perform set_config('onexa.gate75_authorized_write','true',true);
  update public.onexa_native_maintenance_unpaid_sources set
    status=case when _approve then 'approved' else 'rejected' end,
    reviewed_by=_actor,reviewed_at=now(),review_reason=btrim(_reason)
  where id=_claim.id and tenant_id=_tenant and status='pending_review';
  if not found then raise exception 'ONEXA_GATE75_CONCURRENT_REVIEW_CONFLICT'; end if;
  perform set_config('onexa.gate75_authorized_write','',true);
  return _claim.id;
end;
$$;

-- Close provenance ONLY after the ordinary G42 + G64 posting workflow and
-- G74 original-journal attribution already succeeded. This RPC never posts.
create function public.onexa_link_native_unpaid_maintenance_source(
  _source_id uuid,_document_id uuid
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _claim public.onexa_native_maintenance_unpaid_sources%rowtype;
  _document public.onexa_business_documents%rowtype;
  _posting public.onexa_project_cost_postings%rowtype;
  _journal public.onexa_journal_headers%rowtype;
  _attribution public.onexa_native_maintenance_cost_attributions%rowtype;
begin
  if _actor is null or nullif(_tenant,'') is null
    or not onexa_private.is_active_member(_actor)
    or not onexa_private.has_module_action(_actor,'projects','approve')
    or not onexa_private.has_module_action(_actor,'finance','read')
    or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_GATE75_SOURCE_LINK_NOT_AUTHORIZED';
  end if;
  select * into _claim from public.onexa_native_maintenance_unpaid_sources
    where id=_source_id and tenant_id=_tenant for update;
  if _claim.id is null or _claim.status not in ('approved','linked')
    or _actor=_claim.created_by then
    raise exception 'ONEXA_GATE75_APPROVED_INDEPENDENT_SOURCE_REQUIRED';
  end if;
  select * into _document from public.onexa_business_documents
    where id=_document_id and tenant_id=_tenant
      and legal_entity_id=_claim.legal_entity_id for update;
  if _document.id is null or _document.document_type<>'project_cost'
    or _document.module_key<>'projects' or _document.origin<>'native'
    or _document.status<>'posted' or _document.posted_journal_id is null
    or _document.branch_id is distinct from _claim.branch_id
    or _document.currency<>'SAR' or _document.gross_total is distinct from _claim.amount
    or upper(btrim(_document.external_reference)) is distinct from _claim.source_reference
    or _document.source_snapshot->>'source_kind' is distinct from 'unpaid_direct_cost'
    or _document.source_snapshot->>'maintenance_source_claim_id'
       is distinct from _claim.id::text
    or _document.source_snapshot->>'project_cost_center_id'
       is distinct from _claim.project_cost_center_id::text then
    raise exception 'ONEXA_GATE75_POSTED_DOCUMENT_PROVENANCE_MISMATCH';
  end if;
  select * into _posting from public.onexa_project_cost_postings
    where tenant_id=_tenant and legal_entity_id=_claim.legal_entity_id
      and document_id=_document.id for update;
  if _posting.document_id is null
     or _posting.project_cost_center_id is distinct from _claim.project_cost_center_id
     or _posting.journal_id is distinct from _document.posted_journal_id
     or _posting.amount is distinct from _claim.amount
     or _posting.source_revision is distinct from _document.revision then
    raise exception 'ONEXA_GATE75_POSTED_PROJECT_COST_MISMATCH';
  end if;
  select * into _journal from public.onexa_journal_headers
    where id=_posting.journal_id and tenant_id=_tenant
      and legal_entity_id=_claim.legal_entity_id for update;
  if _journal.id is null or _journal.state<>'posted'
    or _journal.reversal_journal_id is not null or _journal.reversal_of_id is not null
    or _journal.source_document_type is distinct from 'project_cost'
    or _journal.source_document_id is distinct from _document.id::text
    or _journal.source_revision is distinct from _document.revision
    or _journal.currency is distinct from 'SAR'
    or _journal.total_debit is distinct from _claim.amount
    or _journal.total_credit is distinct from _claim.amount then
    raise exception 'ONEXA_GATE75_SOURCE_JOURNAL_REVERSED_OR_INVALID';
  end if;
  select * into _attribution from public.onexa_native_maintenance_cost_attributions
    where tenant_id=_tenant and legal_entity_id=_claim.legal_entity_id
      and document_id=_document.id for update;
  if _attribution.id is null
    or _attribution.work_order_id is distinct from _claim.work_order_id
    or _attribution.branch_id is distinct from _claim.branch_id
    or _attribution.project_cost_center_id is distinct from _claim.project_cost_center_id
    or _attribution.journal_id is distinct from _journal.id
    or _attribution.amount is distinct from _claim.amount then
    raise exception 'ONEXA_GATE75_GATE74_WORK_ORDER_ATTRIBUTION_REQUIRED';
  end if;
  if _claim.status='linked' then
    if _claim.linked_document_id is distinct from _document.id then
      raise exception 'ONEXA_GATE75_CANNOT_RELINK_SOURCE';
    end if;
    return _claim.id;
  end if;
  perform set_config('onexa.gate75_authorized_write','true',true);
  update public.onexa_native_maintenance_unpaid_sources set
    status='linked',linked_document_id=_document.id,linked_by=_actor,linked_at=now()
  where id=_claim.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_GATE75_CONCURRENT_LINK_CONFLICT'; end if;
  perform set_config('onexa.gate75_authorized_write','',true);
  return _claim.id;
end;
$$;

-- Enforce evidence review BEFORE an ordinary Gate42 project-cost
-- document can claim a new unpaid maintenance source. The G42 approval/post
-- engine remains the sole authority for journal creation.
create function onexa_private.guard_native_claim_business_document()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _claim_id text:=new.source_snapshot->>'maintenance_source_claim_id';
  _old_claim_id text;
  _claim public.onexa_native_maintenance_unpaid_sources%rowtype;
begin
  if tg_op='UPDATE' then
    _old_claim_id:=old.source_snapshot->>'maintenance_source_claim_id';
    if _old_claim_id is not null and _claim_id is distinct from _old_claim_id then
      raise exception 'ONEXA_GATE75_BUSINESS_DOCUMENT_CLAIM_IMMUTABLE';
    end if;
  end if;
  if _claim_id is null then return new; end if;
  select * into _claim from public.onexa_native_maintenance_unpaid_sources
  where id=_claim_id::uuid and tenant_id=new.tenant_id
    and legal_entity_id=new.legal_entity_id;
  if _claim.id is null or _claim.status not in ('approved','linked')
    or (_claim.status='linked' and _claim.linked_document_id is distinct from new.id)
    or new.document_type<>'project_cost' or new.module_key<>'projects'
    or new.origin<>'native' or new.branch_id is distinct from _claim.branch_id
    or new.currency<>'SAR' or new.gross_total is distinct from _claim.amount
    or upper(btrim(new.external_reference)) is distinct from _claim.source_reference
    or new.source_snapshot->>'source_kind' is distinct from 'unpaid_direct_cost'
    or new.source_snapshot->>'project_cost_center_id'
      is distinct from _claim.project_cost_center_id::text then
    raise exception 'ONEXA_GATE75_UNAPPROVED_OR_MISMATCHED_BUSINESS_DOCUMENT';
  end if;
  return new;
end;
$$;

create trigger onexa_guard_native_claim_business_document
before insert or update of source_snapshot,external_reference,gross_total,
  tenant_id,legal_entity_id,branch_id,document_type,module_key,currency,origin
on public.onexa_business_documents
for each row execute function onexa_private.guard_native_claim_business_document();

-- Historical source claims persist after GL reversal; CURRENT reconciliation
-- is recalculated against journal state and Gate74 attribution on each read.
create view public.onexa_native_maintenance_source_reconciliation
with (security_invoker=true) as
select s.id,s.tenant_id,s.legal_entity_id,s.branch_id,
  s.work_order_id,s.project_cost_center_id,s.source_kind,s.source_reference,
  s.amount,s.status,s.reviewed_by,s.linked_document_id,
  case
    when s.status<>'linked' then s.status
    when d.id is null or d.status<>'posted'
      or d.document_type<>'project_cost' or d.module_key<>'projects'
      or d.origin<>'native' or d.currency<>'SAR'
      or upper(btrim(d.external_reference)) is distinct from s.source_reference
      or d.gross_total is distinct from s.amount
      or d.source_snapshot->>'source_kind' is distinct from 'unpaid_direct_cost'
      or d.source_snapshot->>'maintenance_source_claim_id' is distinct from s.id::text
      or d.source_snapshot->>'project_cost_center_id'
          is distinct from s.project_cost_center_id::text
      then 'document_changed_or_missing'
    when p.document_id is null or p.journal_id is distinct from d.posted_journal_id
      or p.project_cost_center_id is distinct from s.project_cost_center_id
      or p.source_revision is distinct from d.revision
      or p.amount is distinct from s.amount then 'posting_mismatch'
    when j.id is null or j.state<>'posted'
      or j.reversal_journal_id is not null or j.reversal_of_id is not null
      then 'original_journal_reversed_or_missing'
    when j.source_document_type is distinct from 'project_cost'
      or j.source_document_id is distinct from d.id::text
      or j.source_revision is distinct from d.revision
      or j.currency is distinct from 'SAR'
      or j.total_debit is distinct from s.amount
      or j.total_credit is distinct from s.amount
      then 'original_journal_source_or_amount_mismatch'
    when a.id is null or a.work_order_id is distinct from s.work_order_id
      or a.branch_id is distinct from s.branch_id
      or a.project_cost_center_id is distinct from s.project_cost_center_id
      or a.journal_id is distinct from j.id
      or a.amount is distinct from s.amount then 'gate74_attribution_mismatch'
    else 'reconciled'
  end as current_reconciliation_status
from public.onexa_native_maintenance_unpaid_sources s
left join public.onexa_business_documents d
  on d.id=s.linked_document_id and d.tenant_id=s.tenant_id
 and d.legal_entity_id=s.legal_entity_id
left join public.onexa_project_cost_postings p
  on p.document_id=d.id and p.tenant_id=s.tenant_id
 and p.legal_entity_id=s.legal_entity_id
left join public.onexa_journal_headers j
  on j.id=p.journal_id and j.tenant_id=s.tenant_id
 and j.legal_entity_id=s.legal_entity_id
left join public.onexa_native_maintenance_cost_attributions a
  on a.document_id=d.id and a.tenant_id=s.tenant_id
 and a.legal_entity_id=s.legal_entity_id;

revoke all on public.onexa_native_maintenance_unpaid_sources from public,anon,authenticated;
grant select on public.onexa_native_maintenance_unpaid_sources to authenticated;
grant all on public.onexa_native_maintenance_unpaid_sources to service_role;
revoke all on public.onexa_native_maintenance_source_reconciliation from public,anon;
grant select on public.onexa_native_maintenance_source_reconciliation to authenticated;
revoke all on function public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text),
  public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text),
  public.onexa_link_native_unpaid_maintenance_source(uuid,uuid) from public,anon;
grant execute on function public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text),
  public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text),
  public.onexa_link_native_unpaid_maintenance_source(uuid,uuid) to authenticated;
revoke all on function onexa_private.guard_native_unpaid_source_write()
  from public,anon,authenticated;
revoke all on function onexa_private.guard_native_claim_business_document()
  from public,anon,authenticated;

commit;
