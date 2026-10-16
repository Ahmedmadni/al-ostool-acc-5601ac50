-- ONEXA Gate 73: tenant-native work order lifecycle.
-- MANUAL MIGRATION AFTER AUTHORIZED G71 + G72 ACCEPTANCE ONLY.
-- No accounting posts, payroll, inventory movements, or legacy ops_* writes.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_operations_work_orders') is not null
     or to_regclass('public.onexa_operations_work_order_events') is not null
     or to_regclass('public.onexa_operations_work_order_seq') is not null
     or to_regprocedure('public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text)') is not null
     or to_regprocedure('public.onexa_transition_operations_work_order(uuid,text,uuid,text)') is not null then
    raise exception 'ONEXA_GATE73_ALREADY_OR_PARTIALLY_INSTALLED_STOP';
  end if;
  if to_regclass('public.onexa_operations_sites') is null
     or to_regclass('public.onexa_operations_assets') is null
     or to_regclass('public.onexa_company_module_scopes') is null
     or to_regclass('public.onexa_branches') is null
     or to_regclass('public.customers') is null
     or to_regclass('public.contracts') is null
     or to_regclass('public.onexa_workspace_memberships') is null
     or to_regprocedure('public.onexa_has_company_module_access(text,text)') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null then
    raise exception 'ONEXA_GATE73_G71_G72_AND_TENANT_CORE_REQUIRED';
  end if;
  if exists (select 1 from (values
    ('customers','tenant_id'),('customers','id'),('customers','is_active'),
    ('contracts','tenant_id'),('contracts','id'),('contracts','customer_id'),
    ('contracts','status'),
    ('onexa_operations_sites','tenant_id'),
    ('onexa_operations_sites','legal_entity_id'),('onexa_operations_sites','branch_id'),
    ('onexa_operations_assets','tenant_id'),
    ('onexa_operations_assets','legal_entity_id'),
    ('onexa_operations_assets','branch_id'),
    ('onexa_operations_assets','site_id')
  ) x(table_name,column_name) where not exists (
    select 1 from information_schema.columns c where c.table_schema='public'
      and c.table_name=x.table_name and c.column_name=x.column_name
  )) then
    raise exception 'ONEXA_GATE73_TENANT_SOURCE_COLUMN_MISMATCH';
  end if;
end
$preflight$;

-- Existing customer/contract reference keys are unique by ID only. Add
-- composite referenced keys so a privileged insert cannot cross tenants.
-- Review lock/index impact and confirm a restorable staging backup beforehand.
create unique index if not exists onexa_customers_tenant_id_id_uq
  on public.customers(tenant_id,id);
create unique index if not exists onexa_contracts_tenant_id_id_customer_uq
  on public.contracts(tenant_id,id,customer_id);
create unique index if not exists onexa_operations_assets_scope_site_id_uq
  on public.onexa_operations_assets(tenant_id,legal_entity_id,branch_id,site_id,id);

create sequence public.onexa_operations_work_order_seq;

