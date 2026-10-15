import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate66_maintenance_work_order_costs.sql");
const mapping = read("supabase/manual-packages/gate66_aoa_maintenance_mapping.sql");
const postcheck = read("supabase/manual-packages/gate66_postcheck.sql");
const smoke = read("supabase/manual-packages/gate66_maintenance_cost_smoke_test_rollback.sql");
const service = read("src/lib/maintenance/maintenance-cost-service.ts");
const panel = read("src/components/maintenance/onexa-maintenance-costs-panel.tsx");
const flags = read("src/lib/runtime-flags.ts");
const queue = read("src/components/accounting/document-work-queue.tsx");
const route = read("src/routes/_authenticated/maintenance.tsx");

for (const pattern of [
  /onexa_maintenance_work_order_scopes/,
  /onexa_maintenance_work_order_cost_postings/,
  /onexa_save_maintenance_work_order_scope\(/,
  /onexa_post_maintenance_work_order_cost\(/,
  /ops_has_company_access\(_work_order\.company_id\)/,
  /work_order\.status not in \('completed','accepted'\)/,
  /onexa_approval_separation_required\(_document\.document_type,'post'\)/,
  /pg_advisory_xact_lock/,
  /for update/,
  /unique \(tenant_id, legal_entity_id, external_reference\)/,
  /with \(security_invoker=true\)/,
  /enable row level security/,
]) assert.match(sql, pattern);

assert.match(mapping, /'2190'/);
assert.match(mapping, /'5800'/);
assert.match(postcheck, /direct_writes_denied/);
assert.match(postcheck, /anon_can_post/);
for (const marker of [
  "onexa_journal_headers journal",
  "journal_reversed_or_missing",
  "journal_source_or_amount_mismatch",
  "scope_entity_branch_mismatch",
  "ONEXA_MAINTENANCE_JOURNAL_REVERSED_OR_MISSING",
  "journal.state='posted' and journal.reversal_journal_id is null",
  "account.category::text='liabilities'",
  "account.category::text in ('assets','expenses','cost_of_revenue')",
  "onexa_guard_approval_posting",
]) assert.ok(sql.includes(marker), `Missing maintenance journal safeguard: ${marker}`);
assert.match(postcheck, /tgenabled<>'D'/);
assert.match(postcheck, /journal_source_or_amount_mismatch/);
assert.match(postcheck, /scope_entity_branch_mismatch/);
assert.match(sql, /ONEXA_MAINTENANCE_SCOPE_REASSIGNMENT_FORBIDDEN/);
assert.match(sql, /onexa_maintenance_work_order_scopes\.tenant_id=excluded\.tenant_id/);
assert.match(sql, /onexa_maintenance_work_order_scopes\.legal_entity_id=excluded\.legal_entity_id/);
assert.match(sql, /onexa_maintenance_work_order_scopes\.branch_id=excluded\.branch_id/);
assert.doesNotMatch(sql, /on conflict \(work_order_id\) do update set\s+tenant_id=excluded\.tenant_id/);
assert.match(panel, /date\.getFullYear\(\)/);
assert.doesNotMatch(panel, /new Date\(\)\.toISOString\(\)\.slice\(0, 10\)/);
assert.match(smoke, /_retry:=public\.onexa_post_maintenance_work_order_cost/);
assert.match(smoke, /rollback;/i);
assert.match(service, /documentType: "maintenance_work_order_cost"/);
assert.match(service, /source_kind: "unpaid_maintenance_cost"/);
assert.match(panel, /لا تستخدم هذا المسار لإعادة تسجيل تكلفة/);
assert.match(flags, /ONEXA_MAINTENANCE_COST_POSTING_ENABLED/);
assert.match(queue, /postOnexaMaintenanceCost/);
assert.match(route, /OnexaMaintenanceCostsPanel/);
console.log("Gate 66 maintenance work-order cost checks passed");
