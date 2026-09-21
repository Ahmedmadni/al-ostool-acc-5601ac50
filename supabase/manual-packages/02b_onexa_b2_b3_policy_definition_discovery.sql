-- ONEXA ERP — B2/B3 policy and function definition discovery (read only)
-- Run after 02_onexa_b2_b3_discovery.sql.
-- One result grid only. Return the complete grid before installing B2/B3.

with enum_roles as (
  select
    'app_role_enum'::text as check_type,
    ns.nspname || '.app_role' as object_name,
    'inspect'::text as status,
    string_agg(en.enumlabel, ', ' order by en.enumsortorder)::text as details
  from pg_type typ
  join pg_namespace ns on ns.oid = typ.typnamespace
  join pg_enum en on en.enumtypid = typ.oid
  where typ.typname = 'app_role'
  group by ns.nspname
),
membership_summary as (
  select
    'membership_summary'::text as check_type,
    role_key || ':' || status as object_name,
    'inspect'::text as status,
    format('tenant=%s; members=%s', tenant_id, count(*))::text as details
  from public.onexa_workspace_memberships
  group by tenant_id, role_key, status
),
onexa_policies as (
  select
    'onexa_policy'::text as check_type,
    policy.tablename || '.' || policy.policyname as object_name,
    'inspect'::text as status,
    jsonb_build_object(
      'command', policy.cmd,
      'roles', policy.roles,
      'permissive', policy.permissive,
      'using', policy.qual,
      'with_check', policy.with_check
    )::text as details
  from pg_policies policy
  where policy.schemaname = 'public'
    and policy.tablename like 'onexa\_%' escape '\'
),
sensitive_functions as (
  select
    'sensitive_function_definition'::text as check_type,
    proc.proname || '(' || pg_get_function_identity_arguments(proc.oid) || ')' as object_name,
    case
      when has_function_privilege('anon', proc.oid, 'EXECUTE') then 'anon_execute_exposed'
      when proc.prosecdef and coalesce(array_to_string(proc.proconfig, ','), '') not like '%search_path=pg_catalog%'
        then 'unsafe_search_path'
      else 'inspect'
    end::text as status,
    regexp_replace(pg_get_functiondef(proc.oid), E'[\n\r\t ]+', ' ', 'g')::text as details
  from pg_proc proc
  join pg_namespace ns on ns.oid = proc.pronamespace
  where ns.nspname = 'public'
    and proc.proname in (
      'has_permission',
      'has_role',
      'is_admin',
      'user_has_any_role',
      'log_permission_change',
      'hr_termination_revert_approval',
      'hr_termination_undo_approval'
    )
),
internal_table_access as (
  select
    'internal_table_access'::text as check_type,
    target.table_name::text as object_name,
    case
      when to_regclass('public.' || target.table_name) is null then 'missing'
      when has_table_privilege('anon', 'public.' || target.table_name, 'SELECT')
        or has_table_privilege('anon', 'public.' || target.table_name, 'INSERT')
        or has_table_privilege('anon', 'public.' || target.table_name, 'UPDATE')
        or has_table_privilege('anon', 'public.' || target.table_name, 'DELETE')
        then 'anon_access_exposed'
      when has_table_privilege('authenticated', 'public.' || target.table_name, 'SELECT')
        or has_table_privilege('authenticated', 'public.' || target.table_name, 'INSERT')
        or has_table_privilege('authenticated', 'public.' || target.table_name, 'UPDATE')
        or has_table_privilege('authenticated', 'public.' || target.table_name, 'DELETE')
        then 'authenticated_access_exposed'
      else 'internal_only'
    end::text as status,
    case
      when to_regclass('public.' || target.table_name) is null then 'not installed'
      else format(
        'anon: select=%s insert=%s update=%s delete=%s; authenticated: select=%s insert=%s update=%s delete=%s',
        has_table_privilege('anon', 'public.' || target.table_name, 'SELECT'),
        has_table_privilege('anon', 'public.' || target.table_name, 'INSERT'),
        has_table_privilege('anon', 'public.' || target.table_name, 'UPDATE'),
        has_table_privilege('anon', 'public.' || target.table_name, 'DELETE'),
        has_table_privilege('authenticated', 'public.' || target.table_name, 'SELECT'),
        has_table_privilege('authenticated', 'public.' || target.table_name, 'INSERT'),
        has_table_privilege('authenticated', 'public.' || target.table_name, 'UPDATE'),
        has_table_privilege('authenticated', 'public.' || target.table_name, 'DELETE')
      )
    end::text as details
  from (values
    ('onexa_document_sequences'::text),
    ('onexa_support_access_log'::text)
  ) target(table_name)
),
legacy_tables as (
  select
    'legacy_table_without_tenant_id'::text as check_type,
    cls.relname::text as object_name,
    case
      when has_table_privilege('anon', cls.oid, 'SELECT')
        or has_table_privilege('anon', cls.oid, 'INSERT')
        or has_table_privilege('anon', cls.oid, 'UPDATE')
        or has_table_privilege('anon', cls.oid, 'DELETE')
        or has_table_privilege('authenticated', cls.oid, 'SELECT')
        or has_table_privilege('authenticated', cls.oid, 'INSERT')
        or has_table_privilege('authenticated', cls.oid, 'UPDATE')
        or has_table_privilege('authenticated', cls.oid, 'DELETE')
        then 'client_access_review'
      else 'server_only_review'
    end::text as status,
    format(
      'rls=%s; estimated_rows=%s; anon_select=%s; anon_write=%s; authenticated_select=%s; authenticated_write=%s',
      cls.relrowsecurity,
      greatest(cls.reltuples::bigint, 0),
      has_table_privilege('anon', cls.oid, 'SELECT'),
      has_table_privilege('anon', cls.oid, 'INSERT')
        or has_table_privilege('anon', cls.oid, 'UPDATE')
        or has_table_privilege('anon', cls.oid, 'DELETE'),
      has_table_privilege('authenticated', cls.oid, 'SELECT'),
      has_table_privilege('authenticated', cls.oid, 'INSERT')
        or has_table_privilege('authenticated', cls.oid, 'UPDATE')
        or has_table_privilege('authenticated', cls.oid, 'DELETE')
    )::text as details
  from pg_class cls
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relkind in ('r', 'p')
    and cls.relname not like 'onexa\_%' escape '\'
    and not exists (
      select 1
      from information_schema.columns col
      where col.table_schema = 'public'
        and col.table_name = cls.relname
        and col.column_name = 'tenant_id'
    )
)
select * from enum_roles
union all select * from membership_summary
union all select * from internal_table_access
union all select * from onexa_policies
union all select * from sensitive_functions
union all select * from legacy_tables
order by check_type, object_name;
