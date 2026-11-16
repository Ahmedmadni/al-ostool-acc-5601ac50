import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ts from "typescript";

const source = readFileSync("src/lib/accounting/manual-journal-validation.ts", "utf8");
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText;
const { evaluateManualJournalDraft } = await import(
  "data:text/javascript;base64," + Buffer.from(compiled).toString("base64")
);

const base = {
  legalEntityId: "legal-A",
  branchId: "branch-A",
  entityIds: ["legal-A"],
  branchIdsForEntity: ["branch-A"],
  accountCodes: ["1110", "2110", "5100"],
  accountingDate: "2026-11-16",
  currency: "SAR",
  memo: "اختبار قيد تجريبي",
  lines: [
    { accountCode: "1110", debit: "100.10", credit: "", description: "" },
    { accountCode: "2110", debit: "", credit: "100.10", description: "" },
  ],
};
const validate = (changes = {}) => evaluateManualJournalDraft({ ...base, ...changes });
const line = (accountCode, debit, credit) => ({ accountCode, debit, credit, description: "" });

assert.equal(validate().valid, true, "ordinary SAR journal must pass");
assert.equal(validate().totalDebit, "100.10");
assert.equal(validate().totalCredit, "100.10");
assert.equal(validate().difference, "0.00");
assert.equal(validate().normalizedLines[0].debit, 100.1);

assert.equal(validate({
  lines: [line("1110", "0.10", ""), line("5100", "0.20", ""), line("2110", "", "0.30")],
}).valid, true, "0.1 + 0.2 must equal 0.3 exactly");

for (const bad of [
  { lines: [line("1110", "100.00", ""), line("2110", "", "100.01")] },
  { lines: [line("1110", "-100", ""), line("2110", "", "100")] },
  { lines: [line("1110", "Infinity", ""), line("2110", "", "100")] },
  { lines: [line("1110", "1e2", ""), line("2110", "", "100")] },
  { lines: [line("1110", "100.001", ""), line("2110", "", "100.001")] },
  { lines: [line("1110", "999999999999.99", ""), line("2110", "", "999999999999.99")] },
  { lines: [line("1110", "100", "1"), line("2110", "", "99")] },
  { lines: [line("1110", "", ""), line("2110", "", "")] },
  { lines: [line("9999", "100", ""), line("2110", "", "100")] },
  { lines: [line("1110", "100", "")] },
  { branchId: "branch-B" },
  { legalEntityId: "legal-B" },
  { accountingDate: "2026-02-30" },
  { accountingDate: "2026-13-01" },
  { currency: "INVALID" },
  { memo: "  " },
]) {
  const result = validate(bad);
  assert.equal(result.valid, false, "unsafe draft must be rejected: " + JSON.stringify(bad));
  assert.deepEqual(result.normalizedLines, [], "unsafe draft must never yield RPC-ready lines");
}

assert.equal(validate({
  currency: "KWD",
  lines: [line("1110", "1.123", ""), line("2110", "", "1.123")],
}).valid, true, "three-decimal currency must be accepted");
assert.equal(validate({
  currency: "KWD",
  lines: [line("1110", "1.1234", ""), line("2110", "", "1.1234")],
}).valid, false, "currency precision must be enforced");
assert.equal(validate({
  currency: "JPY",
  lines: [line("1110", "100", ""), line("2110", "", "100")],
}).valid, true, "zero-decimal currency must pass");
assert.equal(validate({
  currency: "JPY",
  lines: [line("1110", "100.01", ""), line("2110", "", "100.01")],
}).valid, false, "zero-decimal currency must reject fractional units");

console.log("ONEXA manual journal decimal/date/tenant-selection preflight tests passed");
