import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const queuePath = "src/components/accounting/document-work-queue.tsx";
const receiptServicePath = "src/lib/sales/customer-receipt-service.ts";
const paymentServicePath = "src/lib/procurement/supplier-payment-service.ts";
const transferServicePath = "src/lib/finance/bank-transfer-service.ts";

for (const path of [
  queuePath,
  receiptServicePath,
  paymentServicePath,
  transferServicePath,
]) {
  assert.ok(existsSync(path), `Gate 61 file is missing: ${path}`);
}

const queue = read(queuePath);
const receiptService = read(receiptServicePath);
const paymentService = read(paymentServicePath);
const transferService = read(transferServicePath);
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "postOnexaReceipt",
  "postOnexaPayment",
  "postOnexaBankTransfer",
  "ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED",
  "ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED",
  "ONEXA_BANK_TRANSFER_POSTING_ENABLED",
  'item.document_type === "customer_receipt"',
  'item.document_type === "supplier_payment"',
  'item.document_type === "bank_transfer"',
  "يتطلب تنفيذ وتفعيل Gate 39",
  "يتطلب تنفيذ وتفعيل Gate 40",
  "يتطلب تنفيذ وتفعيل Gate 41",
  'queryKey: ["onexa-receivables"]',
  'queryKey: ["onexa-receipts"]',
  'queryKey: ["onexa-payables"]',
  'queryKey: ["onexa-payments"]',
  'queryKey: ["onexa-bank-transfers"]',
]) {
  assert.ok(queue.includes(marker), `treasury inbox contract missing: ${marker}`);
}

for (const [service, rpc, flag] of [
  [receiptService, "onexa_post_customer_receipt", "ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED"],
  [paymentService, "onexa_post_supplier_payment", "ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED"],
  [transferService, "onexa_post_bank_transfer", "ONEXA_BANK_TRANSFER_POSTING_ENABLED"],
]) {
  assert.ok(service.includes(rpc), `governed posting RPC missing: ${rpc}`);
  assert.ok(service.includes(flag), `fail-closed runtime flag missing: ${flag}`);
}

assert.ok(
  !queue.includes('.rpc("onexa_post_'),
  "work queue must use service boundaries instead of calling treasury RPCs directly",
);
assert.ok(
  !queue.includes('.from("onexa_business_documents").update'),
  "work queue must not bypass governed posting functions",
);
assert.equal(
  pkg.scripts["check:gate61-treasury-posting-inbox"],
  "node scripts/check-gate61-treasury-posting-inbox.mjs",
);
assert.ok(
  pkg.scripts.verify.includes("check:gate61-treasury-posting-inbox"),
  "Gate 61 is missing from verify",
);

console.log("Gate 61 unified treasury posting inbox checks passed ✓");
