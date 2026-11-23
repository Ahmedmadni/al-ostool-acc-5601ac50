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
assert.ok(sql.includes("ONEXA_PAYROLL_POSTING_RETRY_CONFLICT") &&
  sql.includes("return _existing.journal_id;") &&
  sql.includes("and h.source_snapshot = _expected_snapshot") &&
  sql.includes("and h.total_debit = _employer_cost") &&
  sql.includes("and h.state = 'posted'") &&
  sql.includes("= _journal_lines"),
  "Safe retry must compare source, tenant, currency, fiscal period, totals and ordered GL lines");
assert.ok(sql.includes("ONEXA_PAYROLL_TENANT_BOUNDARY_COLUMNS_REQUIRED") &&
  sql.includes("ONEXA_PAYROLL_SOURCE_TENANT_MISMATCH") &&
  sql.includes("ONEXA_PAYROLL_EMPLOYEE_TENANT_MISMATCH") &&
  sql.includes("ONEXA_PAYROLL_PROJECT_TENANT_MISMATCH") &&
  sql.includes("where id = _payroll_run_id and tenant_id = _tenant_id for update") &&
  sql.includes("and cost.tenant_id = _tenant_id") &&
  sql.includes("join public.hr_employees employee on employee.id = line.employee_id\n    where line.run_id = _payroll_run_id\n      and employee.tenant_id is distinct from _tenant_id") &&
  sql.includes("employee.id = line.employee_id and employee.tenant_id = _tenant_id\n    where line.run_id = _payroll_run_id and line.tenant_id = _tenant_id"),
  "Payroll source/employee/project, GL debit grouping and cost ledger must remain within claimant tenant");
assert.ok(sql.includes("_source_status => 'approved'") &&
  sql.includes("_run.status::text not in ('approved', 'paid')"),
  "B4 accepts approved source status even when payroll is already paid");
assert.ok(sql.includes("employer_cost = (net_pay + gosi_payable + loan_recovery)") &&
  sql.includes("_cost_ledger_amount <> _employer_cost") &&
  sql.includes("_employer_cost <> (_net_pay + _gosi_payable + _loan_recovery)") &&
  !sql.includes("<= 0.01") && !sql.includes("> 0.01"),
  "Payroll source/GL equation must be exact, without tolerated halala drift");
assert.ok(sql.includes("ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR"), "separation of duties is missing");
assert.ok(sql.includes("ONEXA_PAYROLL_COST_LEDGER_MISMATCH"), "cost reconciliation is missing");
assert.ok(sql.includes("left join public.hr_employees employee on employee.id = line.employee_id") &&
  sql.includes("employee.id is null or employee.tenant_id is distinct from _tenant_id"),
  "Missing employee rows and foreign-tenant employee rows must both block payroll GL");
assert.ok((sql.match(/cost.project_id is not distinct from line.project_id/g)??[]).length>=3,
  "Both UI reconciliation and posted payroll must match project attribution for cost entries");
assert.ok(sql.includes("ONEXA_PAYROLL_COST_LINE_MISMATCH") &&
  sql.includes("cost.amount is distinct from public.hr_payroll_employer_cost"),
  "Offsetting employee-cost errors cannot be concealed by a matching aggregate");

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

const b4PayrollContract = read("scripts/sql-fixtures/gate37-paid-payroll-b4-strict-smoke.sql");
const syntheticParents = read("scripts/sql-fixtures/gate37-hr-synthetic-parents-ONLY.sql");
const realB4Integration = read("scripts/sql-fixtures/gate37-real-b4-payroll-integration-smoke.sql");
const ledgerAudit = read("supabase/manual-packages/onexa_g37_payroll_contract_READ_ONLY.sql");
const financeB4Workflow = read(".github/workflows/onexa-b4-shared-ledger-integrity.yml");
for(const marker of [
  "G37_PAID_SOURCE_STATUS_WAS_ACCEPTED_BY_B4",
  "G37_APPROVED_CANONICAL_B4_PAYROLL_POST_FAILED",
  "G37_ONE_HALALA_IMBALANCED_B4_PAYROLL_ACCEPTED",
]) assert.ok(b4PayrollContract.includes(marker),
  "Strict B4 payroll API status/amount contract must be exercised: "+marker);
