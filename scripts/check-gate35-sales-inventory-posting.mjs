import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sqlPath = "supabase/manual-packages/gate35_sales_inventory_posting.sql";
const aoaMappingPath = "supabase/manual-packages/gate35_aoa_account_mapping.sql";
const smokeTestPath = "supabase/manual-packages/gate35_sales_posting_smoke_test_rollback.sql";
assert.ok(existsSync(sqlPath), "Gate 35 SQL package is missing");
assert.ok(existsSync(aoaMappingPath), "Gate 35 AOA account mapping package is missing");
assert.ok(existsSync(smokeTestPath), "Gate 35 rollback smoke test is missing");
assert.ok(existsSync("supabase/manual-packages/00_onexa_gate34_35_preflight.sql"), "Gate 34/35 preflight is missing");
assert.ok(existsSync("supabase/manual-packages/03_onexa_gate34_35_postcheck.sql"), "Gate 34/35 postcheck is missing");
assert.ok(existsSync("supabase/manual-packages/README_AR.md"), "Arabic manual execution guide is missing");

const sql = read(sqlPath);
const aoaMapping = read(aoaMappingPath);
const smokeTest = read(smokeTestPath);
const preflight = read("supabase/manual-packages/00_onexa_gate34_35_preflight.sql");
const postcheck = read("supabase/manual-packages/03_onexa_gate34_35_postcheck.sql");
const service = read("src/lib/sales/sales-posting-service.ts");
const contract = read("src/lib/accounting/posting-contracts.ts");
const reports = read("src/lib/reporting/report-catalog.ts");
const runtime = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const route = read("src/routes/_authenticated/customers/reports.tsx");
const architecture = read("docs/architecture/onexa-sales-inventory-posting.md");
const pkg = JSON.parse(read("package.json"));

for (const table of ["onexa_inventory_balances", "onexa_inventory_movements", "onexa_sales_posting_runs"]) {
  assert.ok(sql.includes(`public.${table}`), `missing Gate 35 table: ${table}`);
  assert.ok(sql.includes(`alter table public.${table} enable row level security`), `RLS missing: ${table}`);
}
assert.ok(sql.includes("public.onexa_account_role_mappings"), "Gate 35 must reuse the installed B4 account-role mapping table");
assert.ok(!sql.includes("public.onexa_posting_account_roles"), "Gate 35 must not create a duplicate account-role mapping table");

for (const invariant of [
  "ONEXA_B4_POST_JOURNAL_SIGNATURE_REQUIRED", "pg_advisory_xact_lock", "for update",
  "ONEXA_INSUFFICIENT_STOCK", "weighted", "onexa_post_journal", "onexa.transition_authorized",
  "security_invoker = true", "ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR",
  "ONEXA_SALES_INVOICE_LINE_TOTALS_MISMATCH", "posting_contract_version', 'sales-v1",
]) assert.ok(sql.toLowerCase().includes(invariant.toLowerCase()), `posting invariant missing: ${invariant}`);

assert.ok(sql.includes("order by warehouse_id, item_id, line_number"), "inventory locks are not deterministic");
assert.ok(sql.includes("return _document.posted_journal_id"), "safe posting retry is missing");
assert.ok(sql.includes("ONEXA_B3_MODULE_AUTHORIZATION_REQUIRED"), "Gate 35 must require B3 authorization");
assert.ok(sql.includes("ONEXA_SALES_POST_NOT_AUTHORIZED"), "sales posting must enforce module authorization");
assert.ok(sql.includes("revoke all on function public.onexa_post_sales_invoice(uuid, text) from public, anon"), "sales posting must reject public and anonymous execution");
assert.ok(sql.includes("grant execute on function public.onexa_post_sales_invoice(uuid, text) to authenticated"), "authorized users must be able to invoke the guarded sales posting boundary");
assert.ok(!sql.includes("grant insert") && !sql.includes("grant update") && !sql.includes("grant delete"), "operational tables must not expose direct writes");
assert.ok(preflight.includes("signature_mismatch_or_missing") && preflight.includes("information_schema.columns"), "preflight does not fail closed on dependency drift");
assert.ok(
  sql.includes("public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)"),
  "Gate 35 must require the installed B4 journal signature",
);
assert.ok(
  sql.includes("_source_document_id => _document.id::text"),
  "Gate 35 must adapt the document UUID to B4's text source-document contract",
);
assert.ok(!preflight.match(/\b(insert|update|delete|alter|create|drop|truncate)\b(?![^-]*--)/i), "preflight must remain read-only");
assert.ok(postcheck.includes("security_invoker") && postcheck.includes("authenticated_can_execute"), "postcheck does not verify view/function security");

