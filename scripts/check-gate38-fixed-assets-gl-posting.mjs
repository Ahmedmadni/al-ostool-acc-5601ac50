import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const paths = [
  "supabase/manual-packages/gate38_fixed_assets_gl_posting.sql",
  "supabase/manual-packages/gate38_aoa_account_mapping.sql",
  "supabase/manual-packages/gate38_postcheck.sql",
  "supabase/manual-packages/gate38_asset_depreciation_smoke_test_rollback.sql",
];
for (const path of paths) {
  assert.ok(existsSync(path), `Gate 38 file is missing: ${path}`);
}

const sql = read(paths[0]);
const mapping = read(paths[1]);
const postcheck = read(paths[2]);
const smoke = read(paths[3]);
const service = read("src/lib/assets/asset-posting-service.ts");
const panel = read("src/components/assets/asset-accounting-panel.tsx");
const route = read("src/routes/_authenticated/fixed-assets/index.tsx");
const reports = read("src/lib/reporting/report-catalog.ts");
const runtime = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const architecture = read("docs/architecture/onexa-fixed-assets-gl-posting.md");
const pkg = JSON.parse(read("package.json"));

assert.ok(
  sql.includes("public.onexa_asset_depreciation_postings"),
  "depreciation posting ledger is missing",
);
assert.ok(
  sql.includes("alter table public.onexa_asset_depreciation_postings enable row level security"),
  "posting RLS is missing",
);
assert.ok(sql.includes("security_invoker = true"), "views must use security_invoker");
assert.ok(sql.includes("pg_advisory_xact_lock"), "period/asset advisory lock is missing");
assert.ok(sql.includes("for update"), "asset row locking is missing");
assert.ok(sql.includes("if found then") && sql.includes("return _journal_id"), "safe retry is missing");
assert.ok(
  sql.includes("ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR"),
  "preparer/poster separation is missing",
);
assert.ok(
  sql.includes("ONEXA_ASSET_DEPRECIATION_OUT_OF_SEQUENCE"),
  "chronological period guard is missing",
);
assert.ok(
  sql.includes("ONEXA_POSTED_ASSET_FINANCIALS_IMMUTABLE"),
  "posted-register mutation guard is missing",
);
assert.ok(
  sql.includes("onexa_private.has_module_action(_actor, 'assets', 'post')"),
  "asset posting authorization is missing",
);
assert.ok(
  sql.includes("_source_document_type => 'depreciation_run'"),
  "B4 depreciation source adapter is missing",
);
assert.ok(
  sql.includes("posting_contract_version', 'asset-depreciation-v1"),
  "posting contract version is missing",
);
assert.ok(
  sql.includes(
    "revoke all on function public.onexa_post_asset_depreciation(uuid, text, date) from public, anon",
  ),
  "anonymous RPC access is not revoked",
);
assert.ok(
  !sql.includes("grant insert") &&
    !sql.includes("grant update") &&
    !sql.includes("grant delete"),
  "direct posting-ledger writes are exposed",
);

for (const role of ["depreciation_expense", "accumulated_depreciation"]) {
  assert.ok(sql.includes(`'${role}'`), `SQL role missing: ${role}`);
  assert.ok(mapping.includes(`'${role}'`), `mapping role missing: ${role}`);
}
for (const code of ["6200", "1290"]) {
  assert.ok(mapping.includes(`'${code}'`), `account missing: ${code}`);
}

for (const marker of [
  "ONEXA_SMOKE_READY_ASSET_REQUIRED",
  "ONEXA_SMOKE_DISTINCT_ASSET_POSTER_REQUIRED",
  "ONEXA_SMOKE_ASSET_ROLLFORWARD_FAILED",
  "ONEXA_SMOKE_ASSET_RETRY_NOT_IDEMPOTENT",
  "rollback;",
]) {
  assert.ok(smoke.includes(marker), `smoke-test invariant missing: ${marker}`);
}
assert.ok(!smoke.includes("commit;"), "smoke test must never commit");

assert.ok(
  postcheck.includes("authenticated direct insert/update/delete must remain false"),
  "postcheck privilege assertion is missing",
);
assert.ok(
  service.includes('db.rpc("onexa_post_asset_depreciation"'),
  "asset posting service RPC is missing",
);
assert.ok(
  service.includes('from("onexa_asset_accounting_reconciliation")'),
  "asset reconciliation query is missing",
);
assert.ok(
  panel.includes("مطابقة سجل الأصول والإهلاك") &&
    panel.includes("reconciliation_status"),
  "asset accounting panel is missing",
);
assert.ok(
  route.includes("AssetAccountingPanel"),
  "fixed-assets route does not render the accounting panel",
);
assert.ok(
  reports.includes('key: "fixed_asset_accounting_reconciliation"'),
  "asset reconciliation report is missing",
);
assert.ok(runtime.includes("ONEXA_ASSET_POSTING_ENABLED"), "runtime gate is missing");
assert.ok(
  env.includes('VITE_ENABLE_ONEXA_ASSET_POSTING=""'),
  "runtime flag must default false",
);
for (const phrase of [
  "does not post that acquisition value again",
  "straight line",
  "safe retry",
  "rollback smoke test",
]) {
  assert.ok(
    architecture.includes(phrase),
    `architecture decision missing: ${phrase}`,
  );
}
assert.equal(
  pkg.scripts["check:gate38-fixed-assets-gl-posting"],
  "node scripts/check-gate38-fixed-assets-gl-posting.mjs",
);
assert.ok(
  pkg.scripts.verify.includes("check:gate38-fixed-assets-gl-posting"),
  "Gate 38 is missing from verify",
);

console.log("Gate 38 ONEXA fixed-assets/GL posting checks passed ✓");