create table public.onexa_operations_work_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null references public.onexa_tenants(tenant_id) on delete restrict,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  site_id uuid not null,
  asset_id uuid,
  customer_id uuid not null,
  contract_id uuid,
  work_order_no text not null,
  title text not null check (nullif(btrim(title),'') is not null),
  description text,
  priority text not null default 'normal'
    check (priority in ('low','normal','high','critical')),
  status text not null default 'draft'
    check (status in ('draft','approved','assigned','in_progress','on_hold',
      'completed','accepted','cancelled')),
  assigned_to uuid references auth.users(id),
  created_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  completed_by uuid references auth.users(id),
  accepted_by uuid references auth.users(id),
  approved_at timestamptz,
  completed_at timestamptz,
  accepted_at timestamptz,
  completion_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onexa_wo_tenant_entity_branch_site_fk
    foreign key (tenant_id,legal_entity_id,branch_id,site_id)
    references public.onexa_operations_sites(tenant_id,legal_entity_id,branch_id,id)
    on delete restrict,
  constraint onexa_wo_tenant_entity_branch_site_asset_fk
    foreign key (tenant_id,legal_entity_id,branch_id,site_id,asset_id)
    references public.onexa_operations_assets(tenant_id,legal_entity_id,branch_id,site_id,id)
    on delete restrict,
  constraint onexa_wo_tenant_customer_fk
    foreign key (tenant_id,customer_id)
    references public.customers(tenant_id,id) on delete restrict,
  constraint onexa_wo_tenant_contract_customer_fk
    foreign key (tenant_id,contract_id,customer_id)
    references public.contracts(tenant_id,id,customer_id) on delete restrict,
  constraint onexa_wo_tenant_number_uq unique (tenant_id,work_order_no),
  constraint onexa_wo_completion_audit
    check (status not in ('completed','accepted') or
      (completed_at is not null and completed_by is not null
        and nullif(btrim(completion_note),'') is not null)),
  constraint onexa_wo_acceptance_audit
    check (status<>'accepted' or (accepted_by is not null and accepted_at is not null)),
  constraint onexa_wo_assignment_required
    check (status not in ('assigned','in_progress','on_hold','completed','accepted')
      or assigned_to is not null)
);

create index onexa_wo_tenant_branch_status_idx
  on public.onexa_operations_work_orders
  (tenant_id,legal_entity_id,branch_id,status,created_at desc);
create index onexa_wo_tenant_customer_idx
  on public.onexa_operations_work_orders(tenant_id,customer_id,created_at desc);
create index onexa_wo_tenant_assignee_idx
  on public.onexa_operations_work_orders(tenant_id,assigned_to,status);

create table public.onexa_operations_work_order_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  work_order_id uuid not null,
  from_status text,
  to_status text not null,
  reason text not null check (nullif(btrim(reason),'') is not null),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  constraint onexa_wo_event_tenant_order_fk
    foreign key (tenant_id,work_order_id)
    references public.onexa_operations_work_orders(tenant_id,id) on delete restrict
);

create unique index onexa_work_order_tenant_id_uq
  on public.onexa_operations_work_orders(tenant_id,id);
create index onexa_wo_events_tenant_order_at_idx
  on public.onexa_operations_work_order_events(tenant_id,work_order_id,changed_at desc);

alter table public.onexa_operations_work_orders enable row level security;
alter table public.onexa_operations_work_order_events enable row level security;

create policy onexa_operations_work_orders_read
  on public.onexa_operations_work_orders for select to authenticated
  using (tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null
    and onexa_private.is_active_member(auth.uid())
    and onexa_private.has_module_action(auth.uid(),'projects','read')
    and exists (select 1 from public.onexa_operations_sites site
      join public.onexa_company_module_scopes scope
        on scope.id=site.company_scope_id and scope.tenant_id=site.tenant_id
       and scope.legal_entity_id=site.legal_entity_id
      join public.onexa_branches branch
        on branch.id=site.branch_id and branch.tenant_id=site.tenant_id
       and branch.legal_entity_id=site.legal_entity_id
      join public.onexa_legal_entities entity
        on entity.id=site.legal_entity_id and entity.tenant_id=site.tenant_id
      where site.id=site_id
        and site.tenant_id=onexa_operations_work_orders.tenant_id
        and site.legal_entity_id=onexa_operations_work_orders.legal_entity_id
        and site.branch_id=onexa_operations_work_orders.branch_id
        and scope.legacy_company_code='OM' and scope.module_key='projects'
        and scope.is_active and site.is_active and branch.is_active and entity.is_active));

create policy onexa_operations_work_order_events_read
  on public.onexa_operations_work_order_events for select to authenticated
  using (tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null
    and onexa_private.is_active_member(auth.uid())
    and exists (select 1 from public.onexa_operations_work_orders w
      where w.id=work_order_id and w.tenant_id=onexa_operations_work_order_events.tenant_id));

