import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sqlPath = "supabase/manual-packages/gate58_manual_journal_workflow.sql";
const postcheckPath = "supabase/manual-packages/gate58_postcheck.sql";
const smokePath = "supabase/manual-packages/gate58_manual_journal_smoke_test_rollback.sql";
for (const path of [sqlPath, postcheckPath, smokePath]) assert.ok(existsSync(path), `Gate 58 file missing: ${path}`);

const sql = read(sqlPath);
const postcheck = read(postcheckPath);
const smoke = read(smokePath);
const liveAudit = read("supabase/manual-packages/gate58_live_compatibility_readonly.sql");
const reviewPatch = read("supabase/manual-packages/gate58_create_validation_patch_REVIEW_ONLY.sql");
const viewReviewPatch = read("supabase/manual-packages/gate58_reconciliation_exact_patch_REVIEW_ONLY.sql");
const lifecyclePatch = read("supabase/manual-packages/gate58_lifecycle_authorization_patch_REVIEW_ONLY.sql");
const balancePatch = read("supabase/manual-packages/gate58_exact_balance_constraint_patch_REVIEW_ONLY.sql");
const amendmentPatch = read("supabase/manual-packages/gate58_amendment_REVIEW_ONLY.sql");
const amendSmoke = read("scripts/sql-fixtures/gate58-amendment-smoke.sql");
const g58Smoke = read("scripts/sql-fixtures/gate58-real-manual-journal-smoke.sql");
const g58Adapter = read("scripts/sql-fixtures/gate58-disposable-b4-adapter.sql");
const g58Workflow = read(".github/workflows/onexa-manual-journal-real-sql.yml");
const realB4Workflow = read(".github/workflows/onexa-manual-journal-real-b4.yml");
const realB4Snapshot = read("scripts/sql-fixtures/gate58-b4-catalog-snapshot-20261118.sql");
const realB4Parents = read("scripts/sql-fixtures/gate58-b4-real-parents-ONLY.sql");
const realB4Smoke = read("scripts/sql-fixtures/gate58-real-b4-post-reverse-smoke.sql");
const badB4Smoke = read("scripts/sql-fixtures/gate58-b4-invalid-receipt-smoke.sql");
const b4LiveAudit = read("supabase/manual-packages/gate58_b4_live_contract_readonly.sql");
const b4PostPatch = read("supabase/manual-packages/gate58_b4_post_contract_REVIEW_ONLY.sql");
const b4PrivateGrantPatch = read("supabase/manual-packages/gate58_b4_private_grants_REVIEW_ONLY.sql");
const b4PrivateGrantSmoke = read("scripts/sql-fixtures/gate58-b4-private-grant-smoke.sql");
const b4FoundationWorkflow = read(".github/workflows/onexa-b4-shared-ledger-integrity.yml");
const b4StrictReview = read("supabase/manual-packages/gate58_b4_strict_monetary_REVIEW_ONLY.sql");
const b4StrictFixture = read("scripts/sql-fixtures/gate58-b4-strict-monetary-fixture.sql");
const b4SourceTypeReview = read("supabase/manual-packages/gate58_b4_gl_source_type_REVIEW_ONLY.sql");
const b4HeaderBalanceReview = read("supabase/manual-packages/gate58_b4_gl_exact_balance_REVIEW_ONLY.sql");
const b4LegacyConstraints = read("scripts/sql-fixtures/gate58-b4-hosted-check-constraints-ONLY.sql");
const b4LegacyProbe = read("scripts/sql-fixtures/gate58-b4-hosted-baseline-defects-smoke.sql");
const b4StrictSmoke = read("scripts/sql-fixtures/gate58-b4-strict-cross-module-smoke.sql");
const b4IdempotencyLegacy = read("scripts/sql-fixtures/gate58-b4-idempotency-legacy-smoke.sql");
const b4IdempotencyStrict = read("scripts/sql-fixtures/gate58-b4-idempotency-strict-smoke.sql");
const b4IdempotencyConcurrency = read("scripts/sql-fixtures/gate58-b4-idempotency-concurrency.sh");

const service = read("src/lib/accounting/manual-journal-service.ts");
const panel = read("src/components/accounting/manual-journal-panel.tsx");
const journalValidation = read("src/lib/accounting/manual-journal-validation.ts");
const route = read("src/routes/_authenticated/financials/index.tsx");
const runtime = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const guide = read("supabase/manual-packages/README_AR.md");
const pkg = JSON.parse(read("package.json"));

