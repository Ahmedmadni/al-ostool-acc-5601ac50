import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sql = read("supabase/manual-packages/gate40_supplier_payments.sql");
const postcheck = read("supabase/manual-packages/gate40_postcheck.sql");
const smoke = read("supabase/manual-packages/gate40_payment_smoke_test_rollback.sql");
const mapping = read("supabase/manual-packages/gate40_aoa_account_mapping.sql");
const service = read("src/lib/procurement/supplier-payment-service.ts");
const panel = read("src/components/procurement/onexa-vendor-payments-panel.tsx");
const route = read("src/routes/_authenticated/vendors/payments.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "onexa_post_journal(", "onexa_supplier_payment_allocations",
  "ONEXA_PAYMENT_INVOICE_OVERPAYMENT", "ONEXA_PAYMENT_ALLOCATION_TOTAL_MISMATCH",
  "ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR", "pg_advisory_xact_lock",
  "for update", "security_invoker = true", "enable row level security",
  "onexa_private.claim_tenant_id()", "onexa.transition_authorized",
]) assert.ok(sql.includes(marker), `Missing payment control: ${marker}`);
assert.ok(sql.includes("_invoice.branch_id is distinct from _payment.branch_id"));
assert.ok(sql.includes("_invoice.party_type is distinct from 'vendor'"));
assert.ok(sql.includes("'account_code', _ap, 'debit', _payment.gross_total"));
assert.ok(sql.includes("'account_code', _cash, 'debit', 0"));
assert.ok(!/grant\s+(insert|update|delete)/i.test(sql), "Direct ledger writes exposed");
assert.ok(postcheck.includes("authenticated_direct_writes_denied"));
assert.ok(postcheck.includes("security_invoker"));
assert.ok(mapping.includes("ONEXA_GATE40_CASH_ACCOUNT_MAPPING_REQUIRED"));
assert.ok(smoke.includes("ONEXA_SMOKE_PAYMENT_RETRY_FAILED"));
assert.ok(smoke.includes("ONEXA_SMOKE_CROSS_TENANT_ALLOWED"));
assert.match(smoke.trim(), /rollback;$/);
assert.ok(!smoke.includes("commit;"));
assert.ok(service.includes("createBusinessDocument") && service.includes("onexa_post_supplier_payment"));
assert.ok(panel.includes("approveOnexaPayment") && route.includes("OnexaPaymentsPanel"));
assert.ok(flags.includes("ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED"));
assert.ok(env.includes('VITE_ENABLE_ONEXA_SUPPLIER_PAYMENT_POSTING=""'));
assert.ok(pkg.scripts.verify.includes("check:gate40-supplier-payments"));
console.log("Gate 40 supplier payments package checks passed");
