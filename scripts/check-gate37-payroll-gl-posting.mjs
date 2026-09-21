import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const paths = [
  "supabase/manual-packages/gate37_payroll_gl_posting.sql",
  "supabase/manual-packages/gate37_aoa_account_mapping.sql",
  "supabase/manual-packages/gate37_postcheck.sql",
  "supabase/manual-packages/gate37_payroll_posting_smoke_test_rollback.sql",
];
for (const path of paths) assert.ok(existsSync(path), `Gate 37 file is missing: ${path}`);

const sql = read(paths[0]);
const mapping = read(paths[1]);
const postcheck = read(paths[2]);
const smoke = read(paths[3]);
const service = read("src/lib/payroll/payroll-posting-service.ts");
const panel = read("src/components/payroll/payroll-accounting-panel.tsx");
const contract = read("src/lib/accounting/posting-contracts.ts");
const reports = read("src/lib/reporting/report-catalog.ts");
const runtime = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const architecture = read("docs/architecture/onexa-payroll-gl-posting.md");
const pkg = JSON.parse(read("package.json"));

assert.ok(sql.includes("public.onexa_payroll_posting_runs"), "posting-run table is missing");
assert.ok(sql.includes("alter table public.onexa_payroll_posting_runs enable row level security"), "RLS is missing");
assert.ok(sql.includes("security_invoker = true"), "views must use security_invoker");
assert.ok(sql.includes("pg_advisory_xact_lock"), "advisory lock is missing");
assert.ok(sql.includes("order by id for update"), "deterministic line locking is missing");
assert.ok(sql.includes("if found then return _journal_id"), "safe retry is missing");
assert.ok(sql.includes("ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR"), "separation of duties is missing");
assert.ok(sql.includes("ONEXA_PAYROLL_COST_LEDGER_MISMATCH"), "cost reconciliation is missing");
assert.ok(sql.includes("hr_payroll_attendance_is_stale"), "attendance guard is missing");
assert.ok(sql.includes("onexa_private.has_module_action(_actor, 'people', 'post')"), "posting authorization is missing");
assert.ok(sql.includes("_source_document_id => _run.id::text"), "B4 source adapter is missing");
assert.ok(sql.includes("posting_contract_version', 'payroll-v1"), "contract version is missing");
assert.ok(sql.includes("revoke all on function public.onexa_post_payroll_run(uuid, uuid, uuid, text) from public, anon"), "anon RPC access is not revoked");
assert.ok(!sql.includes("grant insert") && !sql.includes("grant update") && !sql.includes("grant delete"), "direct writes exposed");

for (const role of ["payroll_expense_or_project_cost", "employee_payables", "gosi_payable", "employee_loans_receivable"]) {
  assert.ok(sql.includes(`'${role}'`), `SQL role missing: ${role}`);
  assert.ok(mapping.includes(`'${role}'`), `mapping role missing: ${role}`);
  assert.ok(contract.includes(`accountRole: "${role}"`), `contract role missing: ${role}`);
}
for (const code of ["6100", "2140", "2170", "1170"]) assert.ok(mapping.includes(`'${code}'`), `account missing: ${code}`);
for (const marker of [
  "ONEXA_SMOKE_APPROVED_COST_SYNCED_PAYROLL_REQUIRED",
  "ONEXA_SMOKE_DISTINCT_FINANCE_POSTER_REQUIRED",
  "ONEXA_SMOKE_PAYROLL_RECONCILIATION_FAILED",
  "ONEXA_SMOKE_PAYROLL_RETRY_NOT_IDEMPOTENT",
  "rollback;",
]) assert.ok(smoke.includes(marker), `smoke-test invariant missing: ${marker}`);
assert.ok(!smoke.includes("commit;"), "smoke test must never commit");

assert.ok(postcheck.includes("authenticated direct insert/update/delete must remain false"), "postcheck privilege assertion missing");
assert.ok(service.includes('db.rpc("onexa_post_payroll_run"'), "service RPC missing");
assert.ok(service.includes('from("onexa_payroll_accounting_reconciliation")'), "reconciliation query missing");
assert.ok(panel.includes("الربط المحاسبي للرواتب") && panel.includes("reconciliation_status"), "accounting UI missing");
assert.ok(reports.includes('key: "payroll_accounting_reconciliation"'), "report catalog entry missing");
assert.ok(runtime.includes("ONEXA_PAYROLL_POSTING_ENABLED"), "runtime gate missing");
assert.ok(env.includes('VITE_ENABLE_ONEXA_PAYROLL_POSTING=""'), "runtime flag must default false");
for (const phrase of ["one PostgreSQL transaction", "project and department", "safe retry", "rollback smoke test"]) {
  assert.ok(architecture.includes(phrase), `architecture decision missing: ${phrase}`);
}
assert.equal(pkg.scripts["check:gate37-payroll-gl-posting"], "node scripts/check-gate37-payroll-gl-posting.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate37-payroll-gl-posting"), "Gate 37 missing from verify");

console.log("Gate 37 ONEXA payroll/GL posting checks passed ✓");
