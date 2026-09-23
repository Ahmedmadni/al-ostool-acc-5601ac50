import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const executive = readFileSync(new URL("../src/routes/_authenticated/executive/index.tsx", import.meta.url), "utf8");

for (const pattern of [
  /const sources = \[/,
  /status: error \? "error" as const/,
  /جاهزية مصادر القرار/,
  /تعذر تحميل لوحة القرار/,
  /metricAvailable/,
  /value={metricAvailable\("invoices"\)/,
  /value={metricAvailable\("banks"\)/,
  /value={metricAvailable\("aging"\)/,
  /value={metricAvailable\("suppliers"\)/,
  /ChartEmptyState/,
  /فتح مركز الاستيراد/,
  /فتح الخزينة/,
]) assert.match(executive, pattern);

assert.match(executive, /source\("invoices".*inv\.error/);
assert.match(executive, /source\("banks".*banks\.error/);
assert.match(executive, /source\("costs".*costs\.error/);
assert.doesNotMatch(executive, /value={fmtSAR\(data\?\.snapshot\.cashPosition \?\? 0\)}/);

console.log("Gate 51 executive data-readiness checks passed");
