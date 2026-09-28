-- Gate 64: bind the approval-map post step to every installed business-document posting engine.
-- Gate 63 and posting Gates 35, 36, 39, 40, 41, 42 and 43 must be applied first.
begin;

do $preflight$
declare
  _signature text;
begin
  if to_regclass('public.onexa_approval_instances') is null
     or to_regclass('public.onexa_approval_decisions') is null
     or to_regprocedure('onexa_private.approval_actor_matches_step(uuid,uuid,uuid)') is null
     or to_regprocedure('public.onexa_approval_separation_required(text,text)') is null then
    raise exception 'ONEXA_GATE63_APPROVAL_RUNTIME_REQUIRED';
  end if;

  foreach _signature in array array[
    'public.onexa_post_sales_invoice(uuid,text)',
    'public.onexa_post_purchase_invoice(uuid,text)',
    'public.onexa_post_customer_receipt(uuid,text)',
    'public.onexa_post_supplier_payment(uuid,text)',
    'public.onexa_post_bank_transfer(uuid,text)',
    'public.onexa_post_project_cost(uuid,text)',
    'public.onexa_post_fleet_trip_cost(uuid,text)'
  ] loop
    if to_regprocedure(_signature) is null then
      raise exception 'ONEXA_GATE64_POSTING_ENGINE_REQUIRED: %', _signature;
    end if;
  end loop;
end;
$preflight$;

-- Earlier posting packages enforced creator/poster separation unconditionally.
-- Upgrade those installed functions in place so an active tenant workflow can
-- explicitly permit the same actor while the legacy fallback stays strict.
do $patch_posting_engines$
declare
  _target record;
  _oid oid;
  _definition text;
  _patched text;
  _pattern text;
  _replacement text;
begin
  for _target in
    select * from (values
      ('public.onexa_post_sales_invoice(uuid,text)', '_document'),
      ('public.onexa_post_purchase_invoice(uuid,text)', '_document'),
      ('public.onexa_post_customer_receipt(uuid,text)', '_receipt'),
      ('public.onexa_post_supplier_payment(uuid,text)', '_payment'),
      ('public.onexa_post_bank_transfer(uuid,text)', '_document'),
      ('public.onexa_post_project_cost(uuid,text)', '_document'),
      ('public.onexa_post_fleet_trip_cost(uuid,text)', '_document')
    ) targets(signature, record_name)
  loop
    _oid := to_regprocedure(_target.signature)::oid;
    _definition := pg_get_functiondef(_oid);

    if position('onexa_approval_separation_required' in _definition) > 0 then
      continue;
    end if;

    _pattern := format(
      'if[[:space:]]+(_actor[[:space:]]*=[[:space:]]*%1$s\.created_by|%1$s\.created_by[[:space:]]*=[[:space:]]*_actor)[[:space:]]+then[[:space:]]+raise exception[[:space:]]+''ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'';[[:space:]]+end if;',
      _target.record_name
    );
    _replacement := format(
      E'if _actor = %1$s.created_by\n     and public.onexa_approval_separation_required(%1$s.document_type, ''post'') then\n    raise exception ''ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'';\n  end if;',
      _target.record_name
    );
    _patched := regexp_replace(_definition, _pattern, _replacement, 'i');

    if _patched = _definition then
      raise exception 'ONEXA_GATE64_SEPARATION_GUARD_PATCH_FAILED: %', _target.signature;
    end if;
    execute _patched;
  end loop;
end;
$patch_posting_engines$;

create or replace function onexa_private.guard_approval_posting()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _instance public.onexa_approval_instances%rowtype;
  _step public.onexa_approval_workflow_steps%rowtype;
  _workflow_requires_post boolean := false;
begin
  if _actor is null or nullif(_tenant, '') is null or _tenant <> old.tenant_id then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if new.posted_by is distinct from _actor or new.posted_journal_id is null then
    raise exception 'ONEXA_GOVERNED_POSTING_AUDIT_REQUIRED';
  end if;

  select * into _instance
  from public.onexa_approval_instances instance
  where instance.tenant_id = old.tenant_id
    and instance.document_id = old.id
    and instance.status = 'awaiting_post'
  order by instance.started_at desc
  limit 1
  for update;

  if found then
    select * into _step
    from public.onexa_approval_workflow_steps step
    where step.id = _instance.current_step_id
      and step.tenant_id = old.tenant_id;

    if _step.id is null or _step.action_key <> 'post' then
      raise exception 'ONEXA_APPROVAL_POST_STEP_REQUIRED';
    end if;
    if not onexa_private.approval_actor_matches_step(_step.id, old.id, _actor) then
      raise exception 'ONEXA_POST_STEP_NOT_ASSIGNED_TO_ACTOR';
    end if;
    if _actor = old.created_by
       and public.onexa_approval_separation_required(old.document_type, 'post') then
      raise exception 'ONEXA_SEGREGATION_OF_DUTIES_REQUIRED';
    end if;
    return new;
  end if;

  select exists (
    select 1
    from public.onexa_approval_workflows workflow
    join public.onexa_approval_workflow_steps step
      on step.workflow_id = workflow.id and step.tenant_id = workflow.tenant_id
    where workflow.tenant_id = old.tenant_id
      and workflow.process_key = old.document_type
      and workflow.is_active
      and step.is_required
      and step.action_key = 'post'
  ) into _workflow_requires_post;

  if _workflow_requires_post then
    raise exception 'ONEXA_APPROVAL_POST_INSTANCE_REQUIRED';
  end if;
  if _actor = old.created_by
     and public.onexa_approval_separation_required(old.document_type, 'post') then
    raise exception 'ONEXA_SEGREGATION_OF_DUTIES_REQUIRED';
  end if;
  return new;
