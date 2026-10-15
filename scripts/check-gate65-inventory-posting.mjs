import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate65_inventory_gl_posting.sql");
const mapping = read("supabase/manual-packages/gate65_aoa_inventory_mapping.sql");
const postcheck = read("supabase/manual-packages/gate65_postcheck.sql");
const smoke = read("supabase/manual-packages/gate65_inventory_smoke_test_rollback.sql");
const service = read("src/lib/inventory/inventory-posting-service.ts");
const panel = read("src/components/inventory/onexa-inventory-document-panel.tsx");
const flags = read("src/lib/runtime-flags.ts");
const queue = read("src/components/accounting/document-work-queue.tsx");
const receipts = read("src/routes/_authenticated/warehouses/receipts.tsx");
const issues = read("src/routes/_authenticated/warehouses/issues.tsx");

for (const pattern of [
  /onexa_inventory_posting_runs/,
  /onexa_inventory_document_reconciliation/,
  /onexa_post_inventory_document\(/,
  /has_module_action\(_actor,'inventory','post'\)/,
  /onexa_approval_separation_required\(_document\.document_type,'post'\)/,
  /pg_advisory_xact_lock/,
  /for update/,
  /moving|weighted|average_unit_cost/,
  /goods_received_not_invoiced/,
  /project_cost_cogs_or_expense/,
  /with \(security_invoker = true\)/,
  /enable row level security/,
  /revoke all on public\.onexa_inventory_posting_runs from anon,authenticated/,
  /revoke insert,update,delete on public\.inventory_receipts/,
]) assert.match(sql, pattern);

assert.match(mapping, /'2120'/);
assert.match(mapping, /'5700'/);
assert.match(postcheck, /direct_writes_denied/);
assert.match(postcheck, /anon_can_execute/);
for (const marker of [
  "onexa_guard_inventory_journal_reversal",
  "ONEXA_INVENTORY_STOCK_COMPENSATION_REQUIRED",
  "ONEXA_INVENTORY_JOURNAL_REVERSED_OR_MISSING",
  "journal_reversed_or_missing",
  "journal_source_or_value_mismatch",
  "movement_journal_mismatch",
  "distinct_journal_count",
  "missing_journal_count",
  "journal.state='posted' and journal.reversal_journal_id is null",
  "account.category::text='liabilities'",
  "account.category::text='assets'",
  "ONEXA_GATE64_APPROVAL_POSTING_BRIDGE_REQUIRED",
]) assert.ok(sql.includes(marker), `Missing inventory integrity control: ${marker}`);
assert.match(sql, /when \(old.state = 'posted' and new.state = 'reversed'\)/);
assert.match(sql, /from public\.onexa_inventory_posting_runs posting/);
assert.match(postcheck, /inventory_reversal_guard/);
assert.match(postcheck, /movement_journal_mismatch/);
assert.match(postcheck, /journal_source_or_value_mismatch/);
assert.match(smoke, /_retry:=public\.onexa_post_inventory_document/);
assert.match(smoke, /rollback;/i);
assert.match(service, /documentType: input\.kind === "receipt" \? "inventory_receipt" : "inventory_issue"/);
assert.match(service, /transitionBusinessDocument\(documentId, "submitted"\)/);
assert.match(panel, /average_unit_cost/);
assert.match(flags, /ONEXA_INVENTORY_POSTING_ENABLED/);
assert.match(queue, /postOnexaInventoryDocument/);
assert.match(receipts, /OnexaInventoryDocumentPanel kind="receipt"/);
assert.match(issues, /OnexaInventoryDocumentPanel kind="issue"/);
console.log("Gate 65 inventory posting checks passed");