for (const role of ["accounts_receivable", "sales_revenue", "output_vat", "cost_of_goods_sold", "inventory"]) {
  assert.ok(sql.includes(`'${role}'`), `sales account role missing: ${role}`);
  assert.ok(contract.includes(`accountRole: "${role}"`), `posting contract role missing: ${role}`);
  assert.ok(aoaMapping.includes(`'${role}'`), `AOA mapping role missing: ${role}`);
}

for (const marker of [
  "ONEXA_AOA_ACCOUNT_CODE_USED_BY_ANOTHER_TENANT",
  "ONEXA_AOA_EXPECTED_FIVE_VALID_POSTING_ACCOUNTS",
  "ONEXA_AOA_EXPECTED_FIVE_VALID_ACCOUNT_MAPPINGS",
  "ONEXA_AOA_SALES_POSTING_CONFIGURATION_GAPS_REMAIN",
  "'request.jwt.claims'",
  "on conflict (legal_entity_id, account_role)",
]) assert.ok(aoaMapping.includes(marker), `AOA account mapping invariant missing: ${marker}`);

for (const accountCode of ["1120", "1130", "2160", "4500", "5600"]) {
  assert.ok(aoaMapping.includes(`'${accountCode}'`), `AOA posting account missing: ${accountCode}`);
}

for (const marker of [
  "ONEXA_SMOKE_DISTINCT_FINANCE_POSTER_REQUIRED",
  "ONEXA_SMOKE_DOCUMENT_NOT_POSTED_CORRECTLY",
  "ONEXA_SMOKE_STOCK_BALANCE_MISMATCH",
  "ONEXA_SMOKE_EXPECTED_ONE_INVENTORY_MOVEMENT",
  "ONEXA_SMOKE_SALES_POSTING_RUN_MISMATCH",
  "ONEXA_SMOKE_RECONCILIATION_FAILED",
  "rollback;",
]) assert.ok(smokeTest.includes(marker), `Gate 35 smoke-test invariant missing: ${marker}`);

assert.ok(!smokeTest.includes("commit;"), "Gate 35 smoke test must never commit test data");

assert.ok(service.includes('db.rpc("onexa_post_sales_invoice"'), "sales service does not use the atomic posting RPC");
assert.ok(service.includes('from("onexa_sales_inventory_reconciliation")'), "sales reconciliation service is missing");
assert.ok(runtime.includes("ONEXA_SALES_POSTING_ENABLED"), "sales posting runtime gate is missing");
assert.ok(env.includes('VITE_ENABLE_ONEXA_SALES_POSTING=""'), "sales posting flag must default to false");
assert.ok(reports.includes('key: "sales_margin"'), "sales margin report is missing");
assert.ok(route.includes("Sales, Inventory & GL Reconciliation") && route.includes("reconciliation_status"), "sales reconciliation UI is missing");

for (const phrase of ["one PostgreSQL transaction", "moving weighted average", "safe retry", "Production execution remains blocked until B2 and B3 pass"]) {
  assert.ok(architecture.includes(phrase), `Gate 35 architecture decision missing: ${phrase}`);
}

assert.equal(pkg.scripts["check:gate35-sales-inventory-posting"], "node scripts/check-gate35-sales-inventory-posting.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate35-sales-inventory-posting"), "Gate 35 is missing from verify");

console.log("Gate 35 ONEXA sales/inventory posting checks passed ✓");