for (const table of ["onexa_manual_journals","onexa_manual_journal_lines","onexa_manual_journal_events"]) {
  assert.ok(sql.includes(`public.${table}`), `manual journal table missing: ${table}`);
  assert.ok(sql.includes(`alter table public.${table} enable row level security`), `RLS missing: ${table}`);
}
for (const fn of ["onexa_create_manual_journal","onexa_amend_manual_journal","onexa_transition_manual_journal","onexa_post_manual_journal","onexa_reverse_manual_journal"]) {
  assert.ok(sql.includes(`function public.${fn}`), `manual journal function missing: ${fn}`);
  assert.ok(sql.includes(`grant execute on function public.${fn}`), `authenticated grant missing: ${fn}`);
}
for (const invariant of [
  "ONEXA_MANUAL_JOURNAL_NOT_BALANCED",
  "ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_APPROVE",
  "ONEXA_MANUAL_JOURNAL_POSTER_MUST_DIFFER_FROM_CREATOR",
  "pg_advisory_xact_lock",
  "onexa_post_journal",
  "onexa_reverse_journal",
  "security_invoker = true",
  "manual-journal-v1",
]) assert.ok(sql.includes(invariant), `manual journal invariant missing: ${invariant}`);
assert.ok(sql.includes("or debit is null or credit is null"), "missing debit or credit must be explicitly rejected before aggregation");
assert.ok(sql.includes("_period_code <> to_char(_accounting_date, 'YYYY-MM')"), "Manual journal SQL must require accounting-date period consistency");
assert.ok(sql.includes("debit <> round(debit, 4) or credit <> round(credit, 4)"), "Gate58 must reject storage-rounding of monetary source lines");
assert.ok(sql.includes("debit <> round(debit, 2) or credit <> round(credit, 2)"), "Gate58 must reject fractional halalas for SAR");
assert.ok(sql.includes("_total_debit <> _total_credit"), "Gate58 must require exact debit-credit equality");
assert.ok(!sql.includes("abs(_total_debit - _total_credit) > 0.005"), "Gate58 must not allow an unbalanced journal within tolerance");
for (const required of [
  "constraint onexa_manual_journals_balanced check (total_debit = total_credit)",
  "_to_status in ('approved','rejected') then 'approve'",
  "ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_REJECT",
  "ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_CANCEL",
  "ONEXA_MANUAL_JOURNAL_CANCELLATION_REASON_REQUIRED",
  "ONEXA_MANUAL_JOURNAL_REVERSAL_PERIOD_INVALID",
]) assert.ok(sql.includes(required), `Gate58 lifecycle invariant missing: ${required}`);
assert.ok(sql.includes("ONEXA_MANUAL_JOURNAL_REJECTED_MUST_BE_AMENDED"), "Rejected journal must require an audited edit before reopening");
assert.ok(g58Smoke.includes("G58_REJECTED_REOPEN_WITHOUT_AMEND_ALLOWED"), "Legacy rejected-to-draft bypass must have a denial test");
assert.ok(amendSmoke.includes("'costCenter','COST-7'"), "Cost centre dimensions must survive audited journal corrections");
assert.ok(service.includes("dimensions") && panel.includes("...lines[index].dimensions"), "Client correction must preserve prior project dimensions");
assert.ok(panel.includes('onClick={() => openForm(false)}'), "Cancelling an edit must clear stale revision context");
assert.ok(panel.includes("ONEXA_MANUAL_JOURNAL_REVISION_CONFLICT"), "Client must explain stale edit denial");
assert.ok(!sql.includes("constraint onexa_manual_journals_balanced check (abs(total_debit - total_credit) <= 0.005)"), "Gate58 fresh installs must enforce exact header balance");

const transitionStart = "create or replace function public.onexa_transition_manual_journal(";
const transitionEnd = "create or replace function public.onexa_post_manual_journal(";
const reverseStart = "create or replace function public.onexa_reverse_manual_journal(";
const reverseEnd = "create or replace view public.onexa_manual_journal_reconciliation";
function assertGuardedSqlBody(start, end, patch, patchEnd) {
  const begin = sql.indexOf(start), finish = sql.indexOf(end, begin + start.length);
  const patchBegin = patch.indexOf(start), patchFinish = patch.indexOf(patchEnd, patchBegin + start.length);
  assert.ok(begin >= 0 && finish > begin && patchBegin >= 0 && patchFinish > patchBegin, "Guarded patch function boundaries missing");
  assert.equal(patch.slice(patchBegin, patchFinish).trim(), sql.slice(begin, finish).trim(), "Guarded lifecycle patch must match authoritative SQL source");
}
assertGuardedSqlBody(transitionStart, transitionEnd, lifecyclePatch, reverseStart);
assertGuardedSqlBody(reverseStart, reverseEnd, lifecyclePatch, "-- Existing grants, RLS policies");
for (const gate of [
  "ONEXA_GATE58_TRANSITION_DRIFT_STOP_REVIEW_REQUIRED",
  "ONEXA_GATE58_REVERSAL_DRIFT_STOP_REVIEW_REQUIRED",
]) assert.ok(lifecyclePatch.includes(gate), `Lifecycle patch drift gate missing: ${gate}`);
for (const gate of [
  "ONEXA_GATE58_BALANCE_CONSTRAINT_DRIFT_STOP_REVIEW_REQUIRED",
  "ONEXA_GATE58_HISTORICAL_UNBALANCED_ROWS_STOP_FINANCE_REVIEW_REQUIRED",
  "check (total_debit = total_credit)",
  "lock_timeout",
]) assert.ok(balancePatch.includes(gate), `Balance patch safeguard missing: ${gate}`);
for (const test of [
  "G58_UNBALANCED_HEADER_CONSTRAINT_ALLOWED",
  "G58_CREATOR_REJECTION_ALLOWED",
  "G58_UNAUTHORIZED_REVIEWER_REJECTION_ALLOWED",
  "G58_OTHER_CREATOR_CANCELLATION_ALLOWED",
  "G58_SUBMITTED_CANCEL_NO_REASON_ALLOWED",
  "G58_REVIEW_REJECTION_AUDIT_FAILED",
  "G58_CREATOR_CANCEL_WITH_REASON_FAILED",
  "G58_REVERSAL_PERIOD_MISMATCH_ALLOWED",
  "G58_NULL_REVERSAL_DATE_ALLOWED",
]) assert.ok(g58Smoke.includes(test), `Gate58 database lifecycle negative test missing: ${test}`);

