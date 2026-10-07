import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate68_lease_schedule_reconciliation.sql");
const postcheck = read("supabase/manual-packages/gate68_postcheck.sql");
const smoke = read("supabase/manual-packages/gate68_lease_schedule_smoke_test_rollback.sql");
const flags = read("src/lib/runtime-flags.ts");
const route = read("src/routes/_authenticated/real-estate.tsx");

for (const pattern of [
  /ONEXA_GATE67_LEASE_ACCOUNTING_REQUIRED/,
  /onexa_guard_posted_lease_schedule/,
  /before update or delete/,
  /ONEXA_POSTED_LEASE_SCHEDULE_IMMUTABLE/,
  /scope\.tenant_id=_tenant/,
  /receipt\.invoice_id=p\.document_id and receipt\.tenant_id=_tenant/,
  /onexa_lease_schedule_dashboard\(\)/,
  /onexa_lease_portfolio_snapshot\(\)/,
  /has_module_action\(auth\.uid\(\),'facilities','read'\)/,
  /revoke all on function/,
]) assert.match(sql, pattern);
assert.match(postcheck, /authenticated_can_snapshot/);
assert.match(postcheck, /having s\.invoice_id is not null/);
assert.match(smoke, /ONEXA_GATE68_SCHEDULE_GUARD_FAILED/);
assert.match(smoke, /rollback;/i);
assert.match(flags, /ONEXA_LEASE_RECONCILIATION_ENABLED/);
assert.match(route, /ONEXA_LEASE_RECONCILIATION_ENABLED/);
assert.match(route, /onexa_lease_schedule_dashboard/);
assert.match(route, /onexa_lease_portfolio_snapshot/);
console.log("Gate 68 lease schedule reconciliation checks passed");
