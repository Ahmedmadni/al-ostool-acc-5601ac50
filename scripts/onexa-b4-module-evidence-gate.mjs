#!/usr/bin/env node
// OFFLINE EVIDENCE CHECK ONLY. Never talks to a DB, enables an ONEXA
// feature, changes SQL or grants production approval. A PASS only means
// that 13 supported publisher modules and one explicitly retired SaaS-incompatible
// legacy writer have complete reviewable STAGING evidence records.
import {readFileSync} from "node:fs";
import {resolve} from "node:path";

const source=JSON.parse(readFileSync("docs/runbooks/onexa-b4-module-publisher-manifest.json","utf8"));
const expected=source.modules;
const fields=[
 "maker_checker_approval",
 "account_mapping_verified",
 "exact_money_and_currency",
 "original_gl_receipt_reconciled",
 "unchanged_retry_idempotency",
 "changed_source_revision_control",
 "reversal_contra_reconciled",
 "closed_period_denial",
 "tenant_boundary_and_role_denial",
 "module_owner_approved",
];
function evaluate(catalogFile,attestationFile){
  const rows=readFileSync(resolve(catalogFile),"utf8").trim().split(/\r?\n/);
  const att=JSON.parse(readFileSync(resolve(attestationFile),"utf8"));
  const blockers=[];
  if(att.environment!=="independently_restored_staging")blockers.push("EVIDENCE:independent_restored_staging");
  if(att.feature_flags_disabled!==true)blockers.push("EVIDENCE:feature_flags_must_remain_OFF");
  if(att.modules===null || typeof att.modules!=="object" || Array.isArray(att.modules)){
    throw Error("Malformed module evidence record");
  }
  const observed=new Map();
  for(const row of rows){
    if(!row.trim())continue;
    const parts=row.trim().split("|");
    if(parts.length!==10)throw Error("Catalog row must contain exactly ten fields");
    const [id,gate,rpc,installed,allowlisted,execute,checked,authorized,receipt,status]=parts;
    const entry=expected.find(x=>x.id===id);
    if(!entry || observed.has(id))throw Error("Unknown or duplicate module: "+id);
    if(entry.gate!==gate || entry.rpc!==rpc)throw Error("Module RPC/source contract drift: "+id);
    if(![installed,allowlisted,execute,checked,authorized,receipt].every(x=>x==="t"||x==="f")){
      throw Error("Malformed catalog boolean: "+id);
    }
    observed.set(id,{installed,allowlisted,execute,checked,authorized,receipt,status});
  }
  if(observed.size!==expected.length)throw Error("Missing module catalog entries");
  const evidenceIds=Object.keys(att.modules);
  if(evidenceIds.length!==expected.length ||
    evidenceIds.some(id=>!expected.some(m=>m.id===id))){
    throw Error("Module attestation must cover exactly every publisher");
  }
  const validReference=value=>typeof value==="string" &&
    value.trim().length>=8 &&
    !/^(?:tbd|todo|none|unknown|test)$/i.test(value.trim());
  for(const entry of expected){
    const {id}=entry;
    const c=observed.get(id);
    const ev=att.modules[id];
    if(!ev || typeof ev!=="object" || Array.isArray(ev))throw Error("Invalid module attestation: "+id);
    if(!validReference(ev.evidence_reference)){
      blockers.push("EVIDENCE:"+id+":reviewable_reference");
    }

    // Gate66 has an explicit SQL preflight that REJECTS ONEXA SaaS tenancy.
    // It cannot be accepted as an installed publisher. The only allowed
    // outcome is documented RETIREMENT, with independent native G42 accrual
    // and read-only G74 attribution double-posting reconciliation.
    if(id==="maintenance_work_order_cost"){
      if(c.status!=="MISSING_RPC" || c.installed!=="f" ||
        [c.execute,c.checked,c.authorized,c.receipt].some(x=>x!=="f")){
        blockers.push("CATALOG:maintenance_work_order_cost:legacy_writer_must_remain_uninstalled");
      }
      const legacy=att.legacy_maintenance_retirement;
      if(!legacy || typeof legacy!=="object" || Array.isArray(legacy)){
        blockers.push("EVIDENCE:legacy_maintenance_retirement:missing");
        continue;
      }
      for(const [key,value] of Object.entries({
        mode:"saas_native_attribution_only",
        retired_writer:"g66",
        approved_cost_posting_path:"g42",
        native_attribution_gate:"g74",
        legacy_writer_retired:true,
        source_provenance_reconciled:true,
        double_posting_prevention_verified:true,
        native_tenant_isolation_verified:true,
        finance_approved:true,
        security_approved:true,
      })){
        if(legacy[key]!==value)blockers.push("EVIDENCE:legacy_maintenance_retirement:"+key);
      }
      if(!validReference(legacy.evidence_reference)){
        blockers.push("EVIDENCE:legacy_maintenance_retirement:reviewable_reference");
      }
      continue;
    }

    if(c.status!=="SOURCE_PRESENT_ONLY_STAGING_REQUIRED" ||
      ![c.installed,c.allowlisted,c.execute,c.checked,c.authorized,c.receipt].every(x=>x==="t")){
      blockers.push("CATALOG:"+id+":"+c.status);
    }
    for(const field of fields)if(ev[field]!==true)blockers.push("EVIDENCE:"+id+":"+field);
  }
  return blockers;
}
if(process.argv.length!==4){
 console.error("Usage: node scripts/onexa-b4-module-evidence-gate.mjs modules.psv module-attestation.json");
 process.exit(2);
}
try{
 const blockers=evaluate(process.argv[2],process.argv[3]);
 if(blockers.length){
   console.log("ONEXA MODULE STAGING HOLD ("+blockers.length+" missing/failed source or UAT checks)");
   for(const blocker of blockers)console.log(" - "+blocker);
   process.exitCode=1;
 }else{
   console.log("ONEXA MODULE STAGING EVIDENCE COMPLETE (13 PUBLISHERS + G66 RETIRED) — HUMAN FINANCE/SECURITY REVIEW STILL REQUIRED.");
   console.log("This offline checker DOES NOT deploy, approve production, or enable flags.");
 }
}catch(error){
 console.error("ONEXA MODULE STAGING HOLD: "+error.message);
 process.exitCode=2;
}
