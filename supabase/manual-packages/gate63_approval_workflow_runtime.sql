-- Gate 63: execute tenant approval maps for business documents.
-- Gate 62 must be applied first. Legacy strict segregation remains the fallback.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_approval_workflows') is null
     or to_regclass('public.onexa_approval_workflow_steps') is null
     or to_regclass('public.onexa_business_documents') is null
     or to_regprocedure('public.onexa_approval_separation_required(text,text)') is null then
    raise exception 'ONEXA_GATE63_APPROVAL_FOUNDATION_REQUIRED';
  end if;
end;
$preflight$;

create table if not exists public.onexa_approval_instances (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  document_id uuid not null references public.onexa_business_documents(id) on delete cascade,
  workflow_id uuid not null references public.onexa_approval_workflows(id) on delete restrict,
  workflow_version integer not null check (workflow_version > 0),
  current_step_id uuid references public.onexa_approval_workflow_steps(id) on delete restrict,
  current_step_order integer,
  status text not null default 'active' check (status in (
    'active','awaiting_post','completed','rejected','cancelled'
  )),
  started_by uuid not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (tenant_id, document_id)
);

create table if not exists public.onexa_approval_decisions (
  id bigint generated always as identity primary key,
  tenant_id text not null,
  instance_id uuid not null references public.onexa_approval_instances(id) on delete cascade,
  document_id uuid not null references public.onexa_business_documents(id) on delete cascade,
  step_id uuid not null references public.onexa_approval_workflow_steps(id) on delete restrict,
  step_order integer not null,
  actor_user_id uuid not null,
  decision text not null check (decision in ('approved','rejected','posted')),
  reason text,
  created_at timestamptz not null default now(),
  unique (instance_id, step_id, actor_user_id, decision)
);

create index if not exists onexa_approval_instances_active_idx
  on public.onexa_approval_instances (tenant_id, status, current_step_order, updated_at);
create index if not exists onexa_approval_decisions_step_idx
  on public.onexa_approval_decisions (tenant_id, instance_id, step_id, decision);

alter table public.onexa_approval_instances enable row level security;
alter table public.onexa_approval_decisions enable row level security;

drop policy if exists onexa_approval_instances_read on public.onexa_approval_instances;
create policy onexa_approval_instances_read on public.onexa_approval_instances
for select to authenticated using (tenant_id = onexa_private.claim_tenant_id());
drop policy if exists onexa_approval_decisions_read on public.onexa_approval_decisions;
create policy onexa_approval_decisions_read on public.onexa_approval_decisions
for select to authenticated using (tenant_id = onexa_private.claim_tenant_id());

