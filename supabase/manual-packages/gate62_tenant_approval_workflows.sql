-- Gate 62: tenant-configurable approval workflow foundation.
-- Apply after Gate 27 (workspace foundation) and the business-document foundation.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_workspace') is null
     or to_regclass('public.onexa_workspace_memberships') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null then
    raise exception 'ONEXA_GATE62_WORKSPACE_FOUNDATION_REQUIRED';
  end if;
end;
$preflight$;

create table if not exists public.onexa_approval_workflows (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null default onexa_private.claim_tenant_id(),
  process_key text not null check (process_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  name_ar text not null check (length(btrim(name_ar)) between 2 and 120),
  description text,
  manager_user_id uuid,
  is_active boolean not null default true,
  allow_creator_approval boolean not null default false,
  allow_same_actor_all_steps boolean not null default false,
  version integer not null default 1 check (version > 0),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_by uuid not null,
  updated_at timestamptz not null default now(),
  unique (tenant_id, process_key)
);

create table if not exists public.onexa_approval_workflow_steps (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null default onexa_private.claim_tenant_id(),
  workflow_id uuid not null references public.onexa_approval_workflows(id) on delete cascade,
  step_order integer not null check (step_order between 1 and 99),
  name_ar text not null check (length(btrim(name_ar)) between 2 and 120),
  action_key text not null check (action_key in ('prepare','review','approve','post')),
  assignee_kind text not null check (assignee_kind in ('user','role','department','manager')),
  assignee_user_id uuid,
  assignee_role_key text,
  assignee_department_id uuid,
  minimum_approvals integer not null default 1 check (minimum_approvals between 1 and 20),
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workflow_id, step_order),
  check (
    (assignee_kind = 'user' and assignee_user_id is not null and assignee_role_key is null and assignee_department_id is null)
    or (assignee_kind = 'role' and assignee_user_id is null and assignee_role_key is not null and assignee_department_id is null)
    or (assignee_kind = 'department' and assignee_user_id is null and assignee_role_key is null and assignee_department_id is not null)
    or (assignee_kind = 'manager' and assignee_user_id is null and assignee_role_key is null and assignee_department_id is null)
  )
);

create table if not exists public.onexa_approval_workflow_audit (
  id bigint generated always as identity primary key,
  tenant_id text not null,
  workflow_id uuid not null,
  actor_user_id uuid not null,
  event_type text not null,
  before_snapshot jsonb,
  after_snapshot jsonb,
  created_at timestamptz not null default now()
);

create index if not exists onexa_approval_workflows_tenant_active_idx
  on public.onexa_approval_workflows (tenant_id, is_active, process_key);
create index if not exists onexa_approval_steps_workflow_idx
  on public.onexa_approval_workflow_steps (tenant_id, workflow_id, step_order);

alter table public.onexa_approval_workflows enable row level security;
alter table public.onexa_approval_workflow_steps enable row level security;
alter table public.onexa_approval_workflow_audit enable row level security;

drop policy if exists onexa_approval_workflows_read on public.onexa_approval_workflows;
create policy onexa_approval_workflows_read on public.onexa_approval_workflows
for select to authenticated
using (tenant_id = onexa_private.claim_tenant_id());

drop policy if exists onexa_approval_steps_read on public.onexa_approval_workflow_steps;
create policy onexa_approval_steps_read on public.onexa_approval_workflow_steps
for select to authenticated
using (tenant_id = onexa_private.claim_tenant_id());

drop policy if exists onexa_approval_audit_read on public.onexa_approval_workflow_audit;
create policy onexa_approval_audit_read on public.onexa_approval_workflow_audit
for select to authenticated
using (tenant_id = onexa_private.claim_tenant_id());

create or replace function onexa_private.can_manage_approval_workflow(_workflow_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.onexa_workspace_memberships m
    where m.tenant_id = onexa_private.claim_tenant_id()
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role_key = 'workspace_owner'
  ) or exists (
    select 1
    from public.onexa_approval_workflows w
    where w.id = _workflow_id
      and w.tenant_id = onexa_private.claim_tenant_id()
      and w.manager_user_id = auth.uid()
  );
$$;

create or replace function public.onexa_save_approval_workflow(_workflow jsonb)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _actor uuid := auth.uid();
  _tenant text := onexa_private.claim_tenant_id();
  _id uuid := nullif(_workflow->>'id','')::uuid;
  _before jsonb;
  _step jsonb;
  _step_order integer := 0;
