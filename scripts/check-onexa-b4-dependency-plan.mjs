import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {validateFinanceDependencyPlan} from "./lib/onexa-b4-dependency-plan.mjs";

const read=path=>readFileSync(path,"utf8");
const manifest=JSON.parse(read("docs/runbooks/onexa-b4-install-dependency-manifest.json"));
const publishers=JSON.parse(read("docs/runbooks/onexa-b4-module-publisher-manifest.json"));
const result=validateFinanceDependencyPlan(manifest,publishers);
assert.equal(result.node_count,17);
assert.equal(result.publisher_count,14);
assert.equal(result.excluded_legacy_gate,"g66");
const sql=read("supabase/manual-packages/onexa_b4_module_dependencies_READ_ONLY.sql");
const flags=read("src/lib/runtime-flags.ts");
const legacy=read("supabase/manual-packages/gate66_maintenance_work_order_costs.sql");
const approval=read("supabase/manual-packages/gate64_approval_posting_bridge.sql");
assert.ok(flags.includes("export const ONEXA_LEGACY_MAINTENANCE_COST_WRITER_ALLOWED = false;") &&
  flags.includes("ONEXA_MAINTENANCE_COST_POSTING_ENABLED =\n  ONEXA_LEGACY_MAINTENANCE_COST_WRITER_ALLOWED &&"),
  "Legacy SaaS maintenance writer must remain OFF even if an operator turns on its flag");
assert.ok(legacy.includes("if to_regclass('public.onexa_tenants') is not null then") &&
  legacy.includes("ONEXA_GATE66_LEGACY_WORK_ORDERS_NOT_SUPPORTED_ON_SAAS"),
  "Legacy Gate66 must refuse the tenant-aware SaaS installation");
for(const signature of [
 "public.onexa_post_sales_invoice(uuid,text)",
 "public.onexa_post_purchase_invoice(uuid,text)",
 "public.onexa_post_customer_receipt(uuid,text)",
 "public.onexa_post_supplier_payment(uuid,text)",
 "public.onexa_post_bank_transfer(uuid,text)",
 "public.onexa_post_project_cost(uuid,text)",
 "public.onexa_post_fleet_trip_cost(uuid,text)"
])assert.ok(approval.includes(signature),
 "G64 source rewrite must be versioned against each required earlier posting module");
assert.ok(approval.includes("_definition := pg_get_functiondef(_oid);"),
 "Gate64 rewrites actual SQL functions and must be treated as a reviewed Staging-only operation");
assert.ok(approval.includes("ONEXA_GATE64_POSTING_ENGINE_REQUIRED"),
 "G64 must halt if its required module publisher is missing");

const q=v=>"'"+v.replace(/'/g,"''")+"'";
for(const n of manifest.nodes){
 const header="("+[q(n.id),n.wave,q(n.policy),q(n.package??""),q(n.depends_on.join(","))].join(",")+")";
 assert.ok(sql.includes(header),"Catalog omitted DAG node "+n.id);
 if(n.package){
  const source=read(n.package) + (n.id==="g37"
    ? read("supabase/migrations/20260902090000_gate7_attendance_payroll_cost_hardening.sql") +
      read("supabase/migrations/20260903090000_gate8_payroll_cost_ledger.sql")
    : "");
  for(const req of n.requires){
   assert.ok(source.includes(req.ref) || (req.kind==="trigger" && source.includes(req.name)),
     "Installed SQL source does not reference metadata prerequisite "+n.id+" / "+req.ref);
   if(req.kind==="column")assert.ok(source.includes(req.column),
     "SQL source does not mention prerequisite scoped column "+req.column);
   if(req.kind==="trigger")assert.ok(source.includes(req.name),
     "SQL source does not mention required approval trigger "+req.name);
  }
  for(const target of n.targets??[]){
   assert.ok(source.includes(target.ref.split("(")[0]),
     "Publisher SQL package missing installed target "+n.id+" / "+target.ref);
  }
 }
 for(const [arr,part] of [[n.requires,"requirements"],[n.targets??[],"targets"]]){
  for(const ref of arr){
   const tuple="("+[q(n.id),q(ref.kind),q(ref.ref),q(ref.column??ref.name??"")].join(",")+")";
   assert.ok(sql.includes(tuple),"Catalog "+part+" differs from financial DAG: "+tuple);
  }
 }
}
for(const expected of [
 "'SAAS_LEGACY_WRITER_FORBIDDEN'","'LEGACY_REAL_ESTATE_COMPAT_REVIEW'",
 "'PAYROLL_GATE7_8_FOUNDATION_REVIEW'",
 "'MANUAL_JOURNAL_ALLOWLIST_BLOCKED'","'PREREQUISITES_MISSING'",
 "'INSTALLATION_MISSING'","'CATALOG_PRESENT_STAGING_REQUIRED'",
 "to_regprocedure(o.object_ref)","to_regclass(o.object_ref)",
 "information_schema.columns","pg_trigger",
 "t.tgenabled<>'D'","to_regclass('public.onexa_tenants')",
])assert.ok(sql.includes(expected),"Source-only catalog omitted safety condition "+expected);
const withoutComments=sql.replace(/^--[^\n]*/gm,"");
const unquoted=withoutComments.replace(/'(?:''|[^'])*'/g,"''");
assert.match(unquoted,/^\s*with\b/i);
assert.equal((unquoted.match(/;/g)||[]).length,1,"Catalog must be one SELECT-only query");
assert.doesNotMatch(unquoted,/\b(?:CREATE|ALTER|DELETE|UPDATE|INSERT|TRUNCATE|DROP|GRANT|REVOKE|EXECUTE|CALL|DO|COPY)\b/i,
 "Financial dependency catalog must not modify production state");
assert.equal(read("docs/runbooks/onexa-b4-module-publisher-manifest.json").includes('"onexa_post_maintenance_work_order_cost"'),true);
console.log("ONEXA module dependency plan passed: "+result.node_count+" gate nodes, "+
 result.publisher_count+" publishers, "+result.waves.length+
 " deployable stages, Gate66 SaaS hard-disabled ✓");
