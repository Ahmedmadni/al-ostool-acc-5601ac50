-- ONEXA ERP — final B2/B3 contract discovery (read only)
-- This is the last discovery query before generating the B2/B3 install packages.
-- Export and return the complete single result grid.

with private_functions as (
  select
    'private_authorization_function'::text as check_type,
    ns.nspname || '.' || proc.proname || '(' || pg_get_function_identity_arguments(proc.oid) || ')' as object_name,
    case
      when proc.prosecdef and coalesce(array_to_string(proc.proconfig, ','), '') not like '%search_path=pg_catalog%'
        then 'unsafe_search_path'
      else 'inspect'
    end::text as status,
    regexp_replace(pg_get_functiondef(proc.oid), E'[\n\r\t ]+', ' ', 'g')::text as details
  from pg_proc proc
  join pg_namespace ns on ns.oid = proc.pronamespace
  where ns.nspname = 'onexa_private'
    and proc.proname in ('claim_tenant_id', 'is_active_member', 'has_workspace_role')
),
journal_functions as (
  select
    'journal_function_contract'::text as check_type,
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
    and proc.proname in ('onexa_post_journal', 'onexa_reverse_journal')
),
key_constraints as (
  select
    'key_table_constraint'::text as check_type,
    cls.relname || '.' || con.conname as object_name,
    'inspect'::text as status,
    pg_get_constraintdef(con.oid, true)::text as details
  from pg_constraint con
  join pg_class cls on cls.oid = con.conrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname in ('onexa_workspace_memberships', 'onexa_account_role_mappings')
),
critical_legacy_policies as (
  select
    'critical_legacy_policy'::text as check_type,
    policy.tablename || '.' || policy.policyname as object_name,
    case
      when policy.roles && array['anon'::name] then 'anon_policy_review'
      when coalesce(policy.qual, '') in ('true', '(true)')
        or coalesce(policy.with_check, '') in ('true', '(true)') then 'unrestricted_policy_review'
      else 'inspect'
    end::text as status,
    jsonb_build_object(
      'command', policy.cmd,
      'roles', policy.roles,
      'permissive', policy.permissive,
      'using', policy.qual,
      'with_check', policy.with_check
    )::text as details
  from pg_policies policy
  where policy.schemaname = 'public'
    and policy.tablename in (
      'profiles', 'user_roles', 'user_permissions', 'role_permissions',
      'job_title_permissions', 'permission_audit_log', 'hr_terminations',
      'hr_loans', 'hr_loan_installments', 'hr_employees'
    )
),
legacy_base as (
  select cls.oid, cls.relname, cls.relrowsecurity, greatest(cls.reltuples::bigint, 0) as estimated_rows
  from pg_class cls
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relkind in ('r', 'p')
    and cls.relname not like 'onexa\_%' escape '\'
    and not exists (
      select 1 from information_schema.columns col
      where col.table_schema = 'public'
        and col.table_name = cls.relname
        and col.column_name = 'tenant_id'
    )
),
policy_summary as (
  select
    base.relname,
    count(policy.policyname)::integer as policy_count,
    string_agg(distinct policy.cmd, ',' order by policy.cmd) as commands,
    string_agg(distinct policy.policyname, ', ' order by policy.policyname) as policy_names,
    bool_or(coalesce(policy.qual, '') in ('true', '(true)')) as unrestricted_using,
    bool_or(coalesce(policy.with_check, '') in ('true', '(true)')) as unrestricted_check
  from legacy_base base
  left join pg_policies policy
    on policy.schemaname = 'public' and policy.tablename = base.relname
  group by base.relname
),
scope_columns as (
  select
    col.table_name,
    string_agg(col.column_name || ':' || col.data_type, ', ' order by col.ordinal_position) as candidates
  from information_schema.columns col
  where col.table_schema = 'public'
    and col.column_name in (
      'company_id', 'legal_entity_id', 'workspace_id', 'organization_id',
      'project_id', 'user_id', 'created_by', 'employee_id', 'owner_id'
    )
  group by col.table_name
),
foreign_keys as (
  select
    cls.relname,
    string_agg(pg_get_constraintdef(con.oid, true), ' | ' order by con.conname) as definitions
  from pg_constraint con
  join pg_class cls on cls.oid = con.conrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public' and con.contype = 'f'
  group by cls.relname
),
legacy_boundary as (
  select
    'legacy_boundary_contract'::text as check_type,
    base.relname::text as object_name,
    case
      when summary.policy_count = 0 then 'no_policy'
      when coalesce(summary.unrestricted_using, false) or coalesce(summary.unrestricted_check, false)
        then 'unrestricted_policy_review'
      when scope.candidates is null then 'scope_mapping_required'
      else 'inspect'
    end::text as status,
    format(
      'rls=%s; estimated_rows=%s; policies=%s; commands=%s; policy_names=%s; scope_columns=%s; foreign_keys=%s',
      base.relrowsecurity,
      base.estimated_rows,
      summary.policy_count,
      coalesce(summary.commands, 'none'),
      coalesce(summary.policy_names, 'none'),
      coalesce(scope.candidates, 'none'),
      coalesce(fk.definitions, 'none')
    )::text as details
  from legacy_base base
  join policy_summary summary on summary.relname = base.relname
  left join scope_columns scope on scope.table_name = base.relname
  left join foreign_keys fk on fk.relname = base.relname
)
select * from private_functions
union all select * from journal_functions
union all select * from key_constraints
union all select * from critical_legacy_policies
union all select * from legacy_boundary
order by check_type, object_name;
