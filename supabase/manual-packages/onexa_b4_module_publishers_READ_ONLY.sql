-- ONEXA B4 financial module publisher coverage — READ ONLY.
-- Inspects only pg_catalog function DEFINITIONS and EXECUTE grants. No
-- financial tables or tenant/source records are accessed. Zero writes.
-- Evidence of an installed RPC is NEVER permission to activate a module.
with expected(module_code,gate_code,rpc_name) as (
  values
    ('sales_invoice','g35','onexa_post_sales_invoice'),
    ('purchase_invoice','g36','onexa_post_purchase_invoice'),
    ('payroll_run','g37','onexa_post_payroll_run'),
    ('asset_depreciation','g38','onexa_post_asset_depreciation'),
    ('customer_receipt','g39','onexa_post_customer_receipt'),
    ('supplier_payment','g40','onexa_post_supplier_payment'),
    ('bank_transfer','g41','onexa_post_bank_transfer'),
    ('project_cost','g42','onexa_post_project_cost'),
    ('fleet_trip_cost','g43','onexa_post_fleet_trip_cost'),
    ('inventory_document','g65','onexa_post_inventory_document'),
    ('maintenance_work_order_cost','g66','onexa_post_maintenance_work_order_cost'),
    ('lease_invoice','g67','onexa_post_lease_invoice'),
    ('lease_receipt','g67','onexa_post_lease_receipt'),
    ('manual_journal','g58','onexa_post_manual_journal')
), observed as (
  select e.module_code,e.gate_code,e.rpc_name,
    count(p.oid)::integer as overload_count,
    coalesce(bool_or(p.oid is not null
      and has_function_privilege('authenticated',p.oid,'EXECUTE')),false) as authenticated_can_execute,
    coalesce(bool_or(pg_get_functiondef(p.oid) like '%public.onexa_post_journal(%'),false) as calls_public_b4,
    coalesce(bool_or(pg_get_functiondef(p.oid) like '%has_module_action%'),false) as has_module_authorization,
    coalesce(bool_or(pg_get_functiondef(p.oid) like '%ONEXA_POST_JOURNAL_INVALID_RESPONSE%'),false) as checks_nonnull_b4_result
  from expected e
  left join pg_proc p on p.pronamespace=to_regnamespace('public')
    and p.proname=e.rpc_name
  group by e.module_code,e.gate_code,e.rpc_name
)
select module_code,gate_code,rpc_name,
  overload_count = 1 as unique_rpc_installed,
  authenticated_can_execute,
  calls_public_b4,
  has_module_authorization,
  checks_nonnull_b4_result,
  case
    when overload_count=0 then 'MISSING_RPC'
    when overload_count<>1 then 'UNREVIEWED_OVERLOADS'
    when not authenticated_can_execute then 'AUTHENTICATED_EXECUTE_UNVERIFIED'
    when not calls_public_b4 then 'B4_PUBLISHER_PATH_UNVERIFIED'
    when not has_module_authorization then 'MODULE_PERMISSION_GATE_UNVERIFIED'
    when not checks_nonnull_b4_result then 'B4_RESPONSE_GUARD_UNVERIFIED'
    else 'SOURCE_PRESENT_ONLY_STAGING_REQUIRED'
  end as catalog_status
from observed order by gate_code,module_code;
