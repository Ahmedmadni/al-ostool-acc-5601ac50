import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

const manifest=JSON.parse(readFileSync("docs/runbooks/onexa-b4-module-publisher-manifest.json","utf8"));
const template=JSON.parse(readFileSync("docs/runbooks/onexa-b4-module-uat-attestation.example.json","utf8"));
assert.equal(manifest.modules.length,14);
const keys=Object.keys(template.modules);
assert.deepEqual(keys,manifest.modules.map(x=>x.id),"UAT template should enumerate every module exactly once");
const tmp=mkdtempSync(join(tmpdir(),"onexa-b4-module-uat-"));
const catalog=join(tmp,"modules.psv");
const evidence=join(tmp,"evidence.json");
const reportRows=()=>manifest.modules.map(m=>[
 m.id,m.gate,m.rpc,
 ...(m.id==="maintenance_work_order_cost"
   ? ["f","t","f","f","f","f","MISSING_RPC"]
   : ["t","t","t","t","t","t","SOURCE_PRESENT_ONLY_STAGING_REQUIRED"])
].join("|")).join("\n")+"\n";
const run=()=>spawnSync(process.execPath,
 ["scripts/onexa-b4-module-evidence-gate.mjs",catalog,evidence],
 {encoding:"utf8"});
try{
 writeFileSync(catalog,reportRows());
 writeFileSync(evidence,JSON.stringify(template));
 let r=run();
 assert.equal(r.status,1,"Unattested Staging must HOLD");
 assert.match(r.stdout,/ONEXA MODULE STAGING HOLD/);

 const approved=structuredClone(template);
 approved.environment="independently_restored_staging";
 for(const mod of Object.values(approved.modules)){
   mod.evidence_reference="SYNTHETIC-FINANCE-UAT-EVIDENCE-NOT-REAL";
   for(const key of Object.keys(mod))if(typeof mod[key]==="boolean")mod[key]=true;
 }
 approved.legacy_maintenance_retirement.mode="saas_native_attribution_only";
 approved.legacy_maintenance_retirement.evidence_reference="SYNTHETIC-NATIVE-G42-G74-FINANCE-RECONCILIATION";
 for(const key of Object.keys(approved.legacy_maintenance_retirement)){
   if(typeof approved.legacy_maintenance_retirement[key]==="boolean"){
     approved.legacy_maintenance_retirement[key]=true;
   }
 }
 writeFileSync(evidence,JSON.stringify(approved));
 r=run();
 assert.equal(r.status,0,"Synthetic complete reviewer attestations should exercise parser PASS");
 assert.match(r.stdout,/HUMAN FINANCE\/SECURITY REVIEW STILL REQUIRED/);
 assert.match(r.stdout,/13 PUBLISHERS \+ G66 RETIRED/);

 approved.legacy_maintenance_retirement.double_posting_prevention_verified=false;
 writeFileSync(evidence,JSON.stringify(approved));
 r=run();
 assert.equal(r.status,1,"Unproven G42/G74 double-posting prevention must HOLD");
 assert.match(r.stdout,/EVIDENCE:legacy_maintenance_retirement:double_posting_prevention_verified/);
 approved.legacy_maintenance_retirement.double_posting_prevention_verified=true;
 writeFileSync(evidence,JSON.stringify(approved));

 const forbiddenInstalled=reportRows().replace(
   "maintenance_work_order_cost|g66|onexa_post_maintenance_work_order_cost|f|t|f|f|f|f|MISSING_RPC",
   "maintenance_work_order_cost|g66|onexa_post_maintenance_work_order_cost|t|t|t|t|t|t|SOURCE_PRESENT_ONLY_STAGING_REQUIRED"
 );
 writeFileSync(catalog,forbiddenInstalled);
 r=run();
 assert.equal(r.status,1,"Installing SaaS-forbidden legacy Gate66 must NEVER be accepted");
 assert.match(r.stdout,/CATALOG:maintenance_work_order_cost:legacy_writer_must_remain_uninstalled/);
 writeFileSync(catalog,reportRows());

 approved.legacy_maintenance_retirement.mode="UNAPPROVED";
 writeFileSync(evidence,JSON.stringify(approved));
 r=run();
 assert.equal(r.status,1,"Unsupported legacy maintenance mode must HOLD");
 approved.legacy_maintenance_retirement.mode="saas_native_attribution_only";
 writeFileSync(evidence,JSON.stringify(approved));


 const wrongGate=reportRows().replace(
   "manual_journal|g58|onexa_post_manual_journal|t|t|t|t|t|t|SOURCE_PRESENT_ONLY_STAGING_REQUIRED",
   "manual_journal|g58|onexa_post_manual_journal|t|f|t|t|t|t|SOURCE_TYPE_BLOCKED"
 );
 writeFileSync(catalog,wrongGate);
 r=run();
 assert.equal(r.status,1,"Manual GL source type blocker must HOLD");
 assert.match(r.stdout,/CATALOG:manual_journal:SOURCE_TYPE_BLOCKED/);
 writeFileSync(catalog,reportRows());

 const missingRpc=reportRows().replace(
   "payroll_run|g37|onexa_post_payroll_run|t|t|t|t|t|t|SOURCE_PRESENT_ONLY_STAGING_REQUIRED",
   "payroll_run|g37|onexa_post_payroll_run|f|t|f|f|f|f|MISSING_RPC"
 );
 writeFileSync(catalog,missingRpc);
 assert.equal(run().status,1,"Missing payroll must HOLD");
 writeFileSync(catalog,reportRows());

 approved.modules.sales_invoice.changed_source_revision_control=false;
 writeFileSync(evidence,JSON.stringify(approved));
 r=run();
 assert.equal(r.status,1,"Missing source-revision UAT blocks module release");
 assert.match(r.stdout,/EVIDENCE:sales_invoice:changed_source_revision_control/);
 approved.modules.sales_invoice.changed_source_revision_control=true;
 writeFileSync(evidence,JSON.stringify(approved));

 approved.modules.lease_receipt.evidence_reference="";
 writeFileSync(evidence,JSON.stringify(approved));
 assert.equal(run().status,1,"Unreviewable evidence ref must HOLD");
 approved.modules.lease_receipt.evidence_reference="SYNTHETIC-FINANCE-UAT-EVIDENCE-NOT-REAL";
 writeFileSync(evidence,JSON.stringify(approved));

 approved.feature_flags_disabled=false;
 writeFileSync(evidence,JSON.stringify(approved));
 assert.equal(run().status,1,"Enabling finance flags before acceptance must HOLD");
 approved.feature_flags_disabled=true;
 approved.environment="production";
 writeFileSync(evidence,JSON.stringify(approved));
 assert.equal(run().status,1,"Production environment may never pass a Staging-only evidence gate");

 approved.environment="independently_restored_staging";
 writeFileSync(evidence,JSON.stringify(approved));
 writeFileSync(catalog,reportRows().replace("t|t|t|t|t|t|","t|incorrect|t|t|t|t|"));
 assert.equal(run().status,2,"Malformed module catalog booleans must fail closed");
 writeFileSync(catalog,reportRows().split("\n").filter(x=>!x.startsWith("lease_invoice|")).join("\n"));
 assert.equal(run().status,2,"Missing module catalog row must fail closed");

 console.log("ONEXA offline module UAT gate: 13 publishers + one explicitly retired legacy Gate66, missing RPC, source block, missing approval, bad env and malformed evidence ✓");
} finally {
 rmSync(tmp,{recursive:true,force:true});
}