assert.ok(sql.includes("manual.total_debit is distinct from header.total_debit"), "Gate58 reconciliation must compare debit exactly");
assert.ok(sql.includes("manual.total_credit is distinct from header.total_credit"), "Gate58 reconciliation must compare credit exactly");
assert.ok(!sql.includes("abs(manual.total_debit - coalesce(header.total_debit, 0)) > 0.005"), "Gate58 reconciliation must not hide sub-cent ledger differences");
const viewStart = "create or replace view public.onexa_manual_journal_reconciliation";
const viewEnd = "revoke all on table public.onexa_manual_journal_sequences";
const viewSqlStart = sql.indexOf(viewStart);
const viewSqlEnd = sql.indexOf(viewEnd, viewSqlStart);
const viewPatchStart = viewReviewPatch.indexOf(viewStart);
const viewPatchEnd = viewReviewPatch.indexOf("-- CREATE OR REPLACE preserves existing grants;");
assert.ok(viewSqlStart >= 0 && viewSqlEnd > viewSqlStart && viewPatchStart >= 0 && viewPatchEnd > viewPatchStart, "Gate58 reconciliation-view boundaries missing");
assert.equal(viewReviewPatch.slice(viewPatchStart, viewPatchEnd).trim(), sql.slice(viewSqlStart, viewSqlEnd).trim(), "Review-only view patch must match authoritative SQL exactly");
assert.ok(viewReviewPatch.includes("ONEXA_G58_VIEW_DEFINITION_DRIFT_STOP_REVIEW_REQUIRED"), "View review patch must prevent stale replacement");
assert.ok(viewReviewPatch.includes("security_invoker=true"), "Review-only view patch must preserve RLS invoker security");
assert.ok(g58Smoke.includes("G58_SUB_TOLERANCE_RECONCILIATION_ACCEPTED"), "Sub-cent reconciliation negative test missing");
for (const negative of [
  "G58_NONEXISTENT_REVERSAL_RECONCILED",
  "G58_WRONG_REVERSAL_LINK_RECONCILED",
  "G58_REVERSAL_AMOUNT_VARIANCE_RECONCILED",
]) assert.ok(g58Smoke.includes(negative), `Gate58 reversal check missing: ${negative}`);
assert.ok(sql.includes("reversal.reversal_of_id is distinct from manual.posted_journal_id"), "Reversal reconciliation must validate original-journal link");
assert.ok(sql.includes("reversal.total_debit is distinct from header.total_credit"), "Reversal reconciliation must verify contra debit");
assert.ok(sql.includes("reversal.total_credit is distinct from header.total_debit"), "Reversal reconciliation must verify contra credit");


assert.ok(reviewPatch.includes("ONEXA_GATE58_LIVE_FUNCTION_DRIFT_STOP_REVIEW_REQUIRED"), "Review-only production function patch must stop on drift");
assert.ok(reviewPatch.includes("_period_code <> to_char(_accounting_date, 'YYYY-MM')"), "Review patch must include date-period guard");
const fnStart = "create or replace function public.onexa_create_manual_journal(";
const fnEnd = "create or replace function public.onexa_amend_manual_journal(";
const rpcStart = sql.indexOf(fnStart);
// Stop at the end of the CREATE function itself: comments introducing the
// next amendment RPC are not part of the create function's deployable body.
const rpcEndMarker = "\n$function$;";
const rpcEnd = sql.indexOf(rpcEndMarker, rpcStart) + rpcEndMarker.length;
const patchStart = reviewPatch.indexOf(fnStart);
const patchEnd = reviewPatch.indexOf("-- Do not change function grants here.");
assert.ok(rpcStart >= 0 && rpcEnd > rpcStart && sql.indexOf(fnEnd, rpcStart) > rpcEnd && patchStart >= 0 && patchEnd > patchStart, "Gate58 patch-function boundaries missing");
assert.equal(
  reviewPatch.slice(patchStart, patchEnd).trim(),
  sql.slice(rpcStart, rpcEnd).trim(),
  "Guarded review-only patch must exactly mirror authoritative Gate58 RPC",
);
for (const marker of [
  "G58_SUB_TOLERANCE_IMBALANCE_ACCEPTED",
  "G58_EXCESS_STORAGE_PRECISION_ACCEPTED",
  "G58_FRACTIONAL_HALALA_ACCEPTED",
]) assert.ok(g58Smoke.includes(marker), `Gate58 financial precision negative test missing: ${marker}`);

