import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const queuePath = "src/components/accounting/document-work-queue.tsx";
const servicePath = "src/lib/documents/business-document-service.ts";
const financialsPath = "src/routes/_authenticated/financials/index.tsx";
const hubPath = "src/components/accounting/operations-hub.tsx";

for (const path of [queuePath, servicePath, financialsPath, hubPath]) {
  assert.ok(existsSync(path), `Gate 59 file is missing: ${path}`);
}

const queue = read(queuePath);
const service = read(servicePath);
const financials = read(financialsPath);
const hub = read(hubPath);
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "listApprovalInbox",
  "listAccountingInbox",
  "transitionBusinessDocument",
  "postSalesInvoice",
  "postPurchaseInvoice",
  "ONEXA_SALES_POSTING_ENABLED",
  "ONEXA_PROCUREMENT_POSTING_ENABLED",
  "item.can_current_user_act",
  "current_step_name",
  "صندوق الاعتماد والترحيل",
  "يتطلب تنفيذ وتفعيل Gate 36",
]) assert.ok(queue.includes(marker), `work queue contract missing: ${marker}`);

for (const marker of [
  'export async function listApprovalInbox',
  '.from("onexa_approval_task_inbox")',
  'created_by,submitted_by,submitted_at,revision',
  'can_current_user_act',
  'export async function listAccountingInbox',
  '.from("onexa_accounting_inbox")',
]) assert.ok(service.includes(marker), `document service contract missing: ${marker}`);

assert.ok(!queue.includes('.from("onexa_business_documents").update'), "work queue must not bypass governed transition RPCs");
assert.ok(!queue.includes('.from("onexa_business_documents").insert'), "work queue must not create documents directly");
assert.ok(financials.includes("<AccountingDocumentWorkQueue />"), "financial workspace does not expose Gate 59");
assert.ok(financials.includes('id="manual-journal"'), "manual-journal operation link target is missing");
assert.ok(hub.includes('href="#manual-journal"'), "operations hub does not link to manual journals");
assert.ok(hub.includes("جاهز بعد تفعيل Gate 58"), "operations hub still reports the completed manual journal migration as missing");

assert.equal(pkg.scripts["check:gate59-accounting-work-queue"], "node scripts/check-gate59-accounting-work-queue.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate59-accounting-work-queue"), "Gate 59 is missing from verify");

console.log("Gate 59 accounting work queue checks passed ✓");
