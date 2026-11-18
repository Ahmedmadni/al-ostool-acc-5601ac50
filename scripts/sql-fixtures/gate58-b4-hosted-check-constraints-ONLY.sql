-- Reproduce observed hosted B4 CHECK constraints on synthetic GL headers.
-- Disposable onexa_gate_test database ONLY. No hosted SQL execution.
do $preflight$
begin
 if current_database() <> 'onexa_gate_test'
   or to_regclass('public.fixture_module_grants') is null
   or to_regclass('public.onexa_journal_headers') is null then
   raise exception 'ONEXA_B4_SCHEMA_FIXTURE_DISPOSABLE_ONLY';
 end if;
end $preflight$;

alter table public.onexa_journal_headers
  add constraint onexa_journal_headers_source_document_type_check
  CHECK (source_document_type = ANY (ARRAY['sales_invoice'::text, 'customer_receipt'::text, 'purchase_invoice'::text, 'supplier_payment'::text, 'inventory_receipt'::text, 'inventory_issue'::text, 'payroll_run'::text, 'fixed_asset_acquisition'::text, 'depreciation_run'::text, 'project_cost'::text, 'maintenance_work_order_cost'::text, 'lease_invoice'::text, 'lease_receipt'::text, 'fleet_trip_cost'::text, 'fuel_issue'::text, 'bank_transfer'::text, 'journal_reversal'::text]));

alter table public.onexa_journal_headers
  add constraint onexa_journal_headers_check
  check (abs(total_debit - total_credit) <= 0.005);