begin
  if _actor is null or nullif(_tenant,'') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if jsonb_typeof(_workflow->'steps') is distinct from 'array'
     or jsonb_array_length(_workflow->'steps') = 0 then
    raise exception 'ONEXA_APPROVAL_WORKFLOW_STEPS_REQUIRED';
  end if;

  if _id is null then
    if not exists (
      select 1 from public.onexa_workspace_memberships m
      where m.tenant_id = _tenant and m.user_id = _actor
        and m.status = 'active' and m.role_key = 'workspace_owner'
    ) then raise exception 'ONEXA_WORKSPACE_OWNER_REQUIRED'; end if;

    insert into public.onexa_approval_workflows (
      tenant_id, process_key, name_ar, description, manager_user_id,
      is_active, allow_creator_approval, allow_same_actor_all_steps,
      created_by, updated_by
    ) values (
      _tenant, btrim(_workflow->>'process_key'), btrim(_workflow->>'name_ar'),
      nullif(btrim(_workflow->>'description'),''), nullif(_workflow->>'manager_user_id','')::uuid,
      coalesce((_workflow->>'is_active')::boolean,true),
      coalesce((_workflow->>'allow_creator_approval')::boolean,false),
      coalesce((_workflow->>'allow_same_actor_all_steps')::boolean,false),
      _actor, _actor
    ) returning id into _id;
  else
    if not onexa_private.can_manage_approval_workflow(_id) then
      raise exception 'ONEXA_APPROVAL_WORKFLOW_MANAGER_REQUIRED';
    end if;
    select to_jsonb(w) into _before from public.onexa_approval_workflows w
      where w.id = _id and w.tenant_id = _tenant for update;
    if _before is null then raise exception 'ONEXA_APPROVAL_WORKFLOW_NOT_FOUND'; end if;
    update public.onexa_approval_workflows set
      name_ar = btrim(_workflow->>'name_ar'),
      description = nullif(btrim(_workflow->>'description'),''),
      manager_user_id = nullif(_workflow->>'manager_user_id','')::uuid,
      is_active = coalesce((_workflow->>'is_active')::boolean,true),
      allow_creator_approval = coalesce((_workflow->>'allow_creator_approval')::boolean,false),
      allow_same_actor_all_steps = coalesce((_workflow->>'allow_same_actor_all_steps')::boolean,false),
      version = version + 1, updated_by = _actor, updated_at = now()
    where id = _id and tenant_id = _tenant;
    delete from public.onexa_approval_workflow_steps where workflow_id = _id and tenant_id = _tenant;
  end if;

  for _step in select value from jsonb_array_elements(_workflow->'steps') loop
    _step_order := _step_order + 1;
    insert into public.onexa_approval_workflow_steps (
      tenant_id, workflow_id, step_order, name_ar, action_key, assignee_kind,
      assignee_user_id, assignee_role_key, assignee_department_id,
      minimum_approvals, is_required
    ) values (
      _tenant, _id, _step_order, btrim(_step->>'name_ar'), _step->>'action_key',
      _step->>'assignee_kind', nullif(_step->>'assignee_user_id','')::uuid,
      nullif(btrim(_step->>'assignee_role_key'),''),
      nullif(_step->>'assignee_department_id','')::uuid,
      coalesce((_step->>'minimum_approvals')::integer,1),
      coalesce((_step->>'is_required')::boolean,true)
    );
  end loop;

  insert into public.onexa_approval_workflow_audit (
    tenant_id, workflow_id, actor_user_id, event_type, before_snapshot, after_snapshot
  ) values (
    _tenant, _id, _actor, case when _before is null then 'created' else 'updated' end,
    _before, (select to_jsonb(w) from public.onexa_approval_workflows w where w.id = _id)
  );
  return _id;
end;
$function$;

-- Runtime decision used by posting/approval functions. Existing strict behavior
-- remains the fallback until a tenant explicitly activates a process workflow.
create or replace function public.onexa_approval_separation_required(
  _process_key text,
  _action_key text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when not exists (
      select 1 from public.onexa_approval_workflows w
      where w.tenant_id = onexa_private.claim_tenant_id()
        and w.process_key = _process_key and w.is_active
    ) then true
    when _action_key = 'approve' then not coalesce((
      select w.allow_creator_approval from public.onexa_approval_workflows w
      where w.tenant_id = onexa_private.claim_tenant_id()
        and w.process_key = _process_key and w.is_active limit 1
    ),false)
    else not coalesce((
      select w.allow_same_actor_all_steps from public.onexa_approval_workflows w
      where w.tenant_id = onexa_private.claim_tenant_id()
        and w.process_key = _process_key and w.is_active limit 1
    ),false)
  end;
$$;

revoke all on public.onexa_approval_workflows, public.onexa_approval_workflow_steps,
  public.onexa_approval_workflow_audit from anon, authenticated;
grant select on public.onexa_approval_workflows, public.onexa_approval_workflow_steps,
  public.onexa_approval_workflow_audit to authenticated;
revoke all on function public.onexa_save_approval_workflow(jsonb) from public, anon;
grant execute on function public.onexa_save_approval_workflow(jsonb) to authenticated;
revoke all on function public.onexa_approval_separation_required(text,text) from public, anon;
grant execute on function public.onexa_approval_separation_required(text,text) to authenticated;
revoke all on function onexa_private.can_manage_approval_workflow(uuid) from public, anon, authenticated;

commit;
