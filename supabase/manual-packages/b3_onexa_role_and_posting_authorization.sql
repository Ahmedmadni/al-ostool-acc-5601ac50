-- ONEXA ERP — B3 tenant-aware role, workflow, and posting authorization
-- Requires a successful B2 install and B2 postcheck.

begin;

do $preflight$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_roles'
      and column_name = 'tenant_id' and is_nullable = 'NO'
  ) then
    raise exception 'ONEXA_B3_REQUIRES_B2';
  end if;
  if to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null
     or to_regprocedure('onexa_private.has_workspace_role(uuid,text[])') is null then
    raise exception 'ONEXA_B3_MEMBERSHIP_HELPERS_REQUIRED';
  end if;
end;
$preflight$;

create or replace function onexa_private.has_module_action(
  _user_id uuid,
  _module text,
  _action text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    _user_id = auth.uid()
    and exists (
      select 1
      from public.onexa_workspace_memberships membership
      join public.onexa_workspace workspace
        on workspace.tenant_id = membership.tenant_id
      where membership.user_id = _user_id
        and membership.tenant_id = onexa_private.claim_tenant_id()
        and membership.status = 'active'
        and workspace.status = 'active'
        and (
          membership.role_key = 'workspace_owner'
          or (
            _action = 'read'
            and membership.role_key in (
              'finance_manager', 'accountant', 'project_manager',
              'hr_manager', 'auditor_readonly'
            )
          )
          or (
            membership.role_key = 'finance_manager'
            and _module = any(array[
              'finance','sales','procurement','inventory','projects','assets','people'
            ])
            and _action = any(array['create','submit','approve','post','reverse','configure'])
          )
          or (
            membership.role_key = 'accountant'
            and _module = any(array[
              'finance','sales','procurement','inventory','projects','assets','people'
            ])
            and _action = any(array['create','submit','post','reverse'])
          )
          or (
            membership.role_key = 'project_manager'
            and _module = 'projects'
            and _action = any(array['create','submit','approve'])
          )
          or (
            membership.role_key = 'hr_manager'
            and _module = 'people'
            and _action = any(array['create','submit','approve'])
          )
        )
    )
$function$;

revoke all on function onexa_private.has_module_action(uuid, text, text) from public, anon;
grant execute on function onexa_private.has_module_action(uuid, text, text) to authenticated;

-- Tenant-aware replacements for the legacy RBAC helpers.
create or replace function public.is_admin(_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    _user_id is not null
    and onexa_private.is_active_member(_user_id)
    and (
      _user_id = auth.uid()
      or onexa_private.has_workspace_role(auth.uid(), array['workspace_owner']::text[])
    )
    and (
      onexa_private.has_workspace_role(_user_id, array['workspace_owner']::text[])
      or exists (
        select 1 from public.user_roles role_row
        where role_row.user_id = _user_id
          and role_row.tenant_id = onexa_private.claim_tenant_id()
          and role_row.role = 'admin'::public.app_role
      )
    )
$function$;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    _user_id is not null
    and onexa_private.is_active_member(_user_id)
    and (
      _user_id = auth.uid()
      or onexa_private.has_workspace_role(auth.uid(), array['workspace_owner']::text[])
    )
    and exists (
      select 1 from public.user_roles role_row
      where role_row.user_id = _user_id
        and role_row.tenant_id = onexa_private.claim_tenant_id()
        and role_row.role = _role
    )
$function$;

create or replace function public.user_has_any_role(_user_id uuid, _roles text[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    _user_id is not null
    and onexa_private.is_active_member(_user_id)
    and (
      _user_id = auth.uid()
      or onexa_private.has_workspace_role(auth.uid(), array['workspace_owner']::text[])
    )
    and exists (
      select 1 from public.user_roles role_row
      where role_row.user_id = _user_id
        and role_row.tenant_id = onexa_private.claim_tenant_id()
        and role_row.role::text = any(_roles)
    )
$function$;

create or replace function public.has_permission(
  _user_id uuid,
  _module text,
  _action text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _value boolean;
  _job_title_id uuid;
  _parts text[];
  _key text;
  _index integer;
begin
  if _user_id is null or _module is null or _action is null or _tenant_id is null then
    return false;
  end if;
  if not onexa_private.is_active_member(_user_id) then return false; end if;
  if _user_id <> auth.uid()
     and not onexa_private.has_workspace_role(auth.uid(), array['workspace_owner']::text[]) then
    return false;
  end if;
  if public.is_admin(_user_id) then return true; end if;

  _parts := string_to_array(_module, '.');
  select profile.job_title_id into _job_title_id
  from public.profiles profile
  where profile.id = _user_id and profile.tenant_id = _tenant_id;

  for _index in reverse array_length(_parts, 1)..1 loop
    _key := array_to_string(_parts[1:_index], '.');

    select permission.granted into _value
    from public.user_permissions permission
    where permission.tenant_id = _tenant_id
      and permission.user_id = _user_id
      and permission.module_key = _key
      and permission.action_key = _action;
    if found then return _value; end if;

    select bool_or(role_permission.granted) into _value
    from public.role_permissions role_permission
    join public.user_roles user_role
      on user_role.role = role_permission.role
     and user_role.tenant_id = role_permission.tenant_id
    where user_role.tenant_id = _tenant_id
      and user_role.user_id = _user_id
      and role_permission.module_key = _key
      and role_permission.action_key = _action;
    if _value is not null then return _value; end if;

    if _job_title_id is not null then
      select title_permission.granted into _value
      from public.job_title_permissions title_permission
      where title_permission.tenant_id = _tenant_id
        and title_permission.job_title_id = _job_title_id
        and title_permission.module_key = _key
        and title_permission.action_key = _action;
      if found then return _value; end if;
    end if;
  end loop;
  return false;
end;
$function$;

revoke all on function public.is_admin(uuid) from public, anon;
revoke all on function public.has_role(uuid, public.app_role) from public, anon;
revoke all on function public.user_has_any_role(uuid, text[]) from public, anon;
revoke all on function public.has_permission(uuid, text, text) from public, anon;
grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.has_role(uuid, public.app_role) to authenticated;
grant execute on function public.user_has_any_role(uuid, text[]) to authenticated;
grant execute on function public.has_permission(uuid, text, text) to authenticated;

create or replace function public.log_permission_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text;
begin
  _tenant_id := case when tg_op = 'DELETE' then old.tenant_id else new.tenant_id end;
  if auth.uid() is not null and (
    _tenant_id is distinct from onexa_private.claim_tenant_id()
    or not onexa_private.is_active_member(auth.uid())
  ) then
    raise exception 'ONEXA_PERMISSION_AUDIT_TENANT_MISMATCH';
  end if;

  if tg_op = 'INSERT' then
    insert into public.permission_audit_log(
      tenant_id, user_id, changed_by, module_key, action_key, old_value, new_value
    ) values (
      _tenant_id, new.user_id, auth.uid(), new.module_key, new.action_key, null, new.granted
    );
  elsif tg_op = 'UPDATE' and new.granted is distinct from old.granted then
    insert into public.permission_audit_log(
      tenant_id, user_id, changed_by, module_key, action_key, old_value, new_value
    ) values (
      _tenant_id, new.user_id, auth.uid(), new.module_key, new.action_key, old.granted, new.granted
    );
  elsif tg_op = 'DELETE' then
    insert into public.permission_audit_log(
      tenant_id, user_id, changed_by, module_key, action_key, old_value, new_value
    ) values (
      _tenant_id, old.user_id, auth.uid(), old.module_key, old.action_key, old.granted, null
    );
  end if;
  return coalesce(new, old);
end;
$function$;

revoke all on function public.log_permission_change() from public, anon, authenticated;

-- Harden HR reversal helpers so SECURITY DEFINER cannot cross tenants.
create or replace function public.hr_termination_undo_approval(
  _termination_id uuid,
  _target_status text
)
returns public.hr_terminations
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _employee_id uuid;
  _status text;
  _details jsonb;
  _row public.hr_terminations;
  _loan jsonb;
begin
  if auth.uid() is null or _tenant_id is null or not onexa_private.is_active_member(auth.uid()) then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if _target_status not in ('draft', 'pending') then
    raise exception 'ONEXA_INVALID_TERMINATION_TARGET_STATUS';
  end if;
  if not (
    public.has_permission(auth.uid(), 'hr.termination', 'approve')
    or public.is_admin(auth.uid())
  ) then
    raise exception 'ليست لديك صلاحية التراجع عن اعتماد إنهاء الخدمة';
  end if;

  select termination.employee_id, termination.status, termination.settlement_details
  into _employee_id, _status, _details
  from public.hr_terminations termination
  where termination.id = _termination_id and termination.tenant_id = _tenant_id
  for update;
  if not found then raise exception 'termination not found'; end if;
  if _status <> 'approved' then raise exception 'termination is not approved (%)', _status; end if;

  for _loan in
    select * from jsonb_array_elements(coalesce(_details->'_closed_loans', '[]'::jsonb))
  loop
    update public.hr_loans
    set status = 'active',
        paid_amount = (_loan->>'prior_paid_amount')::numeric,
        updated_at = now()
    where id = (_loan->>'id')::uuid and tenant_id = _tenant_id;
  end loop;

  update public.hr_loan_installments
  set paid = false, paid_at = null
  where tenant_id = _tenant_id
    and id in (
      select jsonb_array_elements_text(
        coalesce(_details->'_closed_installments', '[]'::jsonb)
      )::uuid
    );

  update public.hr_employees
  set status = 'active'
  where id = _employee_id and tenant_id = _tenant_id and status = 'terminated';

  update public.hr_terminations
  set status = _target_status,
      approved_at = null,
      approved_by = null,
      settlement_details = coalesce(settlement_details, '{}'::jsonb)
        - '_closed_loans' - '_closed_installments'
  where id = _termination_id and tenant_id = _tenant_id
  returning * into _row;
  return _row;
end;
$function$;

create or replace function public.hr_termination_revert_approval(_termination_id uuid)
returns public.hr_terminations
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  return public.hr_termination_undo_approval(_termination_id, 'pending');
end;
$function$;

revoke all on function public.hr_termination_undo_approval(uuid, text) from public, anon;
revoke all on function public.hr_termination_revert_approval(uuid) from public, anon;
grant execute on function public.hr_termination_undo_approval(uuid, text) to authenticated;
grant execute on function public.hr_termination_revert_approval(uuid) to authenticated;

-- Preserve the reviewed Gate 34/B4 implementations behind authorized wrappers.
do $rename_boundaries$
begin
  if to_regprocedure('public.onexa_create_business_document_unchecked(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb)') is null then
    alter function public.onexa_create_business_document(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb)
      rename to onexa_create_business_document_unchecked;
  end if;
  if to_regprocedure('public.onexa_transition_business_document_unchecked(uuid,text,text)') is null then
    alter function public.onexa_transition_business_document(uuid,text,text)
      rename to onexa_transition_business_document_unchecked;
  end if;
  if to_regprocedure('public.onexa_post_journal_unchecked(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null then
    alter function public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)
      rename to onexa_post_journal_unchecked;
  end if;
  if to_regprocedure('public.onexa_reverse_journal_unchecked(uuid,date,text,text)') is null then
    alter function public.onexa_reverse_journal(uuid,date,text,text)
      rename to onexa_reverse_journal_unchecked;
  end if;
end;
$rename_boundaries$;

revoke all on function public.onexa_create_business_document_unchecked(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb) from public, anon, authenticated;
revoke all on function public.onexa_transition_business_document_unchecked(uuid,text,text) from public, anon, authenticated;
revoke all on function public.onexa_post_journal_unchecked(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.onexa_reverse_journal_unchecked(uuid,date,text,text) from public, anon, authenticated;

create or replace function public.onexa_create_business_document(
  _legal_entity_id uuid, _branch_id uuid, _module_key text, _document_type text,
  _document_date date, _accounting_date date, _due_date date, _currency text,
  _party_type text, _party_id uuid, _party_name_snapshot text,
  _external_reference text, _origin text, _import_batch_id uuid,
  _subtotal numeric, _discount_total numeric, _tax_total numeric, _gross_total numeric,
  _dimensions jsonb, _source_snapshot jsonb, _memo text, _lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, onexa_private
as $function$
begin
  if auth.uid() is null or not onexa_private.has_module_action(auth.uid(), _module_key, 'create') then
    raise exception 'ONEXA_DOCUMENT_CREATE_NOT_AUTHORIZED';
  end if;
  return public.onexa_create_business_document_unchecked(
    _legal_entity_id, _branch_id, _module_key, _document_type,
    _document_date, _accounting_date, _due_date, _currency,
    _party_type, _party_id, _party_name_snapshot, _external_reference,
    _origin, _import_batch_id, _subtotal, _discount_total, _tax_total,
    _gross_total, _dimensions, _source_snapshot, _memo, _lines
  );
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
set search_path = pg_catalog, public, onexa_private
as $function$
declare
  _module_key text;
  _current_status text;
  _action text;
begin
  if auth.uid() is null or onexa_private.claim_tenant_id() is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  select document.module_key, document.status
  into _module_key, _current_status
  from public.onexa_business_documents document
  where document.id = _document_id
    and document.tenant_id = onexa_private.claim_tenant_id();
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;

  _action := case
    when _to_status = 'submitted' then 'submit'
    when _to_status in ('approved', 'rejected') then 'approve'
    when _to_status = 'cancelled' and _current_status in ('submitted', 'approved') then 'approve'
    else 'create'
  end;
  if not onexa_private.has_module_action(auth.uid(), _module_key, _action) then
    raise exception 'ONEXA_DOCUMENT_TRANSITION_NOT_AUTHORIZED';
  end if;
  return public.onexa_transition_business_document_unchecked(
    _document_id, _to_status, _reason
  );
end;
$function$;

create or replace function public.onexa_post_journal(
  _legal_entity_id uuid, _source_document_type text, _source_document_id text,
  _source_revision integer, _source_status text, _source_snapshot jsonb,
  _accounting_date date, _period_code text, _currency text, _memo text, _lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, onexa_private
as $function$
begin
  if auth.uid() is null or not onexa_private.has_module_action(auth.uid(), 'finance', 'post') then
    raise exception 'ONEXA_JOURNAL_POST_NOT_AUTHORIZED';
  end if;
  return public.onexa_post_journal_unchecked(
    _legal_entity_id, _source_document_type, _source_document_id,
    _source_revision, _source_status, _source_snapshot, _accounting_date,
    _period_code, _currency, _memo, _lines
  );
end;
$function$;

create or replace function public.onexa_reverse_journal(
  _journal_id uuid, _accounting_date date, _period_code text, _reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, onexa_private
as $function$
begin
  if auth.uid() is null or not onexa_private.has_module_action(auth.uid(), 'finance', 'reverse') then
    raise exception 'ONEXA_JOURNAL_REVERSE_NOT_AUTHORIZED';
  end if;
  return public.onexa_reverse_journal_unchecked(
    _journal_id, _accounting_date, _period_code, _reason
  );
end;
$function$;

revoke all on function public.onexa_create_business_document(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb) from public, anon;
revoke all on function public.onexa_transition_business_document(uuid,text,text) from public, anon;
revoke all on function public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb) from public, anon;
revoke all on function public.onexa_reverse_journal(uuid,date,text,text) from public, anon;
grant execute on function public.onexa_create_business_document(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb) to authenticated;
grant execute on function public.onexa_transition_business_document(uuid,text,text) to authenticated;
grant execute on function public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb) to authenticated;
grant execute on function public.onexa_reverse_journal(uuid,date,text,text) to authenticated;

-- Replace Gate 34 policies with membership- and module-aware policies.
drop policy if exists onexa_documents_select_tenant on public.onexa_business_documents;
create policy onexa_documents_select_tenant
  on public.onexa_business_documents for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), module_key, 'read')
  );

drop policy if exists onexa_documents_insert_tenant on public.onexa_business_documents;
create policy onexa_documents_insert_tenant
  on public.onexa_business_documents for insert to authenticated
  with check (
    tenant_id = onexa_private.claim_tenant_id()
    and created_by = auth.uid()
    and status = 'draft'
    and onexa_private.has_module_action(auth.uid(), module_key, 'create')
  );

drop policy if exists onexa_documents_update_tenant on public.onexa_business_documents;
create policy onexa_documents_update_tenant
  on public.onexa_business_documents for update to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and status not in ('posted', 'reversed')
    and (
      (created_by = auth.uid() and onexa_private.has_module_action(auth.uid(), module_key, 'create'))
      or coalesce(current_setting('onexa.transition_authorized', true), '') = 'true'
    )
  )
  with check (
    tenant_id = onexa_private.claim_tenant_id()
    and (
      (created_by = auth.uid() and onexa_private.has_module_action(auth.uid(), module_key, 'create'))
      or coalesce(current_setting('onexa.transition_authorized', true), '') = 'true'
    )
  );

drop policy if exists onexa_documents_delete_draft on public.onexa_business_documents;
create policy onexa_documents_delete_draft
  on public.onexa_business_documents for delete to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and created_by = auth.uid()
    and status = 'draft'
    and onexa_private.has_module_action(auth.uid(), module_key, 'create')
  );

drop policy if exists onexa_document_lines_select_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_select_tenant
  on public.onexa_business_document_lines for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and exists (
      select 1 from public.onexa_business_documents document
      where document.id = public.onexa_business_document_lines.document_id
        and document.tenant_id = public.onexa_business_document_lines.tenant_id
        and onexa_private.has_module_action(auth.uid(), document.module_key, 'read')
    )
  );

drop policy if exists onexa_document_lines_insert_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_insert_tenant
  on public.onexa_business_document_lines for insert to authenticated
  with check (
    tenant_id = onexa_private.claim_tenant_id()
    and exists (
      select 1 from public.onexa_business_documents document
      where document.id = public.onexa_business_document_lines.document_id
        and document.tenant_id = public.onexa_business_document_lines.tenant_id
        and document.created_by = auth.uid()
        and document.status in ('draft', 'rejected')
        and onexa_private.has_module_action(auth.uid(), document.module_key, 'create')
    )
  );

drop policy if exists onexa_document_lines_update_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_update_tenant
  on public.onexa_business_document_lines for update to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and exists (
      select 1 from public.onexa_business_documents document
      where document.id = public.onexa_business_document_lines.document_id
        and document.tenant_id = public.onexa_business_document_lines.tenant_id
        and document.created_by = auth.uid()
        and document.status in ('draft', 'rejected')
        and onexa_private.has_module_action(auth.uid(), document.module_key, 'create')
    )
  )
  with check (
    tenant_id = onexa_private.claim_tenant_id()
    and exists (
      select 1 from public.onexa_business_documents document
      where document.id = public.onexa_business_document_lines.document_id
        and document.tenant_id = public.onexa_business_document_lines.tenant_id
        and document.created_by = auth.uid()
        and document.status in ('draft', 'rejected')
        and onexa_private.has_module_action(auth.uid(), document.module_key, 'create')
    )
  );

drop policy if exists onexa_document_lines_delete_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_delete_tenant
  on public.onexa_business_document_lines for delete to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and exists (
      select 1 from public.onexa_business_documents document
      where document.id = public.onexa_business_document_lines.document_id
        and document.tenant_id = public.onexa_business_document_lines.tenant_id
        and document.created_by = auth.uid()
        and document.status in ('draft', 'rejected')
        and onexa_private.has_module_action(auth.uid(), document.module_key, 'create')
    )
  );

drop policy if exists onexa_document_events_select_tenant on public.onexa_business_document_events;
create policy onexa_document_events_select_tenant
  on public.onexa_business_document_events for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and exists (
      select 1 from public.onexa_business_documents document
      where document.id = public.onexa_business_document_events.document_id
        and document.tenant_id = public.onexa_business_document_events.tenant_id
        and onexa_private.has_module_action(auth.uid(), document.module_key, 'read')
    )
  );

commit;
