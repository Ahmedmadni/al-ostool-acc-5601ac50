import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = (p) => readFileSync(new URL(`../${p}`,import.meta.url),"utf8");

const workflow=read(".github/workflows/native-tenant-sql-smoke.yml");
const fixture=read("scripts/sql-fixtures/native-maintenance-parent-schema.sql");
const smoke=read("scripts/sql-fixtures/native-maintenance-two-tenant-smoke.sql");
const pkg=JSON.parse(read("package.json"));
const files=[
  "gate71_onexa_tenant_company_module_scopes.sql",
  "gate72_onexa_native_operations_sites_assets.sql",
  "gate73_onexa_native_operations_work_orders.sql",
  "gate74_native_maintenance_posted_cost_attribution.sql",
  "gate75_native_maintenance_unpaid_source_review.sql",
];

assert.match(workflow,/services:\s*\n\s*postgres:/);
assert.match(workflow,/image: postgres:16/);
assert.match(workflow,/POSTGRES_DB: onexa_gate_test/);
assert.match(workflow,/PGDATABASE: onexa_gate_test/);
assert.match(workflow,/PGPASSWORD: disposable_only/);
assert.match(workflow,/ON_ERROR_STOP=1/);
assert.match(workflow,/native-maintenance-parent-schema\.sql/);
assert.match(workflow,/native-maintenance-two-tenant-smoke\.sql/);
assert.doesNotMatch(workflow,/secrets\.|supabase\.co|supabase\.com|onexa\.com|service.role|project[_-]id/i,
  "Disposable PostgreSQL checks must never use production cloud credentials");

let previousIndex=-1;
for(const name of files) {
  assert.match(read("supabase/manual-packages/"+name),/begin;/i);
  const offset=workflow.indexOf(name);
  assert.ok(offset>previousIndex, "G71-G75 must compile in dependency order: "+name);
  previousIndex=offset;
}
assert.match(fixture,/-- SYNTHETIC EPHEMERAL TEST DB ONLY/);
assert.match(fixture,/tenant-smoke-A/);
assert.match(fixture,/tenant-smoke-B/);
assert.match(fixture,/create schema auth/);
assert.match(fixture,/create schema onexa_private/);
assert.match(fixture,/create role authenticated/);
assert.match(smoke,/set local role authenticated/);
assert.match(smoke,/SMOKE_CROSS_TENANT_RLS_WORK_ORDER_VISIBLE/);
assert.match(smoke,/SMOKE_CROSS_TENANT_WORK_ORDER_CREATED/);
assert.match(smoke,/SMOKE_CROSS_TENANT_CLAIM_REGISTERED/);
assert.match(smoke,/SMOKE_CREATOR_SELF_REVIEW_ALLOWED/);
assert.match(smoke,/SMOKE_REVERSED_GL_STILL_RECONCILED/);
assert.match(smoke,/SMOKE_REVERSED_GL_STILL_IN_COST_TOTAL/);
assert.match(smoke,/onexa_attribute_posted_project_cost/);
assert.match(smoke,/onexa_link_native_unpaid_maintenance_source/);
assert.match(smoke,/rollback;/);
assert.doesNotMatch(smoke,/tenant-001-al-ostool|a159a7c0|3ba2a953|localhost.*5432.*production/i,
  "No actual production tenant or environment details may be put in smoke fixtures");
assert.equal(pkg.scripts["check:gate76-ephemeral-postgres-smoke"],
  "node scripts/check-gate76-ephemeral-postgres-smoke.mjs");
assert.match(pkg.scripts.verify,/check:gate76-ephemeral-postgres-smoke/);
console.log("Gate76 disposable PostgreSQL safety contract verified");