create or replace function onexa_private.approval_actor_matches_step(
  _step_id uuid,
  _document_id uuid,
  _actor uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select exists (
    select 1
    from public.onexa_approval_workflow_steps step
    join public.onexa_business_documents document
      on document.id = _document_id and document.tenant_id = step.tenant_id
    where step.id = _step_id
      and step.tenant_id = onexa_private.claim_tenant_id()
      and (
        (step.assignee_kind = 'user' and step.assignee_user_id = _actor)
        or (step.assignee_kind = 'role' and exists (
          select 1 from public.onexa_workspace_memberships membership
          where membership.tenant_id = step.tenant_id
            and membership.user_id = _actor
            and membership.status = 'active'
            and membership.role_key = step.assignee_role_key
        ))
        or (step.assignee_kind = 'department' and exists (
          select 1 from public.profiles profile
          where profile.id = _actor and profile.tenant_id = step.tenant_id
            and profile.status = 'active'
            and profile.department_id = step.assignee_department_id
        ))
        or (step.assignee_kind = 'manager' and exists (
          select 1 from public.profiles creator
          where creator.id = document.created_by and creator.tenant_id = step.tenant_id
            and creator.manager_id = _actor
        ))
      )
  );
$function$;

create or replace function public.onexa_can_act_on_approval_step(_document_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select coalesce((
    select onexa_private.approval_actor_matches_step(
      instance.current_step_id, instance.document_id, auth.uid()
    )
    from public.onexa_approval_instances instance
    where instance.document_id = _document_id
      and instance.tenant_id = onexa_private.claim_tenant_id()
      and instance.status in ('active','awaiting_post')
  ), false);
$function$;

create or replace function onexa_private.set_business_document_status(
  _document_id uuid,
  _status text,
  _actor uuid,
  _reason text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform set_config('onexa.transition_authorized','true',true);
  perform set_config('onexa.transition_reason',coalesce(_reason,''),true);
  update public.onexa_business_documents set
    status = _status,
    submitted_by = case when _status = 'submitted' then _actor else submitted_by end,
    submitted_at = case when _status = 'submitted' then now() else submitted_at end,
    approved_by = case when _status = 'approved' then _actor else approved_by end,
    approved_at = case when _status = 'approved' then now() else approved_at end,
    rejected_by = case when _status = 'rejected' then _actor else rejected_by end,
    rejected_at = case when _status = 'rejected' then now() else rejected_at end,
    cancelled_by = case when _status = 'cancelled' then _actor else cancelled_by end,
    cancelled_at = case when _status = 'cancelled' then now() else cancelled_at end
  where id = _document_id and tenant_id = onexa_private.claim_tenant_id();
  if not found then raise exception 'ONEXA_DOCUMENT_STATUS_UPDATE_FAILED'; end if;
end;
$function$;

create or replace function public.onexa_transition_business_document(
  _document_id uuid,
  _to_status text,
  _reason text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
  _workflow public.onexa_approval_workflows%rowtype;
  _instance public.onexa_approval_instances%rowtype;
  _step public.onexa_approval_workflow_steps%rowtype;
  _next_step public.onexa_approval_workflow_steps%rowtype;
  _decision_count integer;
begin
  if _actor is null or nullif(_tenant,'') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if _to_status not in ('draft','submitted','approved','rejected','cancelled') then
    raise exception 'ONEXA_INVALID_MANUAL_TRANSITION';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':approval:' || _document_id::text,0));
  select * into _document from public.onexa_business_documents
    where id = _document_id and tenant_id = _tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;

  if _to_status = 'submitted' then
    if _document.status not in ('draft','rejected') then raise exception 'ONEXA_INVALID_STATUS_TRANSITION'; end if;
    if _document.created_by <> _actor then raise exception 'ONEXA_ONLY_DOCUMENT_CREATOR_CAN_SUBMIT'; end if;
    select * into _workflow from public.onexa_approval_workflows workflow
      where workflow.tenant_id = _tenant and workflow.process_key = _document.document_type
        and workflow.is_active order by workflow.version desc limit 1;
    perform onexa_private.set_business_document_status(_document_id,'submitted',_actor,_reason);
    if _workflow.id is not null then
      select * into _step from public.onexa_approval_workflow_steps step
        where step.workflow_id = _workflow.id and step.tenant_id = _tenant
          and step.is_required and step.action_key <> 'prepare'
        order by step.step_order limit 1;
      if not found then raise exception 'ONEXA_APPROVAL_ACTION_STEP_REQUIRED'; end if;
      insert into public.onexa_approval_instances (
        tenant_id,document_id,workflow_id,workflow_version,current_step_id,
        current_step_order,status,started_by
      ) values (
        _tenant,_document_id,_workflow.id,_workflow.version,_step.id,
        _step.step_order,case when _step.action_key='post' then 'awaiting_post' else 'active' end,_actor
      ) on conflict (tenant_id,document_id) do update set
        workflow_id=excluded.workflow_id,workflow_version=excluded.workflow_version,
        current_step_id=excluded.current_step_id,current_step_order=excluded.current_step_order,
        status=excluded.status,started_by=excluded.started_by,started_at=now(),
        completed_at=null,updated_at=now()
      returning id into _instance.id;
      delete from public.onexa_approval_decisions
        where instance_id=_instance.id and tenant_id=_tenant;
      if _step.action_key = 'post' then
        perform onexa_private.set_business_document_status(_document_id,'approved',_actor,'workflow_ready_for_post');
      end if;
    end if;
    return (select status from public.onexa_business_documents where id=_document_id);
  end if;

  select * into _instance from public.onexa_approval_instances instance
    where instance.document_id = _document_id and instance.tenant_id = _tenant
      and instance.status in ('active','awaiting_post') for update;

  if _to_status in ('approved','rejected') and found then
    select * into _step from public.onexa_approval_workflow_steps
      where id = _instance.current_step_id and tenant_id = _tenant;
    if _step.id is null or _step.action_key = 'post' then
      raise exception 'ONEXA_APPROVAL_STEP_ACTION_INVALID';
    end if;
    if not onexa_private.approval_actor_matches_step(_step.id,_document_id,_actor) then
      raise exception 'ONEXA_APPROVAL_STEP_NOT_ASSIGNED_TO_ACTOR';
    end if;
    if _actor = _document.created_by
       and public.onexa_approval_separation_required(_document.document_type,'approve') then
      raise exception 'ONEXA_SEGREGATION_OF_DUTIES_REQUIRED';
    end if;
    if _to_status = 'rejected' and nullif(btrim(_reason),'') is null then
      raise exception 'ONEXA_TRANSITION_REASON_REQUIRED';
    end if;
    insert into public.onexa_approval_decisions (
      tenant_id,instance_id,document_id,step_id,step_order,actor_user_id,decision,reason
    ) values (
      _tenant,_instance.id,_document_id,_step.id,_step.step_order,_actor,
      case when _to_status='approved' then 'approved' else 'rejected' end,nullif(btrim(_reason),'')
    ) on conflict do nothing;
    if _to_status = 'rejected' then
      update public.onexa_approval_instances set status='rejected',completed_at=now(),updated_at=now()
        where id=_instance.id;
      perform onexa_private.set_business_document_status(_document_id,'rejected',_actor,_reason);
      return 'rejected';
    end if;
    select count(*) into _decision_count from public.onexa_approval_decisions decision
      where decision.instance_id=_instance.id and decision.step_id=_step.id
        and decision.decision='approved';
    if _decision_count < _step.minimum_approvals then return 'submitted'; end if;
    select * into _next_step from public.onexa_approval_workflow_steps step
      where step.workflow_id=_instance.workflow_id and step.tenant_id=_tenant
        and step.is_required and step.step_order > _step.step_order
        and step.action_key <> 'prepare'
      order by step.step_order limit 1;
    if found then
      update public.onexa_approval_instances set
        current_step_id=_next_step.id,current_step_order=_next_step.step_order,
        status=case when _next_step.action_key='post' then 'awaiting_post' else 'active' end,
        updated_at=now() where id=_instance.id;
      if _next_step.action_key='post' then
        perform onexa_private.set_business_document_status(_document_id,'approved',_actor,'workflow_approval_completed');
        return 'approved';
      end if;
      return 'submitted';
    end if;
    update public.onexa_approval_instances set status='completed',completed_at=now(),updated_at=now()
      where id=_instance.id;
    perform onexa_private.set_business_document_status(_document_id,'approved',_actor,'workflow_approval_completed');
    return 'approved';
  end if;

  -- Legacy fallback for tenants/processes without an active approval instance.
  if not (
    (_document.status='submitted' and _to_status in ('approved','rejected','cancelled')) or
    (_document.status='rejected' and _to_status in ('draft','cancelled')) or
    (_document.status='draft' and _to_status='cancelled') or
    (_document.status='approved' and _to_status='cancelled')
  ) then raise exception 'ONEXA_INVALID_STATUS_TRANSITION'; end if;
  if _to_status='approved' and _actor=_document.created_by
     and public.onexa_approval_separation_required(_document.document_type,'approve') then
    raise exception 'ONEXA_SEGREGATION_OF_DUTIES_REQUIRED';
  end if;
  if _to_status in ('rejected','cancelled') and nullif(btrim(_reason),'') is null then
    raise exception 'ONEXA_TRANSITION_REASON_REQUIRED';
  end if;
  if _document.status in ('draft','rejected') and _actor<>_document.created_by then
    raise exception 'ONEXA_ONLY_DOCUMENT_CREATOR_CAN_SUBMIT';
  end if;
  perform onexa_private.set_business_document_status(_document_id,_to_status,_actor,_reason);
  return _to_status;
end;
$function$;

create or replace view public.onexa_approval_task_inbox
with (security_invoker = true)
as
select
  document.id, document.tenant_id, document.legal_entity_id, document.branch_id,
  document.module_key, document.document_type, document.document_number,
  document.document_date, document.accounting_date, document.currency,
  document.party_name_snapshot, document.gross_total, document.created_by,
  document.submitted_by, document.submitted_at, document.revision,
  instance.id as approval_instance_id, instance.current_step_order,
  step.name_ar as current_step_name, step.action_key as current_action_key,
  step.assignee_kind, step.minimum_approvals,
  case when instance.id is null then auth.uid() <> document.created_by
    else public.onexa_can_act_on_approval_step(document.id)
  end as can_current_user_act,
  (select count(*) from public.onexa_approval_decisions decision
    where decision.instance_id=instance.id and decision.step_id=step.id
      and decision.decision='approved') as approvals_received
from public.onexa_business_documents document
left join public.onexa_approval_instances instance
  on instance.document_id=document.id and instance.tenant_id=document.tenant_id
  and instance.status='active'
left join public.onexa_approval_workflow_steps step on step.id=instance.current_step_id
where document.status='submitted';

revoke all on public.onexa_approval_instances,public.onexa_approval_decisions from anon,authenticated;
grant select on public.onexa_approval_instances,public.onexa_approval_decisions to authenticated;
grant select on public.onexa_approval_task_inbox to authenticated;
revoke all on function onexa_private.approval_actor_matches_step(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function onexa_private.set_business_document_status(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.onexa_can_act_on_approval_step(uuid) from public,anon;
grant execute on function public.onexa_can_act_on_approval_step(uuid) to authenticated;
revoke all on function public.onexa_transition_business_document(uuid,text,text) from public,anon;
grant execute on function public.onexa_transition_business_document(uuid,text,text) to authenticated;

commit;
