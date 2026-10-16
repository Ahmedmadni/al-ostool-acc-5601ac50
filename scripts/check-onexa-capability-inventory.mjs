import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const inventory = read("supabase/manual-packages/onexa_erp_capability_inventory_readonly.sql");
const leasePreflight = read("supabase/manual-packages/lease_gates_67_70_readonly_preflight.sql");
const financePreflight = read("supabase/manual-packages/onexa_gate40_43_readonly_preflight.sql");
const liveAudit = read("docs/runbooks/tenant001-live-activation-audit-2026-10-15.md");
const runbook = read("docs/runbooks/onexa-lease-gates-67-70-rollout.md");

// This is a structural assertion, not a substitute for executing read-only
// diagnostics against the customer's actual database and running smoke tests.
for (const [gate, object] of [
  ["CORE", "public.onexa_workspace"],
  ["CORE", "public.onexa_post_journal("],
  ["G15", "public.re_properties"],
  ["G35", "public.onexa_post_sales_invoice("],
  ["G36", "public.onexa_post_purchase_invoice("],
  ["G39", "public.onexa_post_customer_receipt("],
  ["G40", "public.onexa_post_supplier_payment("],
  ["G41", "public.onexa_post_bank_transfer("],
  ["G42", "public.onexa_post_project_cost("],
  ["G43", "public.onexa_post_fleet_trip_cost("],
  ["G58", "public.onexa_post_manual_journal("],
  ["G60", "public.onexa_activate_accountant_user("],
  ["G62", "public.onexa_approval_workflows"],
  ["G63", "public.onexa_approval_instances"],
  ["G64", "onexa_private.guard_approval_posting()"],
  ["G65", "public.onexa_post_inventory_document("],
  ["G66", "public.ops_work_orders"],
  ["G67", "public.onexa_post_lease_invoice("],
  ["G68", "public.onexa_lease_schedule_dashboard()"],
  ["G69", "public.onexa_lease_property_financial_report("],
  ["G70", "public.onexa_lease_receivables_aging("],
  ["G71", "public.onexa_company_module_scopes"],
  ["G71", "public.onexa_has_company_module_access("],
]) {
  assert.ok(inventory.includes("'" + gate + "'") && inventory.includes(object),
    "Missing feature inventory checkpoint: " + gate + " " + object);
}
for (const sql of [inventory, leasePreflight, financePreflight]) {
  assert.doesNotMatch(sql,
    /^\s*(?:begin|commit|create|alter|drop|truncate|insert|update|delete|grant|revoke|do|call)\b/im,
    "A production inventory query must never contain SQL mutation statements");
  assert.match(sql, /to_reg(class|procedure)\(/, "Presence queries must be fail-safe");
}
assert.match(inventory, /ACCEPTANCE_NOT_VERIFIED/);
for (const gate of ["G40", "G41", "G42", "G43"]) {
  assert.ok(financePreflight.includes("'" + gate + "'"), "Missing finance preflight gate " + gate);
}
assert.match(financePreflight, /PERMISSIONS_MAPPINGS_AND_SMOKE_NOT_VERIFIED/);
assert.match(liveAudit, /14 installed objects, 15 missing objects/);
assert.match(liveAudit, /Gate 67–70 readiness/);
assert.match(runbook, /Gate 68 immutability smoke must FAIL/);
console.log("ONEXA capability inventory checks passed");