-- Protect business identity and state under direct service-role changes.
-- The transition RPC sets a local transaction switch only after verifying
-- actor permissions, state transition, separation of duties and parent links.
create function onexa_private.guard_native_work_order_state()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if tg_op='UPDATE' then
    if row(new.tenant_id,new.legal_entity_id,new.branch_id,new.site_id,
           new.asset_id,new.customer_id,new.contract_id,new.work_order_no,
           new.created_by,new.created_at)
      is distinct from
      row(old.tenant_id,old.legal_entity_id,old.branch_id,old.site_id,
          old.asset_id,old.customer_id,old.contract_id,old.work_order_no,
          old.created_by,old.created_at) then
      raise exception 'ONEXA_WORK_ORDER_IDENTITY_IMMUTABLE';
    end if;
    if new.status is distinct from old.status
       and coalesce(current_setting('onexa.wo_transition_authorized',true),'')<>'true' then
      raise exception 'ONEXA_WORK_ORDER_TRANSITION_RPC_REQUIRED';
    end if;
    if old.status in ('accepted','cancelled')
       and new is distinct from old then
      raise exception 'ONEXA_WORK_ORDER_TERMINAL_IMMUTABLE';
    end if;
  end if;
  return new;
end;
$$;

create trigger onexa_guard_native_work_order_state
  before update on public.onexa_operations_work_orders
  for each row execute function onexa_private.guard_native_work_order_state();

create function onexa_private.guard_native_work_order_events()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if tg_op<>'INSERT' then
    raise exception 'ONEXA_WORK_ORDER_AUDIT_APPEND_ONLY';
  end if;
  if coalesce(current_setting('onexa.wo_event_authorized',true),'')<>'true' then
    raise exception 'ONEXA_WORK_ORDER_EVENT_RPC_REQUIRED';
  end if;
  return new;
end;
$$;

create trigger onexa_guard_native_work_order_events
  before insert or update or delete on public.onexa_operations_work_order_events
  for each row execute function onexa_private.guard_native_work_order_events();

create function public.onexa_create_operations_work_order(
  _site_id uuid,_asset_id uuid,_customer_id uuid,_contract_id uuid,
  _title text,_description text default null
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _site public.onexa_operations_sites%rowtype;
  _work_id uuid;
  _number text;
begin
  if _actor is null or nullif(_tenant,'') is null
     or not onexa_private.is_active_member(_actor)
     or not onexa_private.has_module_action(_actor,'projects','create')
     or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_WORK_ORDER_CREATE_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_title),'') is null then
    raise exception 'ONEXA_WORK_ORDER_TITLE_REQUIRED';
  end if;
  select * into _site from public.onexa_operations_sites
    where id=_site_id and tenant_id=_tenant and is_active for update;
  if _site.id is null or not exists (
    select 1 from public.onexa_company_module_scopes scope
    join public.onexa_legal_entities entity
      on entity.id=scope.legal_entity_id and entity.tenant_id=scope.tenant_id
    join public.onexa_branches branch
      on branch.id=_site.branch_id and branch.tenant_id=scope.tenant_id
     and branch.legal_entity_id=scope.legal_entity_id
    where scope.id=_site.company_scope_id
      and scope.tenant_id=_tenant and scope.legal_entity_id=_site.legal_entity_id
      and scope.legacy_company_code='OM' and scope.module_key='projects'
      and scope.is_active and entity.is_active and branch.is_active
  ) then
    raise exception 'ONEXA_WORK_ORDER_SITE_NOT_ACCESSIBLE';
  end if;
  if _asset_id is not null and not exists (
    select 1 from public.onexa_operations_assets asset
    where asset.id=_asset_id and asset.tenant_id=_tenant
      and asset.legal_entity_id=_site.legal_entity_id
      and asset.branch_id=_site.branch_id and asset.site_id=_site.id
      and asset.is_active
  ) then
    raise exception 'ONEXA_WORK_ORDER_ASSET_SCOPE_INVALID';
  end if;
  if not exists (
    select 1 from public.customers customer
    where customer.id=_customer_id and customer.tenant_id=_tenant
      and customer.is_active is true
  ) then
    raise exception 'ONEXA_WORK_ORDER_CUSTOMER_NOT_ACCESSIBLE';
  end if;
  if _contract_id is not null and not exists (
    select 1 from public.contracts contract
    where contract.id=_contract_id and contract.tenant_id=_tenant
      and contract.customer_id=_customer_id and contract.status::text='active'
      and (contract.start_date is null or contract.start_date<=current_date)
      and (contract.end_date is null or contract.end_date>=current_date)
  ) then
    raise exception 'ONEXA_WORK_ORDER_CONTRACT_SCOPE_INVALID';
  end if;
  _number:='WO-'||to_char(current_date,'YYYY')||'-'
    ||lpad(nextval('public.onexa_operations_work_order_seq')::text,9,'0');
  insert into public.onexa_operations_work_orders (
    tenant_id,legal_entity_id,branch_id,site_id,asset_id,customer_id,
    contract_id,work_order_no,title,description,created_by
  ) values (_tenant,_site.legal_entity_id,_site.branch_id,_site.id,
    _asset_id,_customer_id,_contract_id,_number,btrim(_title),
    nullif(btrim(_description),''),_actor)
  returning id into _work_id;
  perform set_config('onexa.wo_event_authorized','true',true);
  insert into public.onexa_operations_work_order_events(
    tenant_id,work_order_id,from_status,to_status,reason,changed_by
  ) values (_tenant,_work_id,null,'draft','Created',_actor);
  perform set_config('onexa.wo_event_authorized','',true);
  return _work_id;
