import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sql = read("supabase/manual-packages/gate64_approval_posting_bridge.sql");
const postcheck = read("supabase/manual-packages/gate64_postcheck.sql");
const service = read("src/lib/documents/business-document-service.ts");
const queue = read("src/components/accounting/document-work-queue.tsx");
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "guard_approval_posting",
  "finalize_approval_posting",
  "ONEXA_POST_STEP_NOT_ASSIGNED_TO_ACTOR",
  "ONEXA_APPROVAL_POST_INSTANCE_REQUIRED",
  "onexa_approval_separation_required",
  "approval_actor_matches_step",
  "onexa_can_post_business_document",
  "can_current_user_post",
  "decision, reason",
  "'posted'",
]) assert.ok(sql.includes(marker), `Gate 64 contract missing: ${marker}`);

for (const engine of [
  "onexa_post_sales_invoice",
  "onexa_post_purchase_invoice",
  "onexa_post_customer_receipt",
  "onexa_post_supplier_payment",
  "onexa_post_bank_transfer",
  "onexa_post_project_cost",
  "onexa_post_fleet_trip_cost",
]) {
  assert.ok(sql.includes(engine), `Posting engine is not governed: ${engine}`);
}

assert.ok(sql.includes("before update on public.onexa_business_documents"));
assert.ok(sql.includes("after update on public.onexa_business_documents"));
assert.ok(sql.includes("with (security_invoker = true)"));
assert.match(sql, /regexp_count\(_definition, _pattern, 1, 'i'\)/);
assert.match(sql, /regexp_count\(_definition, _policy_pattern, 1, 'i'\)/);
assert.match(sql, /_legacy_guard_count <> 1/);
assert.match(sql, /_policy_guard_count <> 0/);
assert.match(sql, /ONEXA_GATE64_GUARD_DEFINITION_AMBIGUOUS/);
assert.match(sql, /regexp_count\(_patched, _policy_pattern, 1, 'i'\) <> 1/);
assert.match(postcheck, /inbox_security_invoker/);
assert.match(postcheck, /tgenabled <> 'D'/);
assert.match(postcheck, /regexp_count\(/);
assert.doesNotMatch(sql, /if position\('onexa_approval_separation_required' in _definition\) > 0 then[\s\S]*?continue;/,
  "Do not blindly skip on an approval policy marker");
assert.ok(postcheck.includes("all_posting_engines_governed"));
assert.ok(service.includes("can_current_user_post"));
assert.ok(queue.includes("item.can_current_user_post"));
assert.ok(queue.includes("postOnexaProjectCost"));
assert.ok(queue.includes("postOnexaFleetTripCost"));
assert.equal(pkg.scripts["check:gate64-approval-posting-bridge"], "node scripts/check-gate64-approval-posting-bridge.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate64-approval-posting-bridge"));

console.log("Gate 64 approval/posting bridge checks passed ✓");
