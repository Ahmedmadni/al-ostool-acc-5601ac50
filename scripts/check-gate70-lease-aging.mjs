import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate70_lease_receivables_aging.sql");
const check = read("supabase/manual-packages/gate70_postcheck.sql");
const service = read("src/lib/real-estate/lease-accounting-service.ts");
const report = read("src/components/real-estate/onexa-lease-property-report.tsx");
const aging = read("src/components/real-estate/onexa-lease-aging-report.tsx");
const flags = read("src/lib/runtime-flags.ts");
const preflight = read("supabase/manual-packages/lease_gates_67_70_readonly_preflight.sql");
const rollout = read("docs/runbooks/onexa-lease-gates-67-70-rollout.md");

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
assert.match(check, /receipt_doc\.status='posted'/);
assert.match(check, /sum\(case when receipt_doc\.id is not null and receipt_journal\.id is not null then r\.amount else 0 end\)/);
assert.match(sql, /invoice_journal\.state='posted'/);
assert.match(sql, /invoice_journal\.state='reversed'/);
assert.match(sql, /invoice_reversal\.accounting_date>_as_of/);
assert.match(sql, /receipt_journal\.state='posted'/);
assert.match(sql, /receipt_journal\.state='reversed'/);
assert.match(sql, /receipt_reversal\.accounting_date>_as_of/);
assert.match(sql, /receipt_journal\.source_document_id=r\.document_id::text/);
assert.match(check, /receipt_journal\.state='posted'/);
assert.match(service, /onexa_lease_receivables_aging/);
assert.match(flags, /ONEXA_LEASE_AGING_ENABLED/);
assert.match(report, /OnexaLeaseAgingReport/);
assert.match(aging, /أعمار مديونيات الإيجار/);
for (const stage of ["67", "68", "69", "70"]) {
  assert.ok(preflight.includes("('" + stage + "'"), "Lease preflight must inventory Gate " + stage);
}
for (const signature of ["onexa_post_lease_invoice(uuid,text)", "onexa_lease_schedule_dashboard()", "onexa_lease_property_financial_report(uuid,date,date)", "onexa_lease_receivables_aging(uuid,date)"]) {
  assert.ok(preflight.includes(signature), "Lease preflight missing " + signature);
}
assert.doesNotMatch(preflight, /^\s*(?:begin|commit|create|alter|drop|truncate|insert|update|delete|grant|revoke|do|call)\b/im);
assert.match(rollout, /VITE_ENABLE_ONEXA_LEASE_AGING/);
assert.match(rollout, /NOT VERIFIED/);
console.log("Gate 70 lease receivables aging checks passed");
