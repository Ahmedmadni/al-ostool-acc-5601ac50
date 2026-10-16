BEGIN;

-- Legacy ops_* tables use a global group-company key, not ONEXA tenant_id.
DO $onexa_tenant_safety$
BEGIN
  IF to_regclass('public.onexa_tenants') IS NOT NULL THEN
    RAISE EXCEPTION 'ONEXA_GATE14_GLOBAL_OPERATIONS_SCHEMA_FORBIDDEN: tenant-native operations required';
  END IF;
END $onexa_tenant_safety$;

DO $
DECLARE
  v_found integer := 0;
  v_expected constant integer := 15;
BEGIN
  v_found := v_found + CASE WHEN to_regclass('public.ops_sites') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_sla_policies') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_assets') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_service_requests') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_work_orders') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_work_order_assignments') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_work_visits') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_work_order_materials') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_subcontract_costs') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_work_acceptances') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_preventive_plans') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_status_events') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_service_request_seq') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.ops_work_order_seq') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regprocedure('public.ops_create_service_request(uuid,uuid,uuid,text,text,text,uuid)') IS NOT NULL THEN 1 ELSE 0 END;

  IF v_found > 0 AND v_found < v_expected THEN
    RAISE EXCEPTION 'Gate 14 maintenance operations appears partially applied (%/% core markers found); stop and reconcile before retry', v_found, v_expected;
  END IF;
END $$;

COMMIT;
