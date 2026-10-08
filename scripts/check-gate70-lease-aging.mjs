import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate70_lease_receivables_aging.sql");
const check = read("supabase/manual-packages/gate70_postcheck.sql");
const service = read("src/lib/real-estate/lease-accounting-service.ts");
const report = read("src/components/real-estate/onexa-lease-property-report.tsx");
const aging = read("src/components/real-estate/onexa-lease-aging-report.tsx");
const flags = read("src/lib/runtime-flags.ts");

for (const pattern of [
  /ONEXA_GATE69_LEASE_PROPERTY_REPORT_REQUIRED/,
  /ONEXA_LEASE_AGING_NOT_AUTHORIZED/,
  /scope\.tenant_id=_tenant/,
  /receipt\.accounting_date<=_as_of/,
  /d\.accounting_date<=_as_of/,
  /i\.due_date>=_as_of/,
  /i\.due_date<_as_of-90/,
  /limit 25/,
  /revoke all on function public\.onexa_lease_receivables_aging/,
]) assert.match(sql, pattern);
assert.match(check, /anon_can_read/);
assert.match(service, /onexa_lease_receivables_aging/);
assert.match(flags, /ONEXA_LEASE_AGING_ENABLED/);
assert.match(report, /OnexaLeaseAgingReport/);
assert.match(aging, /أعمار مديونيات الإيجار/);
console.log("Gate 70 lease receivables aging checks passed");
