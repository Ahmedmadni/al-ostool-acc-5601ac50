import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import ts from "typescript";

// Exercise the actual TypeScript helper without copying monetary rules into
// the test. No DB, no user financial data, no runtime code generation from
// network inputs: the source is version-controlled in this repository.
const source = readFileSync("src/lib/accounting/posting-money.ts","utf8");
const output = ts.transpileModule(source,{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},
  reportDiagnostics:true,
});
assert.deepEqual(output.diagnostics?.filter(d=>d.category===ts.DiagnosticCategory.Error),[]);
const exports = {};
runInNewContext(output.outputText,{exports,BigInt,String,Number,Set,Boolean});
const check = (...args) => Array.from(exports.inspectPostingMoneyTotals(...args));

assert.deepEqual(check(125.25,125.25,"SAR"),[]);
assert.deepEqual(check(125.25,125.26,"SAR"),["journal_must_balance"]);
assert.deepEqual(check(100,100.004,"KWD"),["journal_must_balance"],
  "Any sub-0.005 debit/credit difference must fail");
assert.deepEqual(check(100.001,100.001,"SAR"),["sar_halalah_precision_invalid"],
  "SAR cannot post fractional halalas even if totals match");
assert.deepEqual(check(90.125,90.125,"KWD"),[],
  "Other supported currencies may carry >=3 decimals pending currency policy");
assert.deepEqual(check(90.00001,90.00001,"KWD"),["money_storage_precision_invalid"],
  "Four-decimal B4 storage must not silently round five-decimal sources");
assert.deepEqual(check(0.1+0.2,0.3,"SAR"),["money_storage_precision_invalid"],
  "Floating-point computation artifacts must not be auto-rounded into postings");
assert.deepEqual(check(0,0,"SAR"),["positive_totals_required"]);
assert.deepEqual(check(-1,1,"SAR"),["positive_totals_required"]);
assert.deepEqual(check(NaN,1,"SAR"),["finite_totals_required"]);
assert.deepEqual(check(Infinity,Infinity,"SAR"),["finite_totals_required"]);
assert.deepEqual(check(Number.MAX_SAFE_INTEGER+1,Number.MAX_SAFE_INTEGER+1,"SAR"),["unsafe_money_number"],
  "Numbers beyond safe JS integer precision require a string/decimal representation");
assert.deepEqual(check(1e-7,1e-7,"KWD"),["money_decimal_format_invalid"],
  "Exponent notation is refused rather than misinterpreted as a money amount");

console.log("B4 frontend money readiness: exact totals, SAR halalas, 4-place storage and unsafe floats rejected ✓");
