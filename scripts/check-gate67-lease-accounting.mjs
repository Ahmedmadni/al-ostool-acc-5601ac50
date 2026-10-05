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