end;
$function$;

create or replace function onexa_private.finalize_approval_posting()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _actor uuid := auth.uid();
  _instance public.onexa_approval_instances%rowtype;
  _step public.onexa_approval_workflow_steps%rowtype;
begin
  select * into _instance
  from public.onexa_approval_instances instance
  where instance.tenant_id = new.tenant_id
    and instance.document_id = new.id
    and instance.status = 'awaiting_post'
  order by instance.started_at desc
  limit 1
  for update;

  if not found then return null; end if;

  select * into _step
  from public.onexa_approval_workflow_steps step
  where step.id = _instance.current_step_id
    and step.tenant_id = new.tenant_id;

  insert into public.onexa_approval_decisions (
    tenant_id, instance_id, document_id, step_id, step_order, step_snapshot,
    actor_user_id, decision, reason
  ) values (
    new.tenant_id, _instance.id, new.id, _step.id, _step.step_order,
    to_jsonb(_step), _actor, 'posted', 'journal:' || new.posted_journal_id::text
  ) on conflict do nothing;

  update public.onexa_approval_instances
  set status = 'completed', completed_at = now(), updated_at = now()
  where id = _instance.id and status = 'awaiting_post';

  return null;
end;
$function$;

drop trigger if exists onexa_guard_approval_posting on public.onexa_business_documents;
create trigger onexa_guard_approval_posting
before update on public.onexa_business_documents
for each row
when (old.status = 'approved' and new.status = 'posted')
execute function onexa_private.guard_approval_posting();

drop trigger if exists onexa_finalize_approval_posting on public.onexa_business_documents;
create trigger onexa_finalize_approval_posting
after update on public.onexa_business_documents
for each row
when (old.status = 'approved' and new.status = 'posted')
execute function onexa_private.finalize_approval_posting();

-- Preserve the original inbox columns and append assignment-aware posting data.
create or replace view public.onexa_accounting_inbox
with (security_invoker = true)
as
select
  document.id,
  document.tenant_id,
  document.legal_entity_id,
  document.branch_id,
  document.module_key,
  document.document_type,
  document.document_number,
  document.document_date,
  document.accounting_date,
  document.currency,
  document.party_type,
  document.party_id,
  document.party_name_snapshot,
  document.gross_total,
  document.dimensions,
  document.approved_by,
  document.approved_at,
  document.revision,
  instance.id as approval_instance_id,
  step.name_ar as posting_step_name,
  case
    when instance.id is not null then
      onexa_private.has_module_action(auth.uid(), document.module_key, 'post')
      and onexa_private.approval_actor_matches_step(step.id, document.id, auth.uid())
      and (
        auth.uid() <> document.created_by
        or not public.onexa_approval_separation_required(document.document_type, 'post')
      )
    when exists (
      select 1
      from public.onexa_approval_workflows workflow
      join public.onexa_approval_workflow_steps required_step
        on required_step.workflow_id = workflow.id
        and required_step.tenant_id = workflow.tenant_id
      where workflow.tenant_id = document.tenant_id
        and workflow.process_key = document.document_type
        and workflow.is_active
        and required_step.is_required
        and required_step.action_key = 'post'
    ) then false
    else
      onexa_private.has_module_action(auth.uid(), document.module_key, 'post')
      and (
        auth.uid() <> document.created_by
        or not public.onexa_approval_separation_required(document.document_type, 'post')
      )
  end as can_current_user_post
from public.onexa_business_documents document
left join lateral (
  select candidate.*
  from public.onexa_approval_instances candidate
  where candidate.tenant_id = document.tenant_id
    and candidate.document_id = document.id
    and candidate.status = 'awaiting_post'
  order by candidate.started_at desc
  limit 1
) instance on true
left join public.onexa_approval_workflow_steps step
  on step.id = instance.current_step_id and step.tenant_id = instance.tenant_id
where document.status = 'approved' and document.posted_journal_id is null;

revoke all on function onexa_private.guard_approval_posting() from public, anon, authenticated;
revoke all on function onexa_private.finalize_approval_posting() from public, anon, authenticated;
grant select on public.onexa_accounting_inbox to authenticated;

commit;
