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
assert.ok(sql.includes("purchase_run.document_id = invoice.id"), "Gate 40 purchase posting alias is invalid");
assert.ok(!sql.includes("procurement.document_id"), "Gate 40 stale procurement alias remains");
assert.ok(sql.includes("account.category::text = 'assets'"), "Gate 40 cash account validation is missing");
assert.ok(sql.includes("account.category::text = 'liabilities'"), "Gate 40 AP account validation is missing");
// Correct liability balances require an actually posted, unreversed source.
assert.match(sql, /join public\.onexa_supplier_payment_postings posted_payment/);
assert.match(sql, /join public\.onexa_business_documents payment_document/);
assert.match(sql, /join public\.onexa_journal_headers payment_journal/);
assert.match(sql, /payment_document\.posted_journal_id = posted_payment\.journal_id/);
assert.match(sql, /payment_journal\.state = 'posted'/);
assert.match(sql, /payment_journal\.reversal_journal_id is null/);
assert.match(sql, /invoice_journal\.state = 'posted'/);
assert.match(sql, /invoice_journal\.reversal_journal_id is null/);
assert.match(sql, /ONEXA_PAYMENT_POSTED_JOURNAL_REVERSED_OR_MISSING/);
assert.match(sql, /ONEXA_PAYMENT_INVOICE_JOURNAL_REVERSED_OR_MISSING/);
assert.match(sql, /mapping\.id is null or account\.code is null/);
assert.match(sql, /roles\.account_role = 'accounts_payable' and account\.category::text = 'liabilities'/);
assert.match(sql, /roles\.account_role = 'cash_or_bank' and account\.category::text = 'assets'/);
assert.match(postcheck, /payment_allocation_source_integrity/);
assert.match(postcheck, /invalid_allocation_count/);
assert.match(postcheck, /payment_journal\.state = 'posted'/);
assert.match(postcheck, /invoice_journal_reversed_or_missing/);
assert.doesNotMatch(sql, /coalesce\(sum\(allocation\.amount\), 0\)::numeric\(20,4\) as paid_amount/,
  "Do not aggregate raw allocations as a posted payment balance");

assert.ok(postcheck.includes("workflow_pending_count"), "Gate 40 postcheck must separate workflow-pending invoices");
assert.ok(postcheck.includes("distinct_creator_and_operator"), "Gate 40 authorization readiness check is missing");
assert.match(postcheck.trim(), /rollback;$/, "Gate 40 postcheck diagnostics must roll back");
console.log("Gate 40 supplier payments package checks passed");
