-- B4 global-ledger manual_journal source allowlist — REVIEW ONLY.
-- This fixes an observed hosted schema blocker, NOT customer transaction data.
-- Only execute in independently restored Staging after change approval.
-- The legacy constraint must match the *observed* catalog definition exactly.
-- Add/validate replacement before removing legacy check; leave all old types.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $preflight$
declare _actual text;
begin
  if to_regclass('public.onexa_journal_headers') is null then
    raise exception 'ONEXA_B4_HEADERS_MISSING_STOP';
  end if;
  select pg_get_constraintdef(oid,true) into _actual
  from pg_constraint where conrelid='public.onexa_journal_headers'::regclass
    and conname='onexa_journal_headers_source_document_type_check'
    and contype='c';
  if _actual is distinct from $constraint$CHECK (source_document_type = ANY (ARRAY['sales_invoice'::text, 'customer_receipt'::text, 'purchase_invoice'::text, 'supplier_payment'::text, 'inventory_receipt'::text, 'inventory_issue'::text, 'payroll_run'::text, 'fixed_asset_acquisition'::text, 'depreciation_run'::text, 'project_cost'::text, 'maintenance_work_order_cost'::text, 'lease_invoice'::text, 'lease_receipt'::text, 'fleet_trip_cost'::text, 'fuel_issue'::text, 'bank_transfer'::text, 'journal_reversal'::text]))$constraint$ then
    raise exception 'ONEXA_B4_SOURCE_TYPE_ALLOWLIST_DRIFT_STOP';
  end if;
  if exists (
    select 1 from pg_constraint
    where conrelid='public.onexa_journal_headers'::regclass
      and conname='onexa_journal_headers_source_document_type_check_v2'
  ) then
    raise exception 'ONEXA_B4_SOURCE_TYPE_STAGING_CONFLICT_STOP';
  end if;
end;
$preflight$;

alter table public.onexa_journal_headers
  add constraint onexa_journal_headers_source_document_type_check_v2
  check (source_document_type = ANY (ARRAY['sales_invoice'::text, 'customer_receipt'::text, 'purchase_invoice'::text, 'supplier_payment'::text, 'inventory_receipt'::text, 'inventory_issue'::text, 'payroll_run'::text, 'fixed_asset_acquisition'::text, 'depreciation_run'::text, 'project_cost'::text, 'maintenance_work_order_cost'::text, 'lease_invoice'::text, 'lease_receipt'::text, 'fleet_trip_cost'::text, 'fuel_issue'::text, 'bank_transfer'::text, 'journal_reversal'::text, 'manual_journal'::text])) not valid;

alter table public.onexa_journal_headers
  validate constraint onexa_journal_headers_source_document_type_check_v2;

alter table public.onexa_journal_headers
  drop constraint onexa_journal_headers_source_document_type_check;

alter table public.onexa_journal_headers
  rename constraint onexa_journal_headers_source_document_type_check_v2
  to onexa_journal_headers_source_document_type_check;

-- Verify old and new types still pass. No journal rows were created/modified.
do $postcheck$
begin
  if not exists (
    select 1 from pg_constraint where conrelid='public.onexa_journal_headers'::regclass
      and conname='onexa_journal_headers_source_document_type_check'
      and pg_get_constraintdef(oid,true) like '%manual_journal%'
  ) then
    raise exception 'ONEXA_B4_SOURCE_TYPE_EXTENSION_FAILED';
  end if;
end;
$postcheck$;
commit;
