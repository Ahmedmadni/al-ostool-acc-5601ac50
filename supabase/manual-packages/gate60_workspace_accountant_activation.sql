-- ONEXA Gate 60: tenant-safe creation and activation of a second accountant.
-- Apply this complete transaction before enabling the workspace accountant UI.

begin;

do $preflight$
begin
  if to_regclass('public.onexa_workspace') is null
     or to_regclass('public.onexa_workspace_memberships') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.user_roles') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null then
    raise exception 'ONEXA_GATE60_WORKSPACE_FOUNDATION_REQUIRED';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'tenant_id'
      and is_nullable = 'NO'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_roles'
      and column_name = 'tenant_id'
      and is_nullable = 'NO'
  ) then
    raise exception 'ONEXA_GATE60_B2_TENANT_COLUMNS_REQUIRED';
  end if;
end;
$preflight$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text :=
    nullif(new.raw_app_meta_data->>'onexa_tenant_id', '');
  _user_count integer;
  _employee_id text :=
    nullif(btrim(new.raw_user_meta_data->>'employee_id'), '');
  _phone text :=
    nullif(btrim(new.raw_user_meta_data->>'phone'), '');
  _department_id uuid;
  _job_title_id uuid;
begin
  if _tenant_id is null then
    raise exception 'ONEXA_NEW_USER_TENANT_CLAIM_REQUIRED';
  end if;

  perform 1
  from public.onexa_workspace workspace
  where workspace.tenant_id = _tenant_id
    and workspace.status = 'active';

  if not found then
    raise exception 'ONEXA_ACTIVE_WORKSPACE_REQUIRED';
  end if;

  begin
    _department_id :=
      nullif(new.raw_user_meta_data->>'department_id', '')::uuid;
  exception
    when invalid_text_representation then
      _department_id := null;
  end;

  begin
    _job_title_id :=
      nullif(new.raw_user_meta_data->>'job_title_id', '')::uuid;
  exception
    when invalid_text_representation then
      _job_title_id := null;
  end;

  select count(*)
  into _user_count
  from public.user_roles role_row
  where role_row.tenant_id = _tenant_id;

  insert into public.profiles (
    id,
    tenant_id,
    full_name,
    email,
    employee_id,
    phone,
    department_id,
    job_title_id,
    status
  )
  values (
    new.id,
    _tenant_id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
      new.email
    ),
    lower(new.email),
    _employee_id,
    _phone,
    _department_id,
    _job_title_id,
    case when _user_count = 0 then 'active' else 'pending' end
  )
  on conflict (id) do nothing;

  if _user_count = 0 then
    insert into public.user_roles (
      tenant_id,
      user_id,
      role
    )
    values (
      _tenant_id,
      new.id,
      'admin'::public.app_role
    )
    on conflict do nothing;
  end if;

  return new;
end;
$function$;

revoke all on function public.handle_new_user()
  from public, anon, authenticated;

create or replace function public.onexa_activate_accountant_user(
  _target_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  _actor uuid := auth.uid();
  _tenant_id text := onexa_private.claim_tenant_id();
  _membership public.onexa_workspace_memberships%rowtype;
  _target_email text;
  _max_active_users integer;
  _active_count integer;
begin
  if _actor is null
     or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;

  if _target_user_id is null
     or _target_user_id = _actor then
    raise exception 'ONEXA_DISTINCT_ACCOUNTANT_USER_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.onexa_workspace_memberships membership
    where membership.tenant_id = _tenant_id
      and membership.user_id = _actor
      and membership.role_key = 'workspace_owner'
      and membership.status = 'active'
  ) then
    raise exception 'ONEXA_WORKSPACE_OWNER_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      _tenant_id || ':workspace-members',
      0
    )
  );

  select workspace.max_active_users
  into _max_active_users
  from public.onexa_workspace workspace
  where workspace.tenant_id = _tenant_id
    and workspace.status = 'active'
  for update;

  if not found then
    raise exception 'ONEXA_ACTIVE_WORKSPACE_REQUIRED';
  end if;

  select *
  into _membership
  from public.onexa_workspace_memberships membership
  where membership.tenant_id = _tenant_id
    and membership.user_id = _target_user_id
  for update;

  if found
     and _membership.status = 'active'
     and _membership.role_key = 'accountant' then
    return _membership.id;
  end if;

  if found and _membership.status = 'active' then
    raise exception
      'ONEXA_TARGET_ALREADY_HAS_ACTIVE_ROLE:%',
      _membership.role_key;
  end if;

  if exists (
    select 1
    from public.onexa_workspace_memberships membership
    where membership.user_id = _target_user_id
      and membership.tenant_id <> _tenant_id
      and membership.status = 'active'
  ) then
    raise exception
      'ONEXA_TARGET_BELONGS_TO_ANOTHER_WORKSPACE';
  end if;

  select lower(users.email)
  into _target_email
  from auth.users users
  where users.id = _target_user_id
    and users.raw_app_meta_data->>'onexa_tenant_id' = _tenant_id;

  if _target_email is null then
    raise exception
      'ONEXA_TARGET_AUTH_USER_WITH_TENANT_CLAIM_REQUIRED';
  end if;

  select count(*)
  into _active_count
  from public.onexa_workspace_memberships membership
  where membership.tenant_id = _tenant_id
    and membership.status = 'active';

  if _max_active_users is not null
     and _active_count >= _max_active_users then
    raise exception 'ONEXA_WORKSPACE_SEAT_LIMIT_REACHED';
  end if;

  if _membership.id is null then
    insert into public.onexa_workspace_memberships (
      tenant_id,
      user_id,
      role_key,
      status
    )
    values (
      _tenant_id,
      _target_user_id,
      'accountant',
      'active'
    )
    returning *
    into _membership;
  else
    update public.onexa_workspace_memberships
    set
      role_key = 'accountant',
      status = 'active',
      updated_at = now()
    where id = _membership.id
    returning *
    into _membership;
  end if;

  update public.profiles
  set
    status = 'active',
    approved_by = _actor,
    approved_at = now(),
    updated_at = now()
  where id = _target_user_id
    and tenant_id = _tenant_id;

  if not found then
    raise exception 'ONEXA_TARGET_PROFILE_REQUIRED';
  end if;

  insert into public.user_roles (
    tenant_id,
    user_id,
    role
  )
  values (
    _tenant_id,
    _target_user_id,
    'accountant'::public.app_role
  )
  on conflict do nothing;

  if to_regclass('public.onexa_workspace_invitations') is not null then
    execute
      'update public.onexa_workspace_invitations
       set status = $1, accepted_at = now()
       where tenant_id = $2
         and lower(email) = $3
         and role_key = $4
         and status = $5'
    using
      'accepted',
      _tenant_id,
      _target_email,
      'accountant',
      'pending';
  end if;

  if to_regclass('public.onexa_workspace_audit_events') is not null then
    execute
      'insert into public.onexa_workspace_audit_events (
         tenant_id,
         actor_user_id,
         action,
         entity_type,
         entity_id,
         details
       )
       values ($1, $2, $3, $4, $5, $6)'
    using
      _tenant_id,
      _actor,
      'accountant_activated',
      'workspace_membership',
      _membership.id::text,
      jsonb_build_object(
        'target_user_id',
        _target_user_id,
        'target_email',
        _target_email,
        'role_key',
        'accountant'
      );
  end if;

  return _membership.id;
end;
$function$;

revoke all on function public.onexa_activate_accountant_user(uuid)
  from public, anon;
grant execute on function public.onexa_activate_accountant_user(uuid)
  to authenticated;

commit;
