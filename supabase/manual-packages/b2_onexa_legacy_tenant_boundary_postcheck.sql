-- ONEXA ERP — B2 post-install verification (read only)
-- Every returned table must have status = ready. Expected row count: 98.

with targets as (
  select cls.oid, cls.relname, cls.relrowsecurity
  from pg_class cls
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relkind in ('r', 'p')
    and cls.relname not like 'onexa\_%' escape '\'
    and exists (
      select 1 from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = cls.relname
        and policy.policyname = 'onexa_tenant_boundary_restrictive'
    )
),
checks as (
  select
    target.relname as object_name,
    case
      when col.column_name is null then 'tenant_column_missing'
      when col.is_nullable <> 'NO' then 'tenant_nullable'
      when coalesce(col.column_default, '') not like '%claim_tenant_id%' then 'tenant_default_missing'
      when not target.relrowsecurity then 'rls_disabled'
      when policy.policyname is null or policy.permissive <> 'RESTRICTIVE' then 'restrictive_policy_missing'
      when constraint_row.oid is null or not constraint_row.convalidated then 'tenant_fk_missing_or_unvalidated'
      when has_table_privilege('anon', target.oid, 'SELECT')
        or has_table_privilege('anon', target.oid, 'INSERT')
        or has_table_privilege('anon', target.oid, 'UPDATE')
        or has_table_privilege('anon', target.oid, 'DELETE') then 'anon_access_exposed'
      else 'ready'
    end as status,
    format(
      'tenant_type=%s; nullable=%s; default=%s; rls=%s; policy=%s; fk_validated=%s; anon_any=%s',
      coalesce(col.data_type, 'missing'),
      coalesce(col.is_nullable, 'missing'),
      coalesce(col.column_default, 'missing'),
      target.relrowsecurity,
      coalesce(policy.permissive, 'missing'),
      coalesce(constraint_row.convalidated, false),
      has_table_privilege('anon', target.oid, 'SELECT')
        or has_table_privilege('anon', target.oid, 'INSERT')
        or has_table_privilege('anon', target.oid, 'UPDATE')
        or has_table_privilege('anon', target.oid, 'DELETE')
    ) as details
  from targets target
  left join information_schema.columns col
    on col.table_schema = 'public'
   and col.table_name = target.relname
   and col.column_name = 'tenant_id'
  left join pg_policies policy
    on policy.schemaname = 'public'
   and policy.tablename = target.relname
   and policy.policyname = 'onexa_tenant_boundary_restrictive'
  left join pg_constraint constraint_row
    on constraint_row.conrelid = target.oid
   and constraint_row.conname = 'onexa_tenant_id_fkey'
)
select
  'b2_table'::text as check_type,
  object_name,
  status,
  details
from checks
union all
select
  'b2_summary',
  'legacy_tenant_boundary',
  case
    when count(*) = 98 and bool_and(status = 'ready') then 'ready'
    else 'failed'
  end,
  format('tables=%s; ready=%s; expected=98', count(*), count(*) filter (where status = 'ready'))
from checks
order by check_type, object_name;
