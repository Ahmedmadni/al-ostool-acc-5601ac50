import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const panelPath = "src/components/sales/onexa-sales-invoice-panel.tsx";
const hubPath = "src/components/accounting/operations-hub.tsx";
assert.ok(existsSync(panelPath), "native sales invoice panel is missing");
assert.ok(existsSync(hubPath), "accounting operations hub is missing");

const panel = read(panelPath);
const hub = read(hubPath);
const invoices = read("src/routes/_authenticated/customers/invoices.tsx");
const financials = read("src/routes/_authenticated/financials/index.tsx");
const service = read("src/lib/documents/business-document-service.ts");
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "createBusinessDocument",
  'documentType: "sales_invoice"',
  'origin: "native"',
  "transitionBusinessDocument",
  '"submitted"',
  "accountRole: \"sales_revenue\"",
  "onexa-sales-business-documents",
  "فاتورة مبيعات جديدة",
]) assert.ok(panel.includes(marker), `native invoice workflow missing: ${marker}`);

assert.ok(!panel.includes('.from("invoices").insert'), "native invoices must not write to the legacy import table");
assert.ok(service.includes('db.rpc("onexa_create_business_document"'), "governed document RPC is missing");
assert.ok(service.includes('db.rpc("onexa_transition_business_document"'), "governed workflow RPC is missing");
assert.ok(invoices.includes("<OnexaSalesInvoicePanel />"), "sales invoice route does not expose native entry");
assert.ok(financials.includes("<AccountingOperationsHub />"), "accounting workspace does not expose operational entry");
for (const operation of [
  "/customers/invoices",
  "/vendors/invoices",
  "/customers/collections",
  "/vendors/payments",
  "/banks",
  "قيد يومية يدوي",
  "يتطلب Migration",
]) assert.ok(hub.includes(operation), `operations hub missing: ${operation}`);

assert.equal(pkg.scripts["check:gate55-native-sales-invoicing"], "node scripts/check-gate55-native-sales-invoicing.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate55-native-sales-invoicing"), "Gate 55 is missing from verify");

console.log("Gate 55 native sales invoicing checks passed ✓");
