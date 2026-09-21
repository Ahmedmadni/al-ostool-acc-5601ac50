import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const migrationPath = "supabase/migrations/202609200001_onexa_business_document_foundation.sql";
assert.ok(existsSync(migrationPath), "Gate 34 migration is missing");

const migration = read(migrationPath);
const service = read("src/lib/documents/business-document-service.ts");
const modules = read("src/lib/erp-module-model.ts");
const reports = read("src/lib/reporting/report-catalog.ts");
const shell = read("src/components/layout/app-shell.tsx");
const apps = read("src/lib/erp-apps.ts");
const architecture = read("docs/architecture/onexa-accounting-first-erp.md");
const pkg = JSON.parse(read("package.json"));

for (const table of ["onexa_document_sequences", "onexa_business_documents", "onexa_business_document_lines", "onexa_business_document_events"]) {
  assert.ok(migration.includes(`public.${table}`), `missing business-document table: ${table}`);
  assert.ok(migration.includes(`alter table public.${table} enable row level security`), `RLS missing: ${table}`);
}

for (const invariant of [
  "app_metadata", "ONEXA_TENANT_MISMATCH", "ONEXA_SEGREGATION_OF_DUTIES_REQUIRED",
  "ONEXA_ONLY_DOCUMENT_CREATOR_CAN_EDIT_LINES", "ONEXA_DOCUMENT_TYPE_MODULE_MISMATCH",
  "onexa.transition_authorized", "security_invoker = true", "set search_path", "onexa_accounting_inbox",
]) assert.ok(migration.includes(invariant), `database invariant missing: ${invariant}`);

assert.ok(migration.includes("security definer"), "atomic numbered document creation must be hardened");
assert.ok(migration.includes("revoke all on function public.onexa_create_business_document"), "create RPC default execute was not revoked");
assert.ok(!migration.includes("grant select, insert, update, delete on table public.onexa_business_documents"), "direct document insert must not be granted");
assert.ok(migration.includes("grant select on table public.onexa_business_documents to authenticated"), "document table should be read-only outside governed RPCs");
assert.ok(service.includes('db.rpc("onexa_create_business_document"'), "document service does not use the atomic create RPC");
assert.ok(service.includes('db.rpc("onexa_transition_business_document"'), "document service does not use the workflow RPC");
assert.ok(service.includes('from("onexa_accounting_inbox")'), "accounting inbox service is missing");

for (const module of ["finance", "sales", "procurement", "inventory", "projects", "facilities", "logistics", "assets", "people"]) {
  assert.ok(modules.includes(`key: "${module}"`), `module blueprint missing: ${module}`);
  assert.ok(reports.includes(`owner: "${module}"`), `module-owned report missing: ${module}`);
}

const executiveStart = shell.indexOf('key: "executive"');
const customersStart = shell.indexOf('key: "customers"');
assert.ok(executiveStart >= 0 && customersStart > executiveStart, "Executive navigation group is missing");
assert.ok(shell.slice(executiveStart, customersStart).includes('to: "/reports"'), "consolidated reports center is not under Executive Management");
assert.ok(!shell.includes('key: "reports"'), "standalone reports navigation group still exists");
assert.ok(!apps.includes('{ key: "reports"'), "standalone reports launcher app still exists");

for (const route of [
  "/projects/reports", "/real-estate/reports", "/fixed-assets/reports",
  "/fleet/reports", "/warehouses/reports", "/financials/reports",
]) assert.ok(shell.includes(`to: "${route}"`), `module report navigation missing: ${route}`);

for (const file of [
  "src/routes/_authenticated/projects/reports.tsx",
  "src/routes/_authenticated/real-estate_.reports.tsx",
  "src/routes/_authenticated/fixed-assets/reports.tsx",
  "src/routes/_authenticated/fleet/reports.tsx",
  "src/routes/_authenticated/warehouses/reports.tsx",
  "src/routes/_authenticated/financials/reports.tsx",
]) assert.ok(existsSync(file), `module report workspace missing: ${file}`);

for (const phrase of ["transaction system first", "creator cannot approve", "Executive Management", "onexa_post_journal", "sales invoice → stock issue/valuation"]) {
  assert.ok(architecture.includes(phrase), `architecture decision missing: ${phrase}`);
}

assert.equal(pkg.scripts["check:gate34-accounting-first-erp"], "node scripts/check-gate34-accounting-first-erp.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate34-accounting-first-erp"), "Gate 34 is missing from verify");

console.log("Gate 34 ONEXA accounting-first ERP checks passed ✓");
