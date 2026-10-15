BEGIN;

DO $$
DECLARE
  v_found integer := 0;
  v_expected constant integer := 16;
BEGIN
  -- Gate 13–15 were originally designed around globally unique legacy
  -- group-company codes (RE/OM). Those codes cannot safely isolate multiple
  -- SaaS customers that share the ONEXA Customer Data Plane.
  -- Require independently partitioned group membership and ops-site scopes
  -- before any Gate 15 DDL on a tenant-aware ONEXA installation.
  IF to_regclass('public.onexa_tenants') IS NOT NULL AND (
    NOT EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='group_companies'
        AND column_name='tenant_id')
    OR NOT EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='group_user_module_access'
        AND column_name='tenant_id')
    OR NOT EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='ops_sites'
        AND column_name='tenant_id')
  ) THEN
    RAISE EXCEPTION 'ONEXA_GATE15_SAAS_TENANT_SCOPE_REQUIRED: global Gate 13/14 company records are not tenant partitioned';
  END IF;

  v_found := v_found + CASE WHEN to_regclass('public.re_properties') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_buildings') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_floors') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_units') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_master_leases') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_tenant_leases') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_lease_schedules') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_occupancy_events') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_facility_links') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_property_cost_links') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_status_events') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_master_lease_seq') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regclass('public.re_tenant_lease_seq') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regprocedure('public.re_create_property(text,text,text,text,text,numeric,numeric)') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regprocedure('public.re_create_tenant_lease(uuid,uuid,date,date,numeric,numeric,text)') IS NOT NULL THEN 1 ELSE 0 END;
  v_found := v_found + CASE WHEN to_regprocedure('public.re_portfolio_snapshot()') IS NOT NULL THEN 1 ELSE 0 END;

  IF v_found > 0 THEN
    RAISE EXCEPTION 'Gate 15 real estate and facilities already installed or appears partially applied (%/% core markers found); stop and reconcile before retry', v_found, v_expected;
  END IF;
END $$;

COMMIT;