assert.ok(g58Smoke.includes("G58_PERIOD_MISMATCH_ACCEPTED") && g58Smoke.includes("G58_CROSS_TENANT_RLS_LEAK"), "Disposable G58 real-RPC negative tests are incomplete");
assert.ok(g58Adapter.includes("SYNTHETIC DISPOSABLE") && g58Adapter.includes("onexa_reverse_journal"), "G58 B4 test double missing");
assert.ok(g58Workflow.includes("real-g58-manual-journal-smoke:") && g58Workflow.includes("gate58-real-manual-journal-smoke.sql"), "G58 real SQL smoke is not wired to its isolated CI workflow");
assert.ok(liveAudit.includes("pg_get_functiondef") && liveAudit.includes("pg_policies"), "Live catalog inspection is incomplete");
assert.ok(g58Workflow.includes("gate58-amendment-smoke.sql"), "Real amendment SQL test must execute in disposable PostgreSQL CI");

assert.ok(g58Workflow.includes("gate58-b4-invalid-receipt-smoke.sql"), "B4 fail-closed negative smoke must run in CI");
for (const marker of [
  "ONEXA_MANUAL_JOURNAL_B4_POST_CONTRACT_MISMATCH",
  "ONEXA_MANUAL_JOURNAL_B4_REVERSAL_CONTRACT_MISMATCH",
  "posted.source_revision = _journal.revision",
  "posted.source_document_id = _journal.id::text",
  "posted.total_debit = _journal.total_debit",
  "posted.total_credit = _journal.total_credit",
  "reversed.reversal_of_id = original.id",
  "original.reversal_journal_id = reversed.id",
]) assert.ok(sql.includes(marker), `Gate58 must verify actual B4 receipt contract: ${marker}`);
for (const marker of [
  "G58_INVALID_B4_POST_RECEIPT_ACCEPTED",
  "G58_INVALID_B4_POST_WAS_NOT_ATOMIC",
  "G58_INVALID_B4_REVERSAL_RECEIPT_ACCEPTED",
  "G58_INVALID_B4_REVERSAL_NOT_ATOMIC",
]) assert.ok(badB4Smoke.includes(marker), `Bad B4 receipt regression missing: ${marker}`);
assert.ok((badB4Smoke.match(/rollback;/g) ?? []).length === 2, "Both malicious B4 fixture transactions must roll back");
assert.ok(realB4Workflow.includes("postgres:16") && realB4Workflow.includes("gate58-b4-catalog-snapshot-20261118.sql"), "Isolated actual B4 SQL CI is missing");
assert.ok(realB4Workflow.includes("gate58-b4-real-parents-ONLY.sql") && realB4Workflow.includes("gate58-real-b4-post-reverse-smoke.sql"), "Actual B4 CI needs real functional acceptance");
assert.ok(!realB4Workflow.includes("gate58-disposable-b4-adapter.sql"), "Real B4 job must never use a mock GL engine");
assert.ok(realB4Parents.includes("ONEXA_B4_DISPOSABLE_PARENT_REQUIRED") && realB4Parents.includes("onexa_fiscal_periods"), "Actual B4 harness must be synthetic and gated");
for (const marker of [
  "-- onexa_private.post_journal: pg_get_functiondef MD5 5ac58a780bbed49e8ba31b6f46c39f48",
  "-- onexa_private.reverse_journal: pg_get_functiondef MD5 f51a890027057a0e838c13cbfd6ddb61",
  "-- public.onexa_post_journal: pg_get_functiondef MD5 0f8adeaf5c85cd470f1c1a29b6545376",
  "-- public.onexa_reverse_journal: pg_get_functiondef MD5 ac77042a26c0c954a7f26402a583f52e",
  "-- public.onexa_post_journal_unchecked: pg_get_functiondef MD5 51db95c8878a9ff78db87cc1cef7ae3d",
  "-- public.onexa_reverse_journal_unchecked: pg_get_functiondef MD5 9f9b4798858ca441280c07de774769f4",
  "p.status = 'open'",
  "onexa_posting_registry",
  "abs(v_debit - v_credit) > 0.005",
]) assert.ok(realB4Snapshot.includes(marker), `Actual deployed B4 catalog snapshot marker missing: ${marker}`);
for (const marker of [
  "G58_REAL_B4_POSTING_CONTRACT_FAILED",
  "G58_REAL_B4_CLOSED_PERIOD_POST_ALLOWED",
  "G58_REAL_B4_PERIOD_REJECTION_NOT_ATOMIC",
  "G58_REAL_B4_CLOSED_PERIOD_REVERSE_ALLOWED",
  "G58_REAL_B4_REVERSE_DENIAL_NOT_ATOMIC",
  "G58_REAL_B4_REVERSAL_CONTRACT_FAILED",
  "G58_REAL_B4_CROSS_TENANT_POST_ALLOWED",
]) assert.ok(realB4Smoke.includes(marker), `Actual B4 closed-period acceptance case missing: ${marker}`);
assert.ok(realB4Smoke.trimEnd().endsWith("rollback;"), "Actual B4 synthetic integration must roll back");
assert.ok(b4LiveAudit.includes("pg_get_functiondef") && b4LiveAudit.includes("matches_verified_snapshot"), "Read-only real B4 catalog fingerprint checks missing");
const b4AuditExecutable = b4LiveAudit.replace(/^--.*$/gm, "").replace(/'(?:''|[^'])*'/g, "''");
assert.doesNotMatch(b4AuditExecutable, /\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|DO|EXECUTE)\b/i, "B4 catalog audit must remain SELECT-only");
const postFunctionStart = "create or replace function public.onexa_post_manual_journal(";
const postFunctionEnd = "create or replace function public.onexa_reverse_manual_journal(";
const postSourceStart = sql.indexOf(postFunctionStart);
const postSourceEnd = sql.indexOf(postFunctionEnd, postSourceStart);
const postPatchStart = b4PostPatch.indexOf(postFunctionStart);
const postPatchEnd = b4PostPatch.indexOf("-- This replacement preserves the existing EXECUTE grants.", postPatchStart);
assert.ok(postSourceStart >= 0 && postSourceEnd > postSourceStart && postPatchStart >= 0 && postPatchEnd > postPatchStart, "Guarded B4 posting patch function bounds missing");
assert.equal(
  b4PostPatch.slice(postPatchStart, postPatchEnd).trim(),
  sql.slice(postSourceStart, postSourceEnd).trim(),
  "Review-only GL posting receipt patch must exactly mirror authoritative Gate58 source",
);
assert.ok(b4PostPatch.includes("ONEXA_GATE58_B4_POST_RPC_DRIFT_STOP_REVIEW_REQUIRED"), "B4 posting patch needs hosted function fingerprint precondition");
for (const marker of [
  "ONEXA_B4_PRIVATE_GRANT_DEFINITION_DRIFT_STOP",
  "ONEXA_B4_PRIVATE_GRANT_EXPECTED_MATRIX_CHANGED_STOP",
  "ONEXA_B4_UNCHECKED_RPC_PERMISSION_DRIFT_STOP",
  "ONEXA_B4_PRIVATE_GRANT_POSTCHECK_FAILED",
  "from authenticated;",
]) assert.ok(b4PrivateGrantPatch.includes(marker), `B4 direct-grant review patch missing: ${marker}`);
for (const marker of [
  "ONEXA_B4_PRIVATE_DIRECT_EXECUTE_STILL_GRANTED",
  "ONEXA_B4_PUBLIC_CHECKED_RPC_INACCESSIBLE",
  "ONEXA_B4_RESTRICTED_PRIVATE_GRANTS_BREAK_APPROVED_FLOW",
  "set local role authenticated;",
  "rollback;",
]) assert.ok(b4PrivateGrantSmoke.includes(marker), `B4 privilege regression missing: ${marker}`);
assert.ok(realB4Workflow.includes("gate58-b4-private-grant-smoke.sql"), "Real B4 CI must exercise restricted internal permissions");