for(const marker of [
  "ONEXA_GATE37_HR_FIXTURE_DISPOSABLE_ONLY",
  "create table public.hr_payroll_runs(",
  "create table public.hr_payroll_lines(",
  "create table public.cost_entries(",
  "create function public.hr_payroll_attendance_is_stale(uuid)",
]) assert.ok(syntheticParents.includes(marker),
  "Real Gate37 integration must isolate fake HR foundation: "+marker);
for(const marker of [
  "G37_REAL_B4_E2E_DISPOSABLE_ONLY",
  "G37_CROSS_TENANT_PAYROLL_RUN_ACCEPTED",
  "G37_FOREIGN_TENANT_SOURCE_ACCEPTED",
  "G37_FOREIGN_TENANT_EMPLOYEE_ACCEPTED",
  "G37_FOREIGN_TENANT_PROJECT_ACCEPTED",
  "G37_FOREIGN_TENANT_COST_ACCEPTED",
  "G37_WRONG_PROJECT_COST_RECEIPT_ACCEPTED",
  "G37_OFFSETTING_COST_LINE_ERRORS_ACCEPTED",
  "G37_ONE_HALALA_COST_DRIFT_ACCEPTED",
  "G37_ONE_HALALA_ACCOUNTING_DRIFT_ACCEPTED",
  "G37_PAID_RUN_CANONICAL_B4_JOURNAL_NOT_POSTED",
  "G37_IDENTICAL_REPLAY_NOT_IDEMPOTENT",
  "G37_CONFLICTING_PERIOD_REPLAY_ACCEPTED",
  "G37_MUTATED_ORIGINAL_GL_LINE_ACCEPTED",
  "G37_MUTATED_SOURCE_SNAPSHOT_ACCEPTED",
  "G37_REVERSED_JOURNAL_REPLAY_ACCEPTED_AS_POSTED",
  "G37_REPLAY_CREATED_DUPLICATE_PAYROLL_LEDGER_OR_REGISTRY",
]) assert.ok(realB4Integration.includes(marker),
  "Real Gate37 + B4 integration test missing: "+marker);
assert.ok(b4PayrollContract.trimEnd().endsWith("rollback;") &&
  realB4Integration.trimEnd().endsWith("rollback;"),
  "Actual B4 and Gate37 transactional tests MUST rollback");
for(const marker of [
  "onexa_g37_payroll_contract_READ_ONLY.sql",
  "gate37-hr-synthetic-parents-ONLY.sql",
  "gate37-real-b4-payroll-integration-smoke.sql",
  "gate37-paid-payroll-b4-strict-smoke.sql",
]) assert.ok(financeB4Workflow.includes(marker) ||
  (marker === "onexa_g37_payroll_contract_READ_ONLY.sql" && ledgerAudit.includes("PAYROLL_RETRY_PAYLOAD_VERIFIED")),
  "Shared B4 CI must run complete Gate37 tests/audits: "+marker);
for(const marker of [
  "PAYROLL_CANONICAL_B4_APPROVED",
  "PAYROLL_TENANT_RUN_SCOPED",
  "PAYROLL_TENANT_COST_SCOPED",
  "PAYROLL_RETRY_LEDGER_LINES_VERIFIED",
  "PAYROLL_EXACT_FINANCIAL_EQUATION",
  "PAYROLL_EXACT_BALANCE_CONSTRAINT",
]) assert.ok(ledgerAudit.includes(marker),"Read-only Gate37 hosted readiness omitted "+marker);
const noComments=ledgerAudit.replace(/^--.*$/gm,"").replace(/'(?:''|[^'])*'/g,"''");
assert.match(noComments,/^\s*with\b/i);
assert.doesNotMatch(noComments,/\b(?:CREATE|ALTER|DELETE|UPDATE|INSERT|DROP|GRANT|REVOKE|EXECUTE|CALL|TRUNCATE|DO)\b/i);
assert.equal((noComments.match(/;/g)??[]).length,1,
  "Hosted Gate37 readiness audit must be one SELECT-only SQL statement");


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