end;
$$;

-- Authorized transitions; state updates and event insertion are atomic.
-- Non-approval actions by the assignee still require active workspace
-- membership and projects.read. Approval and acceptance need projects.approve.
create function public.onexa_transition_operations_work_order(
  _work_order_id uuid,_target_status text,
  _assignee uuid default null,_reason text default null
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _work public.onexa_operations_work_orders%rowtype;
  _manager boolean;
  _assignee_member boolean;
begin
  if _actor is null or nullif(_tenant,'') is null
     or not onexa_private.is_active_member(_actor)
     or not onexa_private.has_module_action(_actor,'projects','read')
     or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_WORK_ORDER_TRANSITION_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_reason),'') is null then
    raise exception 'ONEXA_WORK_ORDER_TRANSITION_REASON_REQUIRED';
  end if;
  select * into _work from public.onexa_operations_work_orders
    where id=_work_order_id and tenant_id=_tenant for update;
  if _work.id is null or not exists (
    select 1 from public.onexa_operations_sites site
    join public.onexa_company_module_scopes scope
      on scope.id=site.company_scope_id and scope.tenant_id=site.tenant_id
     and scope.legal_entity_id=site.legal_entity_id
    join public.onexa_branches branch
      on branch.id=site.branch_id and branch.tenant_id=site.tenant_id
     and branch.legal_entity_id=site.legal_entity_id
    join public.onexa_legal_entities entity
      on entity.id=site.legal_entity_id and entity.tenant_id=site.tenant_id
    where site.id=_work.site_id and site.tenant_id=_tenant
      and site.legal_entity_id=_work.legal_entity_id
      and site.branch_id=_work.branch_id
      and site.is_active and scope.is_active
      and scope.legacy_company_code='OM' and scope.module_key='projects'
      and branch.is_active and entity.is_active
  ) then
    raise exception 'ONEXA_WORK_ORDER_SITE_NOT_ACCESSIBLE';
  end if;
  _manager:=onexa_private.has_module_action(_actor,'projects','approve');
  if _work.status in ('accepted','cancelled') then
    raise exception 'ONEXA_WORK_ORDER_TERMINAL_IMMUTABLE';
  end if;
  if _target_status is null or _target_status=_work.status then
    raise exception 'ONEXA_WORK_ORDER_NEW_STATUS_REQUIRED';
  end if;
  if not (
    (_work.status='draft' and _target_status='approved')
    or (_work.status='draft' and _target_status='cancelled')
    or (_work.status='approved' and _target_status='assigned')
    or (_work.status='approved' and _target_status='cancelled')
    or (_work.status='assigned' and _target_status='in_progress')
    or (_work.status='assigned' and _target_status='cancelled')
    or (_work.status='in_progress' and _target_status='on_hold')
    or (_work.status='on_hold' and _target_status='in_progress')
    or (_work.status='in_progress' and _target_status='completed')
    or (_work.status='completed' and _target_status='accepted')
  ) then
    raise exception 'ONEXA_WORK_ORDER_INVALID_TRANSITION';
  end if;

  if _target_status in ('approved','assigned','accepted','cancelled') then
    if not _manager then
      raise exception 'ONEXA_WORK_ORDER_MANAGER_APPROVAL_REQUIRED';
    end if;
  else
    if not (_actor=_work.assigned_to or _manager) then
      raise exception 'ONEXA_WORK_ORDER_ASSIGNEE_OR_MANAGER_REQUIRED';
    end if;
  end if;

  if _target_status='approved' and _actor=_work.created_by then
    raise exception 'ONEXA_WORK_ORDER_CREATOR_CANNOT_APPROVE';
  end if;
  if _target_status='accepted' and
    _actor in (_work.created_by,_work.completed_by) then
    raise exception 'ONEXA_WORK_ORDER_ACCEPTANCE_SEPARATION_REQUIRED';
  end if;
  if _target_status='assigned' then
    if _assignee is null or not exists (
      select 1 from public.onexa_workspace_memberships m
      where m.user_id=_assignee and m.tenant_id=_tenant and m.status='active'
    ) then
      raise exception 'ONEXA_WORK_ORDER_ACTIVE_ASSIGNEE_REQUIRED';
    end if;
  elsif _assignee is not null then
    raise exception 'ONEXA_WORK_ORDER_ASSIGNEE_CHANGE_REQUIRES_ASSIGNMENT';
  end if;

  perform set_config('onexa.wo_transition_authorized','true',true);
  update public.onexa_operations_work_orders
    set status=_target_status,
        assigned_to=case when _target_status='assigned' then _assignee else assigned_to end,
        approved_by=case when _target_status='approved' then _actor else approved_by end,
        approved_at=case when _target_status='approved' then now() else approved_at end,
        completed_by=case when _target_status='completed' then _actor else completed_by end,
        completed_at=case when _target_status='completed' then now() else completed_at end,
        completion_note=case when _target_status='completed' then btrim(_reason) else completion_note end,
        accepted_by=case when _target_status='accepted' then _actor else accepted_by end,
        accepted_at=case when _target_status='accepted' then now() else accepted_at end,
        updated_at=now()
    where id=_work.id and tenant_id=_tenant;
  perform set_config('onexa.wo_transition_authorized','',true);
  perform set_config('onexa.wo_event_authorized','true',true);
  insert into public.onexa_operations_work_order_events(
    tenant_id,work_order_id,from_status,to_status,reason,changed_by
  ) values (_tenant,_work.id,_work.status,_target_status,btrim(_reason),_actor);
  perform set_config('onexa.wo_event_authorized','',true);
  return _work.id;
end;
$$;

revoke all on public.onexa_operations_work_orders,
  public.onexa_operations_work_order_events from public,anon,authenticated;
grant select on public.onexa_operations_work_orders,
  public.onexa_operations_work_order_events to authenticated;
grant all on public.onexa_operations_work_orders,
  public.onexa_operations_work_order_events to service_role;

revoke all on function public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text),
  public.onexa_transition_operations_work_order(uuid,text,uuid,text) from public,anon;
grant execute on function public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text),
  public.onexa_transition_operations_work_order(uuid,text,uuid,text) to authenticated;

revoke all on function onexa_private.guard_native_work_order_state(),
  onexa_private.guard_native_work_order_events() from public,anon,authenticated;
revoke all on sequence public.onexa_operations_work_order_seq from public,anon,authenticated;
grant usage,select on sequence public.onexa_operations_work_order_seq to service_role;

commit;
