import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/onexa_gate64_readonly_preflight.sql");
const runbook = read("docs/runbooks/onexa-gate64-activation-readiness.md");

for (const signature of [
  "onexa_post_sales_invoice(uuid,text)",
  "onexa_post_purchase_invoice(uuid,text)",
  "onexa_post_customer_receipt(uuid,text)",
  "onexa_post_supplier_payment(uuid,text)",
  "onexa_post_bank_transfer(uuid,text)",
  "onexa_post_project_cost(uuid,text)",
  "onexa_post_fleet_trip_cost(uuid,text)",
  "approval_actor_matches_step(uuid,uuid,uuid)",
  "onexa_approval_separation_required(text,text)",
]) assert.ok(sql.includes(signature), "Missing Gate 64 prerequisite: " + signature);

assert.match(sql, /to_regprocedure\(function_signature\)/);
assert.match(sql, /pg_get_functiondef\(to_regprocedure\(function_signature\)\)/);
assert.match(sql, /MANUAL_DEFINITION_REVIEW_REQUIRED/);
assert.match(sql, /DATABASE_ACCEPTANCE_NOT_VERIFIED/);
assert.doesNotMatch(sql, /^\s*(?:begin|commit|create|alter|drop|truncate|insert|update|delete|grant|revoke|do|call)\b/im);
assert.match(runbook, /NO PRODUCTION SQL/);
assert.match(runbook, /Gate 40/);
console.log("Gate 64 production-readiness preflight checks passed");
