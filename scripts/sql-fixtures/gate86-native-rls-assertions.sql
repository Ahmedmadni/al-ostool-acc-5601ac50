-- Gate 86: run only on disposable PostgreSQL test database after real G71-G75.
-- Fail closed when tenant-bearing tables lose RLS, a SELECT policy, or tenant_id.
-- Catalog metadata only. Never run against company production.
DO $gate86$
DECLARE
  name text;
  oid_value oid;
  enabled boolean;
  policy_total integer;
  tenant_column boolean;
BEGIN
  IF current_database() <> 'onexa_gate_test' THEN
    RAISE EXCEPTION 'GATE86_DISPOSABLE_DATABASE_REQUIRED';
  END IF;
  FOREACH name IN ARRAY ARRAY[
    'onexa_company_module_scopes',
    'onexa_operations_sites',
    'onexa_operations_assets',
    'onexa_operations_work_orders',
    'onexa_operations_work_order_events',
    'onexa_native_maintenance_cost_scopes',
    'onexa_native_maintenance_cost_attributions',
    'onexa_native_maintenance_unpaid_sources'
  ] LOOP
    oid_value := to_regclass('public.' || name);
    IF oid_value IS NULL THEN
      RAISE EXCEPTION 'GATE86_MISSING_TABLE: %', name;
    END IF;
    SELECT relrowsecurity INTO enabled FROM pg_catalog.pg_class WHERE oid=oid_value;
    IF NOT enabled THEN
      RAISE EXCEPTION 'GATE86_RLS_DISABLED: %', name;
    END IF;
    SELECT EXISTS(
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid=oid_value AND attname='tenant_id'
        AND NOT attisdropped
    ) INTO tenant_column;
    IF NOT tenant_column THEN
      RAISE EXCEPTION 'GATE86_TENANT_COLUMN_MISSING: %', name;
    END IF;
    SELECT count(*) INTO policy_total FROM pg_catalog.pg_policies
    WHERE schemaname='public' AND tablename=name
      AND cmd IN ('SELECT','ALL');
    IF policy_total=0 THEN
      RAISE EXCEPTION 'GATE86_SELECT_POLICY_MISSING: %', name;
    END IF;
  END LOOP;
END
$gate86$;
