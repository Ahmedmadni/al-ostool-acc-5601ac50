-- Gate90: disposable PostgreSQL structural privilege contract, never production.
DO $g90$
DECLARE obj text; op text; fn text;
BEGIN
 IF current_database()<>'onexa_gate_test' THEN RAISE EXCEPTION 'G90_DISPOSABLE_ONLY'; END IF;
 FOREACH obj IN ARRAY ARRAY[
  'public.onexa_company_module_scopes',
  'public.onexa_operations_sites',
  'public.onexa_operations_assets',
  'public.onexa_operations_work_orders',
  'public.onexa_operations_work_order_events',
  'public.onexa_native_maintenance_cost_scopes',
  'public.onexa_native_maintenance_cost_attributions',
  'public.onexa_native_maintenance_unpaid_sources'
 ] LOOP
  IF to_regclass(obj) IS NULL THEN RAISE EXCEPTION 'G90_MISSING_RELATION: %',obj; END IF;
  FOREACH op IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege('anon',obj,op) THEN
    RAISE EXCEPTION 'G90_ANON_TABLE_PRIVILEGE: % %',obj,op;
   END IF;
  END LOOP;
  FOREACH op IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE'] LOOP
   IF has_table_privilege('authenticated',obj,op) THEN
    RAISE EXCEPTION 'G90_AUTHENTICATED_DIRECT_WRITE: % %',obj,op;
   END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated',obj,'SELECT') THEN
   RAISE EXCEPTION 'G90_AUTHENTICATED_READ_MISSING: %',obj;
  END IF;
 END LOOP;
 FOREACH fn IN ARRAY ARRAY[
  'public.onexa_create_operations_site(uuid,uuid,text,text)',
  'public.onexa_create_operations_asset(uuid,text,text,text)',
  'public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text)',
  'public.onexa_transition_operations_work_order(uuid,text,uuid,text)',
  'public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text)',
  'public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text)',
  'public.onexa_link_native_unpaid_maintenance_source(uuid,uuid)'
 ] LOOP
  IF to_regprocedure(fn) IS NULL THEN RAISE EXCEPTION 'G90_RPC_MISSING: %',fn; END IF;
  IF has_function_privilege('anon',fn,'EXECUTE') THEN
   RAISE EXCEPTION 'G90_ANON_RPC_EXECUTE: %',fn;
  END IF;
  IF NOT has_function_privilege('authenticated',fn,'EXECUTE') THEN
   RAISE EXCEPTION 'G90_AUTH_RPC_EXECUTE_MISSING: %',fn;
  END IF;
 END LOOP;
END $g90$;
