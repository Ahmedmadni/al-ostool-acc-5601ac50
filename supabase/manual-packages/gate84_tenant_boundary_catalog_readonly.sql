-- Gate 84: metadata-only tenant boundary audit. SELECT ONLY.
-- No business data, customer identifiers, DDL, DML, privilege changes or deployment.
WITH target(table_name) AS (
 VALUES ('onexa_legal_entities'), ('onexa_branches'),
 ('onexa_business_documents'), ('onexa_approval_instances'),
 ('onexa_project_cost_centers'), ('onexa_project_cost_postings'),
 ('onexa_company_module_scopes'), ('onexa_operations_sites'),
 ('onexa_operations_assets'), ('onexa_operations_work_orders'),
 ('onexa_operations_work_order_events'),
 ('onexa_native_maintenance_cost_scopes'),
 ('onexa_native_maintenance_cost_attributions'),
 ('onexa_native_maintenance_unpaid_sources')
)
SELECT t.table_name,
 CASE WHEN c.oid IS NULL THEN 'MISSING_TABLE'
      WHEN NOT c.relrowsecurity THEN 'RLS_DISABLED'
      WHEN NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies p
        WHERE p.schemaname='public' AND p.tablename=t.table_name
      ) THEN 'NO_POLICIES'
      ELSE 'INSPECT_EFFECTIVE_POLICIES'
 END AS boundary_status,
 COALESCE(c.relforcerowsecurity,false) AS force_rls,
 (SELECT count(*) FROM pg_catalog.pg_policies p
  WHERE p.schemaname='public' AND p.tablename=t.table_name) AS policy_count
FROM target t
LEFT JOIN pg_catalog.pg_namespace n ON n.nspname='public'
LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid
 AND c.relname=t.table_name AND c.relkind IN ('r','p')
ORDER BY t.table_name;

-- Constraint metadata: identify which keys are backed by the tenant boundary.
-- A tenant_id in an FK alone is not sufficient to prove isolation.
SELECT con.conrelid::regclass::text AS source_table,
 con.conname AS constraint_name, con.contype AS constraint_type,
 con.confrelid::regclass::text AS referenced_table,
 array_agg(att.attname ORDER BY ord.ordinality) AS source_columns,
 bool_or(att.attname='tenant_id') AS source_includes_tenant_id,
 CASE WHEN con.contype='f' AND NOT bool_or(att.attname='tenant_id')
      THEN 'REVIEW_CROSS_TENANT_FK'
      ELSE 'INSPECT_COMPOSITE_KEY' END AS audit_status
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_namespace ns ON ns.oid=con.connamespace
JOIN LATERAL unnest(con.conkey) WITH ORDINALITY ord(attnum,ordinality) ON true
JOIN pg_catalog.pg_attribute att ON att.attrelid=con.conrelid AND att.attnum=ord.attnum
WHERE ns.nspname='public' AND con.contype IN ('p','u','f')
 AND con.conrelid::regclass::text LIKE 'onexa_%'
GROUP BY con.conrelid,con.conname,con.contype,con.confrelid
ORDER BY source_table,constraint_name;

-- Observe configured policies only: never assume their predicates are correct.
SELECT schemaname,tablename,policyname,cmd,roles,qual,with_check
FROM pg_catalog.pg_policies
WHERE schemaname='public' AND tablename IN (
 'onexa_business_documents','onexa_approval_instances',
 'onexa_project_cost_postings','onexa_operations_work_orders',
 'onexa_native_maintenance_unpaid_sources'
) ORDER BY tablename,policyname;
