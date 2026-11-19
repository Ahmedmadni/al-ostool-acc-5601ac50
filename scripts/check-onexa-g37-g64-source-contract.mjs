import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const read=p=>readFileSync(p,"utf8");
const checks=JSON.parse(read("docs/runbooks/onexa-g37-g64-prerequisite-contract.json"));
const payrollCatalog=read("supabase/manual-packages/onexa_g37_g64_chain_READ_ONLY.sql");
const guardCatalog=read("supabase/manual-packages/onexa_g64_patch_guard_READ_ONLY.sql");
const sourceG7=read("supabase/migrations/20260902090000_gate7_attendance_payroll_cost_hardening.sql");
const sourceG8=read("supabase/migrations/20260903090000_gate8_payroll_cost_ledger.sql");
const sourceG37=read("supabase/manual-packages/gate37_payroll_gl_posting.sql");
const sourceG64=read("supabase/manual-packages/gate64_approval_posting_bridge.sql");
const canonicalG64=read("supabase/manual-packages/onexa_gate64_readonly_preflight.sql");
const dependencyPlan=JSON.parse(read("docs/runbooks/onexa-b4-install-dependency-manifest.json"));
const dependencyAudit=read("supabase/manual-packages/onexa_b4_module_dependencies_READ_ONLY.sql");
const gateNode=dependencyPlan.nodes.find(x=>x.id==="g37");
assert.equal(checks.schema_version,1);
assert.equal(checks.checks.length,35);
assert.equal(gateNode.policy,"payroll_gate7_8_compatibility_review");
assert.ok(dependencyAudit.includes("'PAYROLL_GATE7_8_FOUNDATION_REVIEW'"));
const seen=new Set();
const sqlQuote=s=>"'"+s.replaceAll("'","''")+"'";
for(const item of checks.checks){
  const key=item.stage+":"+item.id;
  assert.ok(!seen.has(key),"Duplicate payroll/approval catalog identity "+key);
  seen.add(key);
  const row="("+[item.stage,item.id,item.kind,item.ref,item.extra].map(sqlQuote).join(",")+")";
  assert.ok(payrollCatalog.includes(row),"Catalog SQL omitted preflight "+key);
  const expectedSources=item.stage.startsWith("G7")
    ? [sourceG7,sourceG8]
    : item.stage.startsWith("G8")
      ? [sourceG8]
      : item.stage.startsWith("G37")
        ? [sourceG37]
        : [sourceG64,sourceG7,sourceG8];
  assert.ok(expectedSources.some(source=>source.includes(item.ref) ||
      source.includes(item.ref.split("(")[0]) ||
      ((item.kind==="trigger"||item.kind==="column") && source.includes(item.extra))),
    "Recorded expected prerequisite missing in actual source packages: "+key);
  if(item.stage.startsWith("G7") || item.stage.startsWith("G8")){
    // Gate37's actual SQL only checks stale/finance employer helper signatures.
    // Supplemental Gate7/8 lineage probes prevent treating two fake helpers
    // as a complete payroll/attendance implementation in a SaaS deployment.
    if(item.kind!=="trigger" && item.kind!=="column" &&
       (item.ref.includes("hr_attendance") || item.ref.includes("cost_period") ||
        item.ref.includes("hr_payroll_employer") || item.ref.includes("hr_sync_payroll_cost"))){
      assert.ok(gateNode.requires.some(r=>r.ref===item.ref) ||
        [ "public.hr_sync_payroll_cost_entries(uuid)" ].includes(item.ref),
        "Payroll lineage audit must be coupled to finance dependency gate "+key);
    }
  }
}
for(const [stage,expected] of [
 ["G7_PRE",9],["G7_INST",10],["G8_PRE",1],["G8_INST",1],
 ["G37_INST",3],["G64_PRE",11],
]){
  assert.equal(checks.checks.filter(x=>x.stage===stage).length,expected,
    "Unexpected audited migration section: "+stage);
}
const a=canonicalG64.indexOf("with engines(gate,function_signature,record_name) as");
const b=canonicalG64.indexOf("-- PostgreSQL CREATE OR REPLACE VIEW",a);
assert.ok(a>0&&b>a);
const authoritative=canonicalG64.slice(a,b).trim();
const expectedGuard=authoritative.replace(
 "select gate,function_signature,legacy_guard_count,policy_guard_count,",
 "select gate,function_signature,legacy_guard_count,policy_guard_count,\n  md5(function_source) as installed_definition_md5,",
);
assert.ok(guardCatalog.includes(expectedGuard),
 "Standalone Gate64 SQL must use exactly the authoritative legacy/policy regex rules");
assert.ok(sourceG64.includes("ONEXA_GATE64_GUARD_DEFINITION_AMBIGUOUS") &&
  sourceG64.includes("ONEXA_GATE64_POSTING_ENGINE_REQUIRED") &&
  sourceG64.includes("regexp_replace(_definition, _pattern, _replacement, 'i')"),
  "Gate64 actual SQL must stop on ambiguous or absent source functions");
for(const [source,name] of [
 [payrollCatalog,"Payroll foundation"],
 [guardCatalog,"Gate64 regex source"],
]){
  const noComments=source.replace(/^--.*$/gm,"").replace(/'(?:''|[^'])*'/g,"''");
  assert.match(noComments,/^\s*with\b/i,name+" catalog must be one CTE");
  assert.equal((noComments.match(/;/g)||[]).length,1,name+" catalog must contain exactly one SQL statement");
  assert.doesNotMatch(noComments,/\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|EXECUTE|DO|CALL|COPY|COMMIT|ROLLBACK)\b/i,
    name+" catalog may not modify the hosted database");
}
const fixture=read("scripts/sql-fixtures/onexa-g37-g64-catalog-smoke.sh");
assert.ok(fixture.includes("ONEXA_G37_G64_CATALOG_DISPOSABLE_ONLY") &&
 fixture.includes("onexa_g37_g64_chain_READ_ONLY.sql") &&
 fixture.includes("onexa_g64_patch_guard_READ_ONLY.sql") &&
 fixture.includes("FOUNDATION:G7_PRE:attendance_periods") &&
 fixture.includes("G64:MISSING:G42:"),
 "PostgreSQL CI must execute the exact operator read-only queries and demand HOLD");
const gate=read("scripts/onexa-g37-g64-foundation-gate.mjs");
assert.ok(gate.includes("ONEXA G7/G8/G37/G64 CATALOG CHECKS PRESENT") &&
 gate.includes("NO PRODUCTION OR FINANCE APPROVAL"),
 "Positive structural parser result must never authorize production");
console.log("ONEXA G37/G64 source contracts passed: 35 real Gate7/8/37/64 prerequisites, exact Gate64 guard parity, SELECT-only catalog ✓");
