import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sqlPath = "supabase/manual-packages/gate36_procurement_inventory_posting.sql";
const mappingPath = "supabase/manual-packages/gate36_aoa_account_mapping.sql";
const postcheckPath = "supabase/manual-packages/gate36_postcheck.sql";
const smokePath = "supabase/manual-packages/gate36_purchase_posting_smoke_test_rollback.sql";
for (const path of [sqlPath, mappingPath, postcheckPath, smokePath]) {
  assert.ok(existsSync(path), `Gate 36 file is missing: ${path}`);
}

const sql = read(sqlPath);
assert.equal((sql.match(/\\bcommit\\s*;/gi) ?? []).length, 1, "Gate 36 migration must contain one transaction commit");
assert.match(sql.trim(), /commit;$/, "Gate 36 migration must end immediately after commit");
const mapping = read(mappingPath);
const postcheck = read(postcheckPath);
const smoke = read(smokePath);
const service = read("src/lib/procurement/purchase-posting-service.ts");
const contract = read("src/lib/accounting/posting-contracts.ts");
const route = read("src/routes/_authenticated/vendors/reports.tsx");
const reports = read("src/lib/reporting/report-catalog.ts");
const runtime = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const architecture = read("docs/architecture/onexa-procurement-inventory-posting.md");
const pkg = JSON.parse(read("package.json"));

assert.ok(sql.includes("public.onexa_purchase_posting_runs"), "purchase posting-run table is missing");
assert.ok(sql.includes("alter table public.onexa_purchase_posting_runs enable row level security"), "posting-run RLS is missing");
assert.ok(sql.includes("security_invoker = true"), "Gate 36 views must use security_invoker");
assert.ok(sql.includes("pg_advisory_xact_lock"), "atomic posting advisory lock is missing");
assert.ok(sql.includes("for update"), "row locking is missing");
assert.ok(sql.includes("order by warehouse_id nulls last, item_id nulls last, line_number"), "inventory lock order is not deterministic");
assert.ok(sql.includes("ONEXA_PURCHASE_RETRY_JOURNAL_MISMATCH") && sql.includes("return _journal_id"), "safe posting retry is missing");
assert.ok(sql.includes("ONEXA_PURCHASE_LINE_CLASSIFICATION_INVALID"), "line classification validation is missing");
assert.ok(sql.includes("ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR"), "creator/poster separation is missing");
assert.ok(sql.includes("onexa_private.has_module_action(_actor, 'procurement', 'post')"), "server-side procurement posting authorization is missing");
assert.ok(sql.includes("public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)"), "B4 journal signature check is missing");
assert.ok(sql.includes("_source_document_id => _document.id::text"), "B4 source-document adapter is missing");
assert.ok(sql.includes("posting_contract_version', 'procurement-v1"), "posting contract version is missing");
assert.ok(sql.includes("revoke all on function public.onexa_post_purchase_invoice(uuid, text) from public, anon"), "anonymous function execution is not revoked");
assert.ok(!sql.includes("grant insert") && !sql.includes("grant update") && !sql.includes("grant delete"), "operational tables must not expose direct writes");

for (const role of ["accounts_payable", "input_vat", "inventory", "purchase_expense", "fixed_asset_cost"]) {
  assert.ok(sql.includes(`'${role}'`), `purchase account role missing in SQL: ${role}`);
  assert.ok(mapping.includes(`'${role}'`), `AOA mapping missing role: ${role}`);
  assert.ok(contract.includes(`accountRole: "${role}"`), `posting contract missing role: ${role}`);
}
for (const code of ["2110", "1160", "1130", "5100", "1210"]) {
  assert.ok(mapping.includes(`'${code}'`), `AOA purchase account missing: ${code}`);
}

for (const marker of [
  "ONEXA_SMOKE_DISTINCT_FINANCE_POSTER_REQUIRED",
  "ONEXA_SMOKE_STOCK_BALANCE_MISMATCH",
  "ONEXA_SMOKE_EXPECTED_ONE_PURCHASE_RECEIPT",
  "ONEXA_SMOKE_PURCHASE_POSTING_RUN_MISMATCH",
  "ONEXA_SMOKE_PURCHASE_RECONCILIATION_FAILED",
  "rollback;",
]) assert.ok(smoke.includes(marker), `Gate 36 smoke-test invariant missing: ${marker}`);
assert.ok(!smoke.includes("commit;"), "Gate 36 smoke test must never commit test data");

assert.ok(postcheck.includes("authenticated direct insert/update/delete must remain false"), "postcheck privilege assertion is missing");
assert.ok(service.includes('db.rpc("onexa_post_purchase_invoice"'), "procurement service does not use the posting RPC");
assert.ok(service.includes('from("onexa_purchase_inventory_reconciliation")'), "procurement reconciliation service is missing");
assert.ok(route.includes("Purchases, Inventory & GL Reconciliation") && route.includes("reconciliation_status"), "procurement reconciliation UI is missing");
assert.ok(reports.includes('key: "purchase_reconciliation"'), "purchase reconciliation report is missing");
assert.ok(runtime.includes("ONEXA_PROCUREMENT_POSTING_ENABLED"), "procurement runtime gate is missing");
assert.ok(env.includes('VITE_ENABLE_ONEXA_PROCUREMENT_POSTING=""'), "procurement runtime flag must default false");

for (const phrase of ["one PostgreSQL transaction", "explicit accounting classification", "safe retry", "rollback smoke test"]) {
  assert.ok(architecture.includes(phrase), `Gate 36 architecture decision missing: ${phrase}`);
}

assert.equal(pkg.scripts["check:gate36-procurement-inventory-posting"], "node scripts/check-gate36-procurement-inventory-posting.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate36-procurement-inventory-posting"), "Gate 36 is missing from verify");

assert.ok(sql.includes("ONEXA_PURCHASE_RETRY_JOURNAL_MISMATCH"), "Gate 36 retry consistency check is missing");
assert.ok(sql.includes("!~ '^[0-9]{4}-(0[1-9]|1[0-2])$'"), "Gate 36 strict period validation is missing");
assert.ok(postcheck.includes("to_regclass"), "Gate 36 postcheck must resolve objects safely");
assert.ok(postcheck.includes("workflow_pending_count"), "Gate 36 postcheck must separate workflow-pending documents");
assert.match(postcheck.trim(), /rollback;$/, "Gate 36 postcheck diagnostics must roll back");
console.log("Gate 36 ONEXA procurement/inventory posting checks passed ✓");