const coreFunctionStart="CREATE OR REPLACE FUNCTION onexa_private.post_journal(";
const endCore="\n$function$;";
function extractCoreFunction(source) {
  const i=source.indexOf(coreFunctionStart);
  const j=source.indexOf(endCore,i+coreFunctionStart.length);
  assert.ok(i>=0 && j>i, "B4 strict function boundaries required");
  return source.slice(i,j+endCore.length).trim();
}
assert.equal(extractCoreFunction(b4StrictReview),extractCoreFunction(b4StrictFixture),
  "Strict B4 reviewed shared publisher must exactly match the isolated test version");
assert.ok(b4LiveAudit.includes("MANUAL_JOURNAL_BLOCKED") &&
  b4LiveAudit.includes("EXACT_BALANCE") &&
  b4LiveAudit.includes("pg_get_constraintdef"),
  "Read-only B4 hosted contract audit must surface the actual ledger constraints");
assert.ok(b4StrictReview.includes("ONEXA_B4_SHARED_PUBLISHER_DRIFT_STOP_REVIEW_REQUIRED"),
  "B4 core patch cannot silently overwrite an unknown deployed function");
assert.ok(b4StrictReview.includes("5ac58a780bbed49e8ba31b6f46c39f48"),
  "The review patch must preflight exactly the observed B4 function version");
assert.ok(!extractCoreFunction(b4StrictFixture).includes("abs(v_debit - v_credit) > 0.005"),
  "Strict publisher may not hide small currency imbalances");
