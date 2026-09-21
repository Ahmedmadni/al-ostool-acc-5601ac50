-- ONEXA ERP — B2/B3 production-schema discovery (read only)
-- Run after Gate 34 and before installing B2, B3, or Gate 35.
-- Return the complete single result grid for package generation.

with tenant_tables as (
  select
    'tenant_table'::text as check_type,
    cols.table_name::text as object_name,
    case
      when not cls.relrowsecurity then 'rls_disabled'
      when coalesce(pol.policy_count, 0) = 0 then 'policy_missing'
      else 'inspect'
    end::text as status,
    format(
      'tenant_id=%s; nullable=%s; rls=%s; policies=%s; commands=%s; estimated_rows=%s',
      cols.data_type,
      cols.is_nullable,
      cls.relrowsecurity,
      coalesce(pol.policy_count, 0),
      coalesce(pol.commands, 'none'),
      greatest(cls.reltuples::bigint, 0)
    )::text as details
  from information_schema.columns cols
  join pg_class cls
    on cls.oid = to_regclass(format('%I.%I', cols.table_schema, cols.table_name))
  left join lateral (
    select
      count(*)::integer as policy_count,
      string_agg(distinct upper(policy.cmd), ',' order by upper(policy.cmd)) as commands
    from pg_policies policy
    where policy.schemaname = cols.table_schema
      and policy.tablename = cols.table_name
  ) pol on true
  where cols.table_schema = 'public'
    and cols.column_name = 'tenant_id'
    and cls.relkind in ('r', 'p')
),
authorization_tables as (
  select
    'authorization_table'::text as check_type,
    cols.table_name::text as object_name,
    'inspect'::text as status,
    string_agg(
      format('%I:%s%s', cols.column_name, cols.data_type,
        case when cols.is_nullable = 'NO' then ':required' else '' end),
      ', ' order by cols.ordinal_position
    )::text as details
  from information_schema.columns cols
  where cols.table_schema = 'public'
    and (
      cols.table_name ilike '%member%'
      or cols.table_name ilike '%role%'
      or cols.table_name ilike '%permission%'
      or cols.table_name ilike '%approval%'
    )
  group by cols.table_name
),
authorization_functions as (
  select
    'authorization_function'::text as check_type,
    proc.proname::text as object_name,
    case
      when proc.prosecdef and not coalesce(proc.proconfig, array[]::text[]) @> array['search_path=pg_catalog, public']::text[]
        then 'review_search_path'
      else 'inspect'
    end::text as status,
    format(
      'args=(%s); security=%s; config=%s; anon_execute=%s; authenticated_execute=%s',
      pg_get_function_identity_arguments(proc.oid),
      case when proc.prosecdef then 'definer' else 'invoker' end,
      coalesce(array_to_string(proc.proconfig, ','), 'none'),
      has_function_privilege('anon', proc.oid, 'EXECUTE'),
      has_function_privilege('authenticated', proc.oid, 'EXECUTE')
    )::text as details
  from pg_proc proc
  join pg_namespace ns on ns.oid = proc.pronamespace
  where ns.nspname = 'public'
    and (
      proc.proname ilike '%tenant%'
      or proc.proname ilike '%member%'
      or proc.proname ilike '%role%'
      or proc.proname ilike '%permission%'
      or proc.proname ilike '%approval%'
      or proc.proname ilike '%authorize%'
      or proc.proname ilike '%admin%'
    )
),
jwt_claims as (
  select
    'jwt_app_metadata'::text as check_type,
    'auth.users'::text as object_name,
    case
      when count(*) filter (
        where raw_app_meta_data->>'onexa_tenant_id' = 'tenant-001-al-ostool'
      ) > 0 then 'inspect'
      else 'tenant_claim_missing'
    end::text as status,
    jsonb_build_object(
      'total_users', count(*),
      'tenant_001_users', count(*) filter (
        where raw_app_meta_data->>'onexa_tenant_id' = 'tenant-001-al-ostool'
      ),
      'tenant_001_with_role', count(*) filter (
        where raw_app_meta_data->>'onexa_tenant_id' = 'tenant-001-al-ostool'
          and coalesce(raw_app_meta_data->>'onexa_role', '') <> ''
      ),
      'distinct_tenant_claims', count(distinct raw_app_meta_data->>'onexa_tenant_id') filter (
        where coalesce(raw_app_meta_data->>'onexa_tenant_id', '') <> ''
      )
    )::text as details
  from auth.users
)
select * from jwt_claims
union all select * from authorization_tables
union all select * from authorization_functions
union all select * from tenant_tables
order by check_type, object_name;
