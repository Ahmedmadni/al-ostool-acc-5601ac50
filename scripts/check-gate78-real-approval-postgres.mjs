import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read=(path)=>readFileSync(new URL(`../${path}`,import.meta.url),"utf8");
const flow=read(".github/workflows/native-tenant-sql-smoke.yml");
const parent=read("scripts/sql-fixtures/native-g64-approval-parent.sql");
const smoke=read("scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql");
const actual=read("supabase/manual-packages/gate64_approval_posting_bridge.sql");
const pkg=JSON.parse(read("package.json"));
for(const x of ["real-g64-approval-posting-smoke:","gate64_approval_posting_bridge.sql",
 "native-g64-approval-parent.sql","native-g64-real-approval-posting-smoke.sql",
 "postgres:16","ON_ERROR_STOP=1"]) assert.ok(flow.includes(x),"Missing real Gate64 PostgreSQL smoke job: "+x);
assert.match(parent,/create table public\.onexa_approval_instances/);
assert.match(parent,/create table public\.onexa_approval_workflow_steps/);
assert.match(parent,/create table public\.onexa_approval_decisions/);
assert.match(parent,/create function public\.onexa_approval_separation_required/);
assert.match(parent,/create function onexa_private\.approval_actor_matches_step/);
for(const n of ["onexa_post_sales_invoice","onexa_post_purchase_invoice",
 "onexa_post_customer_receipt","onexa_post_supplier_payment",
 "onexa_post_bank_transfer","onexa_post_fleet_trip_cost"]) {
 assert.match(parent,new RegExp("create function public\\."+n+"\\("));
}
assert.doesNotMatch(parent,/create table public\.onexa_project_cost_centers|create table public\.onexa_project_cost_postings/i);
assert.match(actual,/create or replace function onexa_private\.guard_approval_posting/);
assert.match(actual,/create or replace function onexa_private\.finalize_approval_posting/);
assert.match(actual,/ONEXA_POST_STEP_NOT_ASSIGNED_TO_ACTOR/);
assert.match(smoke,/SMOKE_G64_UNASSIGNED_POSTER_WAS_ALLOWED/);
assert.match(smoke,/SMOKE_G64_REJECTED_POST_LEFT_ACCOUNTING_ROWS/);
assert.match(smoke,/SMOKE_G64_REJECTED_POST_ADVANCED_APPROVAL/);
assert.match(smoke,/SMOKE_G64_POST_STEP_NOT_COMPLETED/);
assert.match(smoke,/SMOKE_G64_POST_DECISION_NOT_AUDITED/);
assert.match(smoke,/onexa_post_project_cost\(/);
assert.match(smoke,/SMOKE_CROSS_TENANT_RLS_WORK_ORDER_VISIBLE/);
assert.match(smoke,/SMOKE_REVERSED_GL_STILL_IN_COST_TOTAL/);
assert.doesNotMatch(smoke,/insert into public\.onexa_project_cost_postings|insert into public\.onexa_journal_headers/i);
assert.doesNotMatch(flow,/secrets\.|supabase\.co|supabase\.com|service.role/i);
assert.equal(pkg.scripts["check:gate78-real-approval-postgres"],
 "node scripts/check-gate78-real-approval-postgres.mjs");
assert.match(pkg.scripts.verify,/check:gate78-real-approval-postgres/);
console.log("Gate78 real Gate64 approval guard and G42 posting smoke contract passed");