for(const marker of [
 "v_debit numeric;","v_credit numeric;",
 "v_debit <> v_credit",
 "ONEXA_B4_LINE_INVALID",
 "ONEXA_B4_STORAGE_PRECISION_INVALID",
 "ONEXA_B4_SAR_HALALA_PRECISION_INVALID",
 "jsonb_typeof(x->'debit') is distinct from 'number'",
 "jsonb_typeof(x->'credit') is distinct from 'number'",
 "ONEXA_B4_SOURCE_ID_REQUIRED",
]) assert.ok(b4StrictFixture.includes(marker),`B4 strict monetary invariant missing: ${marker}`);
assert.ok(b4LegacyConstraints.includes("source_document_type = ANY") &&
 b4LegacyConstraints.includes("abs(total_debit - total_credit) <= 0.005") &&
 !b4LegacyConstraints.includes("'manual_journal'::text"),
 "Disposable baseline must reproduce actual hosted source-type omission and balance tolerance");
for(const marker of [
 "ONEXA_B4_SOURCE_TYPE_ALLOWLIST_DRIFT_STOP",
 "onexa_journal_headers_source_document_type_check_v2",
 "'manual_journal'::text",
 "validate constraint",
]) assert.ok(b4SourceTypeReview.includes(marker),`Manual journal allowlist review gate missing: ${marker}`);
for(const marker of [
 "ONEXA_B4_HEADER_BALANCE_CONSTRAINT_DRIFT_STOP",
 "ONEXA_B4_HISTORICAL_IMBALANCE_REQUIRES_FINANCE_REVIEW",
 "check (total_debit = total_credit) not valid",
 "validate constraint",
]) assert.ok(b4HeaderBalanceReview.includes(marker),`Exact GL header guard missing: ${marker}`);
for(const marker of [
 "G58_B4_BASELINE_MANUAL_TYPE_UNEXPECTEDLY_ALLOWED",
 "BASELINE_IMBALANCE_CONFIRMED",
 "BASELINE_ROUNDING_CONFIRMED",
 "BASELINE_MISSING_SIDE_CONFIRMED",
 "G58_B4_BASELINE_PROBES_LEFT_LEDGER_DATA",
]) assert.ok(b4LegacyProbe.includes(marker),`Real B4 baseline defect regression missing: ${marker}`);
for(const marker of [
 "G58_B4_STRICT_SOURCE_COVERAGE_INCOMPLETE",
 "G58_B4_STRICT_IMBALANCE_ACCEPTED",
 "G58_B4_STRICT_STORAGE_ROUNDING_ACCEPTED",
 "G58_B4_STRICT_FRACTIONAL_HALALA_ACCEPTED",
 "G58_B4_STRICT_MISSING_DEBIT_ACCEPTED",
 "G58_B4_STRICT_NULL_AMOUNT_ACCEPTED",
 "G58_B4_STRICT_NULL_APPROVAL_ACCEPTED",
 "G58_B4_STRICT_NULL_REVISION_ACCEPTED",
 "G58_B4_STRICT_KWD_3_DECIMAL_REGRESSION",
]) assert.ok(b4StrictSmoke.includes(marker),`B4 strict cross-module regression missing: ${marker}`);
for(const marker of [
 "postgres:16",
 "gate58-b4-catalog-snapshot-20261118.sql",
 "gate58-b4-hosted-check-constraints-ONLY.sql",
 "gate58-b4-hosted-baseline-defects-smoke.sql",
 "gate58_b4_gl_source_type_REVIEW_ONLY.sql",
 "gate58_b4_gl_exact_balance_REVIEW_ONLY.sql",
 "gate58-b4-strict-monetary-fixture.sql",
 "gate58-b4-strict-cross-module-smoke.sql",
]) assert.ok(b4FoundationWorkflow.includes(marker),`B4 GL foundation CI missing: ${marker}`);
assert.ok(!b4FoundationWorkflow.includes("gate58-disposable-b4-adapter.sql"),
  "B4 shared-ledger acceptance must not fake the actual B4 publisher");

for (const invariant of [
  "ONEXA_B4_POSTING_PAYLOAD_CONFLICT",
  "h.source_snapshot = coalesce(_source_snapshot, '{}'::jsonb)",
  "h.memo is not distinct from _memo",
  "h.fiscal_period_id = v_period_id",
  "h.total_debit = v_debit",
  "h.total_credit = v_credit",
  "h.state in ('posted', 'reversed')",
  "r.idempotency_key = v_key",
  "l.tenant_id = v_tenant_id",
  "order by l.line_number",
  "order by ordinality",
  "'dimensions', coalesce(x->'dimensions', '{}'::jsonb)",
  "'description', nullif(x->>'description', '')",
]) assert.ok(b4StrictReview.includes(invariant), `B4 source-identity payload guard missing: ${invariant}`);
assert.ok(b4IdempotencyLegacy.includes("B4_LEGACY_IDEMPOTENCY_BUG_NOT_REPRODUCED") &&
  b4IdempotencyLegacy.includes("LEGACY-IDEMPOTENCY-01"),
  "Idempotency baseline test must prove identical key accepts different approved content");
