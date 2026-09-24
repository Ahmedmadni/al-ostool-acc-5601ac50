import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const panelPath = "src/components/procurement/onexa-purchase-invoice-panel.tsx";
assert.ok(existsSync(panelPath), "native purchase invoice panel is missing");

const panel = read(panelPath);
const invoices = read("src/routes/_authenticated/vendors/invoices.tsx");
const hub = read("src/components/accounting/operations-hub.tsx");
const service = read("src/lib/documents/business-document-service.ts");
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "createBusinessDocument",
  'documentType: "purchase_invoice"',
  'module: "procurement"',
  'origin: "native"',
  "transitionBusinessDocument",
  '"submitted"',
  '"purchase_expense"',
  '"inventory"',
  '"fixed_asset_cost"',
  "itemId:",
  "warehouseId:",
  "فاتورة مشتريات جديدة",
]) assert.ok(panel.includes(marker), `native purchase workflow missing: ${marker}`);

assert.ok(!panel.includes('.from("purchase_invoices").insert'), "native purchases must not write to the legacy import table");
assert.ok(service.includes('db.rpc("onexa_create_business_document"'), "governed document RPC is missing");
assert.ok(invoices.includes("<OnexaPurchaseInvoicePanel />"), "purchase route does not expose native entry");
assert.ok(hub.includes('title: "فاتورة مشتريات"') && hub.includes('state: "متاح الآن"'), "operations hub does not mark purchasing as operational");

assert.equal(pkg.scripts["check:gate56-native-purchase-invoicing"], "node scripts/check-gate56-native-purchase-invoicing.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate56-native-purchase-invoicing"), "Gate 56 is missing from verify");

console.log("Gate 56 native purchase invoicing checks passed ✓");
