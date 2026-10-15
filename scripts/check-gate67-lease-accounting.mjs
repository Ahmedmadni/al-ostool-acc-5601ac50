import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate67_lease_invoice_receipt_posting.sql");
const mapping = read("supabase/manual-packages/gate67_aoa_lease_account_mapping.sql");
const postcheck = read("supabase/manual-packages/gate67_postcheck.sql");
const smoke = read("supabase/manual-packages/gate67_lease_accounting_smoke_test_rollback.sql");
const service = read("src/lib/real-estate/lease-accounting-service.ts");
const panel = read("src/components/real-estate/onexa-lease-accounting-panel.tsx");
const flags = read("src/lib/runtime-flags.ts");
const queue = read("src/components/accounting/document-work-queue.tsx");
const route = read("src/routes/_authenticated/real-estate.tsx");

for (const pattern of [
  /onexa_lease_accounting_scopes/,
  /onexa_lease_invoice_postings/,
  /onexa_lease_receipt_postings/,
  /onexa_save_lease_accounting_scope\(/,
  /onexa_post_lease_invoice\(/,
  /onexa_post_lease_receipt\(/,
  /onexa_approval_separation_required/,
  /pg_advisory_xact_lock/,
  /for update/,
  /with \(security_invoker=true\)/,
  /enable row level security/,
]) assert.match(sql, pattern);

assert.match(mapping, /'4510'/);
assert.match(mapping, /'rental_revenue'/);
assert.match(postcheck, /direct_writes_denied/);
assert.match(postcheck, /anon_can_post_invoice/);
for (const marker of [
  "onexa_journal_headers invoice_journal",
  "onexa_journal_headers receipt_journal",
  "onexa_journal_headers posted_journal",
  "journal_reversed_or_missing",
  "invoice_journal_reversed_or_missing",
  "journal_source_or_amount_mismatch",
  "ONEXA_LEASE_INVOICE_JOURNAL_REVERSED_OR_MISSING",
  "ONEXA_LEASE_RECEIPT_JOURNAL_REVERSED_OR_MISSING",
  "ONEXA_LEASE_SCOPE_REASSIGNMENT_FORBIDDEN",
  "receipt_document.status='posted'",
  "receipt_journal.state='posted' and receipt_journal.reversal_journal_id is null",
  "posted_journal.state='posted'",
  "onexa_guard_approval_posting",
]) assert.ok(sql.includes(marker), `Missing lease GL integrity control: ${marker}`);
assert.match(sql, /public\.onexa_lease_accounting_scopes\.legal_entity_id=excluded\.legal_entity_id/);
assert.match(sql, /public\.onexa_lease_accounting_scopes\.branch_id=excluded\.branch_id/);
assert.match(sql, /public\.onexa_lease_accounting_scopes\.property_id=excluded\.property_id/);
assert.doesNotMatch(sql, /on conflict \(tenant_lease_id\) do update set tenant_id=excluded\.tenant_id/);
assert.match(postcheck, /tgenabled<>'D'/);
assert.match(postcheck, /journal_source_or_amount_mismatch/);
const panelSource = read("src/components/real-estate/onexa-lease-accounting-panel.tsx");
assert.match(panelSource, /date\.getFullYear\(\)/);
assert.doesNotMatch(panelSource, /new Date\(\)\.toISOString\(\)\.slice\(0, 10\)/);
assert.match(smoke, /onexa_post_lease_invoice/);
assert.match(smoke, /onexa_post_lease_receipt/);
assert.match(smoke, /rollback;/i);
assert.match(service, /documentType: "lease_invoice"/);
assert.match(service, /documentType: "lease_receipt"/);
assert.match(panel, /محاسبة عقود الإيجار والتحصيل/);
assert.match(flags, /ONEXA_LEASE_ACCOUNTING_ENABLED/);
assert.match(queue, /postOnexaLeaseInvoice/);
assert.match(queue, /postOnexaLeaseReceipt/);
assert.match(route, /OnexaLeaseAccountingPanel/);
console.log("Gate 67 lease invoice and receipt accounting checks passed");
