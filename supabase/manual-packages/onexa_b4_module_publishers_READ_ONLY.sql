-- ONEXA B4 source-module publisher/catalog inspection — STRICT SELECT ONLY.
-- Reads pg_catalog definitions, not journal/customer/ledger rows. Not a release
-- approval. Cross-check with GLOBAL B4 11-gate catalog and human staging UAT.
with expected(module_code,gate_code,rpc_name,source_codes) as (
  values
    ('sales_invoice','g35','onexa_post_sales_invoice',array['sales_invoice']::text[]),
    ('purchase_invoice','g36','onexa_post_purchase_invoice',array['purchase_invoice']::text[]),
    ('payroll_run','g37','onexa_post_payroll_run',array['payroll_run']::text[]),
    ('asset_depreciation','g38','onexa_post_asset_depreciation',array['depreciation_run']::text[]),
    ('customer_receipt','g39','onexa_post_customer_receipt',array['customer_receipt']::text[]),
    ('supplier_payment','g40','onexa_post_supplier_payment',array['supplier_payment']::text[]),
    ('bank_transfer','g41','onexa_post_bank_transfer',array['bank_transfer']::text[]),
    ('project_cost','g42','onexa_post_project_cost',array['project_cost']::text[]),
    ('fleet_trip_cost','g43','onexa_post_fleet_trip_cost',array['fleet_trip_cost']::text[]),
    ('inventory_document','g65','onexa_post_inventory_document',array['inventory_receipt','inventory_issue']::text[]),
    ('maintenance_work_order_cost','g66','onexa_post_maintenance_work_order_cost',array['maintenance_work_order_cost']::text[]),
    ('lease_invoice','g67','onexa_post_lease_invoice',array['lease_invoice']::text[]),
    ('lease_receipt','g67','onexa_post_lease_receipt',array['lease_receipt']::text[]),
    ('manual_journal','g58','onexa_post_manual_journal',array['manual_journal']::text[])
), constraint_def as (
  select pg_get_constraintdef(c.oid,true) def
  from pg_constraint c
  where c.conrelid=to_regclass('public.onexa_journal_headers')
    and c.conname='onexa_journal_headers_source_document_type_check'
    and c.contype='c'
), observed as (
  select e.module_code,e.gate_code,e.rpc_name,e.source_codes,
    count(p.oid)::integer as overload_count,
    coalesce(bool_or(p.oid is not null
      and has_function_privilege('authenticated',p.oid,'EXECUTE')),false)
      as authenticated_can_execute,
    coalesce(bool_or(pg_get_functiondef(p.oid) like '%public.onexa_post_journal(%'),false)
      as calls_public_b4,
    coalesce(bool_or(pg_get_functiondef(p.oid) like '%has_module_action%'),false)
      as has_module_authorization,
    coalesce(bool_or(pg_get_functiondef(p.oid) like '%ONEXA_POST_JOURNAL_INVALID_RESPONSE%'),false)
      as checks_nonnull_b4_result
  from expected e
  left join pg_proc p on p.pronamespace=to_regnamespace('public')
    and p.proname=e.rpc_name
  group by e.module_code,e.gate_code,e.rpc_name,e.source_codes
), checks as (
  select o.*,
    coalesce(
      (select bool_and(position(chr(39)||t.source_code||chr(39) in d.def)>0)
       from unnest(o.source_codes) t(source_code)
       cross join constraint_def d),
      false) as source_types_allowed
  from observed o
)
select module_code,gate_code,rpc_name,
  overload_count=1 as unique_rpc_installed,
  source_types_allowed,
  authenticated_can_execute,
  calls_public_b4,
  has_module_authorization,
  checks_nonnull_b4_result,
  case
    when overload_count=0 then 'MISSING_RPC'
    when overload_count<>1 then 'UNREVIEWED_OVERLOADS'
    when not source_types_allowed then 'SOURCE_TYPE_BLOCKED'
    when not authenticated_can_execute then 'AUTHENTICATED_EXECUTE_UNVERIFIED'
    when not calls_public_b4 then 'B4_PUBLISHER_PATH_UNVERIFIED'
    when not has_module_authorization then 'MODULE_PERMISSION_GATE_UNVERIFIED'
    when not checks_nonnull_b4_result then 'B4_RESPONSE_GUARD_UNVERIFIED'
    else 'SOURCE_PRESENT_ONLY_STAGING_REQUIRED'
  end as catalog_status
from checks order by gate_code,module_code;
