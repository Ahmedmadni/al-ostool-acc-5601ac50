import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate69_lease_property_financial_report.sql");
const postcheck = read("supabase/manual-packages/gate69_postcheck.sql");
const service = read("src/lib/real-estate/lease-accounting-service.ts");
const panel = read("src/components/real-estate/onexa-lease-accounting-panel.tsx");
const report = read("src/components/real-estate/onexa-lease-property-report.tsx");
const flags = read("src/lib/runtime-flags.ts");

for (const pattern of [
  /ONEXA_GATE68_LEASE_RECONCILIATION_REQUIRED/,
  /ONEXA_LEASE_REPORT_NOT_AUTHORIZED/,
  /scope\.tenant_id=_tenant/,
  /d\.status='posted'/,
  /d\.accounting_date/,
  /i\.accounting_date between _from and _to/,
  /r\.accounting_date between _from and _to/,
  /r\.accounting_date<=_to/,
  /revoke all on function public\.onexa_lease_property_financial_report/,
]) assert.match(sql, pattern);
assert.match(postcheck, /anon_can_report/);
assert.match(postcheck, /RECEIPT_SOURCE_MISMATCH/);
assert.match(sql, /invoice_journal\.state='posted'/);
assert.match(sql, /invoice_journal\.state='reversed'/);
assert.match(sql, /invoice_reversal\.accounting_date>_to/);
assert.match(sql, /receipt_journal\.state='posted'/);
assert.match(sql, /receipt_journal\.state='reversed'/);
assert.match(sql, /receipt_reversal\.accounting_date>_to/);
assert.match(sql, /invoice_reversal\.reversal_of_id=invoice_journal\.id/);
assert.match(sql, /receipt_reversal\.reversal_of_id=receipt_journal\.id/);
assert.match(postcheck, /INVOICE_GL_LINEAGE_INVALID/);
assert.match(postcheck, /RECEIPT_GL_LINEAGE_INVALID/);
assert.match(flags, /ONEXA_LEASE_PROPERTY_REPORT_ENABLED/);
assert.match(service, /onexa_lease_property_financial_report/);
assert.match(panel, /OnexaLeasePropertyReport/);
assert.match(report, /صافي الفواتير المرحلة/);
console.log("Gate 69 lease property financial report checks passed");
