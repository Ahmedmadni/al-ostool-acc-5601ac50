import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = (path) => readFileSync(new URL(`../${path}`,import.meta.url),"utf8");

const job=read(".github/workflows/native-tenant-sql-smoke.yml");
const parent=read("scripts/sql-fixtures/native-g42-real-posting-parent.sql");
const seeds=read("scripts/sql-fixtures/native-g42-real-posting-centers.sql");
const smoke=read("scripts/sql-fixtures/native-g42-real-posting-two-tenant-smoke.sql");
const actual=read("supabase/manual-packages/gate42_project_costs.sql");
const pkg=JSON.parse(read("package.json"));
for (const s of [
 "real-g42-posting-smoke:", "image: postgres:16",
 "native-g42-real-posting-parent.sql",
 "gate42_project_costs.sql",
 "native-g42-real-posting-centers.sql",
 "native-g42-real-posting-two-tenant-smoke.sql",
 "ON_ERROR_STOP=1",
]) assert.ok(job.includes(s),"Missing actual G42 smoke CI requirement: "+s);
assert.doesNotMatch(job,/secrets\.|supabase\.com|supabase\.co|service.role/i,
 "Never use production Supabase credentials or services for finance tests");
assert.match(parent,/-- Native ONEXA finance shell ONLY/);
assert.doesNotMatch(parent,/create table public\.onexa_project_cost_centers/i);
assert.doesNotMatch(parent,/create table public\.onexa_project_cost_postings/i);
assert.match(parent,/create function public\.onexa_post_journal\(/);
assert.match(parent,/SMOKE_B4_STUB_INVALID_JOURNAL_SOURCE/);
assert.match(parent,/insert into public\.onexa_account_role_mappings/);
assert.match(seeds,/insert into public\.onexa_project_cost_centers/);
assert.match(actual,/create table if not exists public\.onexa_project_cost_centers/);
assert.match(actual,/create table if not exists public\.onexa_project_cost_postings/);
assert.match(actual,/create or replace function public\.onexa_post_project_cost/);
assert.match(smoke,/public\.onexa_post_project_cost\(/);
assert.match(smoke,/SMOKE_GATE42_POSTED_DUPLICATED_COST/);
assert.match(smoke,/SMOKE_GATE42_POST_STATUS_ORIGINAL_JOURNAL_MISMATCH/);
assert.match(smoke,/SMOKE_GATE42_RETRY_CREATED_DUPLICATE_JOURNAL/);
assert.match(smoke,/SMOKE_GATE75_LINK_RECONCILIATION_FAILED/);
assert.match(smoke,/SMOKE_CROSS_TENANT_WORK_ORDER_CREATED/);
assert.match(smoke,/SMOKE_REVERSED_GL_STILL_IN_COST_TOTAL/);
assert.doesNotMatch(smoke,/insert into public\.onexa_project_cost_postings|insert into public\.onexa_journal_headers/i,
 "Real Gate42 posting must create its journal & posting; tests must not inject them");
assert.match(smoke,/rollback;/);
assert.equal(pkg.scripts["check:gate77-real-g42-postgres"],
 "node scripts/check-gate77-real-g42-postgres.mjs");
assert.match(pkg.scripts.verify,/check:gate77-real-g42-postgres/);
console.log("Gate77 real Gate42 SQL and isolated posting/safety CI contract passed");
