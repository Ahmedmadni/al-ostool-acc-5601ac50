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
const service = read("src/lib/accounting/manual-journal-service.ts");
const panel = read("src/components/accounting/manual-journal-panel.tsx");
const route = read("src/routes/_authenticated/financials/index.tsx");
const runtime = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const guide = read("supabase/manual-packages/README_AR.md");
const pkg = JSON.parse(read("package.json"));

for (const table of ["onexa_manual_journals","onexa_manual_journal_lines","onexa_manual_journal_events"]) {
  assert.ok(sql.includes(`public.${table}`), `manual journal table missing: ${table}`);
  assert.ok(sql.includes(`alter table public.${table} enable row level security`), `RLS missing: ${table}`);
}
for (const fn of ["onexa_create_manual_journal","onexa_transition_manual_journal","onexa_post_manual_journal","onexa_reverse_manual_journal"]) {
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
assert.ok(!sql.includes("grant insert") && !sql.includes("grant update") && !sql.includes("grant delete"), "manual journal tables must not expose direct writes");
assert.ok(sql.includes("_journal_id_result := public.onexa_post_journal("), "manual journal posting must use PostgreSQL-safe direct assignment");
assert.ok(sql.includes("_reversal_id := public.onexa_reverse_journal("), "manual journal reversal must use PostgreSQL-safe direct assignment");
assert.ok(!sql.includes("::uuid into _journal_id_result") && !sql.includes("::uuid into _reversal_id"), "legacy SELECT INTO assignment syntax must not return");
assert.ok(postcheck.includes("authenticated_can_execute") && postcheck.includes("anon_cannot_execute"), "Gate 58 postcheck is incomplete");
assert.ok(smoke.includes("ONEXA_SMOKE_DISTINCT_MANUAL_JOURNAL_POSTER_REQUIRED"), "distinct poster smoke check missing");
assert.ok(smoke.includes("ONEXA_SMOKE_MANUAL_JOURNAL_RETRY_FAILED"), "idempotency smoke check missing");
assert.ok(smoke.includes("rollback;") && !smoke.includes("commit;"), "manual journal smoke test must roll back");

for (const marker of ['db.rpc("onexa_create_manual_journal"', 'db.rpc("onexa_transition_manual_journal"', 'db.rpc("onexa_post_manual_journal"']) {
  assert.ok(service.includes(marker), `manual journal service missing: ${marker}`);
}
for (const marker of ["ONEXA_MANUAL_JOURNALS_ENABLED", "إضافة قيد يومية", "إجمالي المدين", "إجمالي الدائن", "اعتماد", "ترحيل"]) {
  assert.ok(panel.includes(marker), `manual journal UI missing: ${marker}`);
}
assert.ok(route.includes("<ManualJournalPanel />"), "manual journal panel is missing from accounting workspace");
assert.ok(runtime.includes("VITE_ENABLE_ONEXA_MANUAL_JOURNALS"), "manual journal runtime flag missing");
assert.ok(env.includes('VITE_ENABLE_ONEXA_MANUAL_JOURNALS=""'), "manual journal flag must default false");
assert.ok(guide.includes("Gate 58 — القيود اليومية اليدوية"), "Arabic rollout guide is missing Gate 58");

assert.equal(pkg.scripts["check:gate58-manual-journals"], "node scripts/check-gate58-manual-journals.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate58-manual-journals"), "Gate 58 is missing from verify");

console.log("Gate 58 governed manual journals checks passed ✓");
