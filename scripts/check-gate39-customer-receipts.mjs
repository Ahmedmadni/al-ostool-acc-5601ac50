import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sql = read("supabase/manual-packages/gate39_customer_receipts.sql");
const postcheck = read("supabase/manual-packages/gate39_postcheck.sql");
const smoke = read("supabase/manual-packages/gate39_receipt_smoke_test_rollback.sql");
const mapping = read("supabase/manual-packages/gate39_aoa_account_mapping.sql");
const service = read("src/lib/sales/customer-receipt-service.ts");
const panel = read("src/components/collections/onexa-receipts-panel.tsx");
const route = read("src/routes/_authenticated/customers/collections.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "onexa_post_journal(", "onexa_customer_receipt_allocations",
  "ONEXA_RECEIPT_INVOICE_OVERPAYMENT", "ONEXA_RECEIPT_ALLOCATION_TOTAL_MISMATCH",
  "ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR", "pg_advisory_xact_lock",
  "for update", "security_invoker = true", "enable row level security",
  "onexa_private.claim_tenant_id()", "onexa.transition_authorized",
]) assert.ok(sql.includes(marker), `Missing receipt control: ${marker}`);
assert.ok(sql.includes("_invoice.branch_id is distinct from _receipt.branch_id"));
assert.ok(sql.includes("_invoice.party_type is distinct from 'customer'"));
assert.ok(!/grant\s+(insert|update|delete)/i.test(sql), "Direct ledger writes exposed");
assert.ok(postcheck.includes("authenticated_direct_writes_denied"));
assert.ok(postcheck.includes("security_invoker"));
assert.ok(mapping.includes("ONEXA_GATE39_CASH_ACCOUNT_SELECTION_REQUIRED"));
assert.ok(mapping.includes("ONEXA_GATE39_AR_MAPPING_INVALID"));
assert.ok(!mapping.includes("account_code = '1120'"), "Gate 39 must honor the active AR role mapping instead of hardcoding an account");
for (const marker of [
  "onexa_create_business_document(",
  "onexa_transition_business_document(",
  "onexa_post_sales_invoice(",
  "onexa_inventory_balances",
  "ONEXA_SMOKE_SALES_INVOICE_CREATION_FAILED",
  "ONEXA_SMOKE_SALES_INVOICE_POSTING_FAILED",
  "ONEXA_SMOKE_RECEIPT_CREATOR_APPROVAL_ALLOWED",
  "ONEXA_SMOKE_RECEIPT_RETRY_FAILED",
  "gate39_customer_receipt_smoke_test",
]) assert.ok(smoke.includes(marker), "Missing self-contained receipt smoke control: " + marker);
assert.ok(smoke.includes("ONEXA_SMOKE_CROSS_TENANT_ALLOWED"));
assert.match(smoke, /rollback;[\s\S]*gate39_customer_receipt_smoke_test[\s\S]*passed/);
assert.ok(!smoke.includes("commit;"));
assert.ok(service.includes("createBusinessDocument") && service.includes("onexa_post_customer_receipt"));
assert.ok(panel.includes("approveOnexaReceipt") && route.includes("OnexaReceiptsPanel"));
assert.ok(flags.includes("ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED"));
assert.ok(env.includes('VITE_ENABLE_ONEXA_CUSTOMER_RECEIPT_POSTING=""'));
assert.ok(pkg.scripts.verify.includes("check:gate39-customer-receipts"));
console.log("Gate 39 customer receipts package checks passed");
