-- ONEXA Gate 60 postcheck. Read-only.

with expected(routine_name, signature) as (
  values
    ('handle_new_user'::text, 'public.handle_new_user()'::text),
    (
      'onexa_activate_accountant_user',
      'public.onexa_activate_accountant_user(uuid)'
    )
)
select
  expected.routine_name,
  case
    when to_regprocedure(expected.signature) is not null
      then 'READY'
    else 'MISSING'
  end as status
from expected
order by expected.routine_name;

select
  procedure.oid::regprocedure::text as function_signature,
  procedure.prosecdef as security_definer,
  coalesce(procedure.proconfig, array[]::text[])
    @> array['search_path=pg_catalog, public, auth']
    as fixed_search_path,
  has_function_privilege(
    'authenticated',
    procedure.oid,
    'EXECUTE'
  ) as authenticated_can_execute,
  has_function_privilege(
    'anon',
    procedure.oid,
    'EXECUTE'
  ) as anon_can_execute
from pg_proc procedure
join pg_namespace namespace
  on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.proname = 'onexa_activate_accountant_user';

select
  trigger_row.tgname as trigger_name,
  trigger_row.tgenabled <> 'D' as trigger_enabled,
  trigger_row.tgfoid::regprocedure::text as trigger_function
from pg_trigger trigger_row
where trigger_row.tgrelid = 'auth.users'::regclass
  and not trigger_row.tgisinternal
order by trigger_row.tgname;

select
  column_row.table_name,
  column_row.column_name,
  column_row.is_nullable,
  column_row.column_default,
  case
    when column_row.is_nullable = 'NO' then 'READY'
    else 'TENANT_COLUMN_NOT_REQUIRED'
  end as status
from information_schema.columns column_row
where column_row.table_schema = 'public'
  and (
    (
      column_row.table_name = 'profiles'
      and column_row.column_name = 'tenant_id'
    )
    or (
      column_row.table_name = 'user_roles'
      and column_row.column_name = 'tenant_id'
    )
  )
order by column_row.table_name;

select
  membership.role_key,
  membership.status,
  count(distinct membership.user_id) as user_count
from public.onexa_workspace_memberships membership
where membership.tenant_id = 'tenant-001-al-ostool'
group by membership.role_key, membership.status
order by membership.status, membership.role_key;
