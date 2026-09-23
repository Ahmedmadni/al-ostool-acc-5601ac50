import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const workspace = read("src/routes/_authenticated/financials/index.tsx");
const integration = read("src/components/accounting/integration-overview.tsx");

for (const pattern of [
  /loadAccountingSnapshot/,
  /bank_statements/,
  /aging_buckets/,
  /supplier_balances/,
  /trial_balance_entries/,
  /حالة ميزان المراجعة/,
  /تحميل ميزان المراجعة/,
  /ACCOUNTING_LINKS/,
  /AccountingIntegrationOverview/,
]) assert.match(workspace, pattern);

for (const pattern of [
  /ONEXA CONNECTED LEDGER/,
  /bg-muted\/25/,
  /strokeWidth=\{1\.8\}/,
]) assert.match(integration, pattern);

console.log("Gate 46 accounting workspace checks passed");
