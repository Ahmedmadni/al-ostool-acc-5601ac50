import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const gateCardPath = "src/components/operations/operational-gate-card.tsx";
assert.ok(existsSync(gateCardPath), "operational readiness card is missing");

const gateCard = read(gateCardPath);
const receipts = read("src/components/collections/onexa-receipts-panel.tsx");
const payments = read("src/components/procurement/onexa-vendor-payments-panel.tsx");
const transfers = read("src/components/finance/onexa-bank-transfers-panel.tsx");
const hub = read("src/components/accounting/operations-hub.tsx");
const pkg = JSON.parse(read("package.json"));

for (const marker of ["actionLabel", "تطبيق حزمة", "Postcheck وSmoke test", "تفعيل مفتاح التشغيل الآمن"]) {
  assert.ok(gateCard.includes(marker), `readiness surface missing: ${marker}`);
}
for (const [source, gate, action] of [
  [receipts, "Gate 39", "إنشاء سند تحصيل"],
  [payments, "Gate 40", "إنشاء سند دفع"],
  [transfers, "Gate 41", "إنشاء تحويل بنكي"],
]) {
  assert.ok(source.includes("<OperationalGateCard"), `operational gate card missing for ${gate}`);
  assert.ok(source.includes(gate) && source.includes(action), `visible gated action missing for ${gate}`);
}
for (const gate of ["جاهز بعد Gate 39", "جاهز بعد Gate 40", "جاهز بعد Gate 41"]) {
  assert.ok(hub.includes(gate), `operations hub readiness missing: ${gate}`);
}

assert.equal(pkg.scripts["check:gate57-operational-readiness"], "node scripts/check-gate57-operational-readiness.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate57-operational-readiness"), "Gate 57 is missing from verify");

console.log("Gate 57 operational readiness checks passed ✓");