for (const denial of [
  "B4_CHANGED_PAYLOAD_WAS_ACCEPTED",
  "B4_CORRUPTED_GL_RECEIPT_ACCEPTED",
  "B4_CORRUPTED_LEDGER_LINE_ACCEPTED",
  "B4_IDENTICAL_RETRY_MUST_RETURN_SAME_LEDGER_ID",
  "B4_SEMANTICALLY_IDENTICAL_NUMERIC_RETRY_REJECTED",
  "B4_REVERSED_ORIGINAL_RETRY_DUPLICATED",
  "B4_IDEMPOTENCY_CONFLICT_CREATED_DUPLICATE_GL_OR_AUDIT",
]) assert.ok(b4IdempotencyStrict.includes(denial), `B4 retry acceptance missing: ${denial}`);
for (const concurrency of [
  "ONEXA_B4_POSTING_PAYLOAD_CONFLICT",
  "pg_locks",
  "pg_sleep(3)",
  "1|1|2|1",
  "onexa_gate_test",
]) assert.ok(b4IdempotencyConcurrency.includes(concurrency), `B4 concurrency regression missing: ${concurrency}`);
for (const path of [
  "gate58-b4-idempotency-legacy-smoke.sql",
  "gate58-b4-idempotency-strict-smoke.sql",
  "gate58-b4-idempotency-concurrency.sh",
]) assert.ok(b4FoundationWorkflow.includes(path), `Disposable B4 workflow must execute: ${path}`);
assert.ok(b4IdempotencyLegacy.trimEnd().endsWith("rollback;") &&
 b4IdempotencyStrict.trimEnd().endsWith("rollback;"),
 "Same-key duplicate SQL tests must rollback all synthetic ledger entries");
assert.ok(b4LiveAudit.includes("private_post_checks_retry_payload") &&
  b4LiveAudit.includes("private_post_compares_full_ledger_receipt"),
  "Hosted catalog must surface whether the shared B4 guard has been activated");

assert.ok(b4StrictSmoke.trimEnd().endsWith("rollback;") &&
 b4LegacyProbe.trimEnd().endsWith("rollback;"),
 "B4 financial acceptance tests must rollback every synthetic posting");

assert.ok(b4LiveAudit.includes("authenticated_can_execute_private_post") &&
  b4LiveAudit.includes("authenticated_can_execute_private_reverse") &&
  b4LiveAudit.includes("authenticated_can_execute_unchecked_post"),
  "Read-only B4 audit must expose public versus internal grant difference");


assert.ok(sql.includes("for update;") && sql.includes("ONEXA_MANUAL_JOURNAL_REVISION_CONFLICT"), "Amendment must lock and enforce optimistic revision");
for (const marker of [
  "ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_AMEND",
  "ONEXA_MANUAL_JOURNAL_AMEND_STATUS_INVALID",
  "ONEXA_MANUAL_JOURNAL_NOT_BALANCED",
  "'previous_revision', _journal.revision",
  "'new_revision', _new_revision",
  "'before', jsonb_build_object",
  "'after', jsonb_build_object",
  "event_type,",
  "'amended', _journal.status, 'draft', _actor",
]) assert.ok(sql.includes(marker), `Amendment SQL audit/authorization missing: ${marker}`);
const amendmentStart = "create or replace function public.onexa_amend_manual_journal(";
const amendmentEnd = "create or replace function public.onexa_transition_manual_journal(";
const amendStartInSql = sql.indexOf(amendmentStart);
const amendEndInSql = sql.indexOf(amendmentEnd, amendStartInSql);
const amendStartInPatch = amendmentPatch.indexOf(amendmentStart);
const amendEndInPatch = amendmentPatch.indexOf("revoke all on function public.onexa_amend_manual_journal", amendStartInPatch);
assert.ok(amendStartInSql >= 0 && amendEndInSql > amendStartInSql && amendStartInPatch >= 0 && amendEndInPatch > amendStartInPatch, "Amendment patch and source boundaries required");
assert.equal(
  amendmentPatch.slice(amendStartInPatch, amendEndInPatch).trim(),
  sql.slice(amendStartInSql, amendEndInSql).trim(),
  "Review-only amendment patch must equal authoritative new function",
);
for (const marker of [
  "ONEXA_GATE58_CREATE_RPC_NOT_HARDENED_STOP",
  "ONEXA_GATE58_REVIEWER_PERMISSIONS_NOT_HARDENED_STOP",
  "ONEXA_GATE58_EXACT_BALANCE_CONSTRAINT_REQUIRED",
  "ONEXA_GATE58_AMENDMENT_ALREADY_EXISTS_STOP_REVIEW_REQUIRED",
]) assert.ok(amendmentPatch.includes(marker), `Amendment review-only gate missing: ${marker}`);
for (const marker of [
  "G58_AMEND_DRAFT_UPDATE_FAILED",
  "G58_AMEND_AUDIT_SNAPSHOTS_MISSING",
  "G58_STALE_AMEND_ALLOWED",
  "G58_UNBALANCED_AMEND_ALLOWED",
  "G58_FRACTIONAL_HALALA_AMEND_ALLOWED",
  "G58_NULL_SIDE_AMEND_ALLOWED",
  "G58_DIFFERENT_MAKER_AMEND_ALLOWED",
  "G58_CROSS_TENANT_AMEND_ALLOWED",
  "G58_SUBMITTED_AMEND_ALLOWED",
  "G58_REJECTED_AMEND_REVISION_OR_HISTORY_FAILED",
  "G58_AMENDED_REPOST_LEDGER_REVISION_FAILED",
  "G58_POSTED_AMEND_ALLOWED",
]) assert.ok(amendSmoke.includes(marker), `Amendment executable negative test missing: ${marker}`);
assert.ok(amendSmoke.includes("rollback;") && !amendSmoke.includes("commit;"), "Amendment smoke must be rollback-only");
const liveAuditExecutable = liveAudit.replace(/^--.*$/gm, "");
// Quoted catalog role/privilege arguments such as 'EXECUTE' are data, not SQL statements.
const liveAuditStatements = liveAuditExecutable.replace(/'(?:''|[^'])*'/g, "''");
assert.doesNotMatch(liveAuditStatements, /\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|DO|EXECUTE)\b/i, "G58 live audit must remain SELECT-only");
assert.ok(!sql.includes("grant insert") && !sql.includes("grant update") && !sql.includes("grant delete"), "manual journal tables must not expose direct writes");
assert.ok(sql.includes("_journal_id_result := public.onexa_post_journal("), "manual journal posting must use PostgreSQL-safe direct assignment");
assert.ok(sql.includes("_reversal_id := public.onexa_reverse_journal("), "manual journal reversal must use PostgreSQL-safe direct assignment");
assert.ok(!sql.includes("::uuid into _journal_id_result") && !sql.includes("::uuid into _reversal_id"), "legacy SELECT INTO assignment syntax must not return");
assert.ok(postcheck.includes("authenticated_can_execute") && postcheck.includes("anon_cannot_execute"), "Gate 58 postcheck is incomplete");
for (const marker of [
  "_manual_journal := public.onexa_create_manual_journal(",
  "_to_status => 'submitted'",
  "_to_status => 'approved'",
  "ONEXA_SMOKE_CREATOR_APPROVAL_ALLOWED",
  "ONEXA_SMOKE_DISTINCT_AUTHORIZED_APPROVER_AND_POSTER_REQUIRED",
  "ONEXA_SMOKE_MANUAL_JOURNAL_RETRY_FAILED",
  "ONEXA_SMOKE_MANUAL_JOURNAL_CROSS_TENANT_ALLOWED",
]) assert.ok(smoke.includes(marker), `manual journal end-to-end smoke check missing: ${marker}`);
assert.ok(smoke.includes("rollback;") && !smoke.includes("commit;"), "manual journal smoke test must roll back");

for (const marker of ['db.rpc("onexa_create_manual_journal"', 'db.rpc("onexa_amend_manual_journal"', 'db.rpc("onexa_transition_manual_journal"', 'db.rpc("onexa_post_manual_journal"']) {
  assert.ok(service.includes(marker), `manual journal service missing: ${marker}`);
}
for (const marker of ["ONEXA_MANUAL_JOURNALS_ENABLED", "إضافة قيد يومية", "إجمالي المدين", "إجمالي الدائن", "اعتماد", "ترحيل"]) {
  assert.ok(panel.includes(marker), `manual journal UI missing: ${marker}`);
}
assert.ok(journalValidation.includes("evaluateManualJournalDraft") && journalValidation.includes("BigInt"), "exact-decimal journal input validation is missing");
assert.ok(panel.includes("validation.normalizedLines") && panel.includes('action: "submitted"'), "journal UI must use strict validated lines and allow draft resubmission");
for (const marker of ["loadEditableManualJournal", "amendManualJournal", "تصحيح القيد المرفوض", "سبب الرفض السابق", "expectedRevision", "disabled={Boolean(editTarget)}"]) {
  assert.ok(panel.includes(marker), `Amendment UI flow missing: ${marker}`);
}
assert.ok(route.includes("<ManualJournalPanel />"), "manual journal panel is missing from accounting workspace");
assert.ok(runtime.includes("VITE_ENABLE_ONEXA_MANUAL_JOURNALS"), "manual journal runtime flag missing");
assert.ok(env.includes('VITE_ENABLE_ONEXA_MANUAL_JOURNALS=""'), "manual journal flag must default false");
assert.ok(guide.includes("Gate 58 — القيود اليومية اليدوية"), "Arabic rollout guide is missing Gate 58");

assert.equal(pkg.scripts["check:gate58-manual-journals"], "node scripts/check-gate58-manual-journals.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate58-manual-journals"), "Gate 58 is missing from verify");
assert.equal(pkg.scripts["test:manual-journal-validation"], "node scripts/test-manual-journal-validation.mjs");
assert.ok(pkg.scripts.verify.includes("test:manual-journal-validation"), "journal decimal test is missing from verify");

console.log("Gate 58 governed manual journals checks passed ✓");
