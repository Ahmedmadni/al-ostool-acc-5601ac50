#!/usr/bin/env node
// OFFLINE / read-only report validator: no DB connection, migrations, flags,
// approvals or production writes. "PASS" means the catalog definitions are
// internally present only, never finance authorization to post or deploy.
import {readFileSync} from "node:fs";

const contract=JSON.parse(readFileSync("docs/runbooks/onexa-g37-g64-prerequisite-contract.json","utf8"));
const expected=contract.checks;
const guards=[
 ["G35","public.onexa_post_sales_invoice(uuid,text)"],
 ["G36","public.onexa_post_purchase_invoice(uuid,text)"],
 ["G39","public.onexa_post_customer_receipt(uuid,text)"],
 ["G40","public.onexa_post_supplier_payment(uuid,text)"],
 ["G41","public.onexa_post_bank_transfer(uuid,text)"],
 ["G42","public.onexa_post_project_cost(uuid,text)"],
 ["G43","public.onexa_post_fleet_trip_cost(uuid,text)"],
];

function readRows(path,width){
 const map=new Map();
 const s=readFileSync(path,"utf8").trim();
 for(const line of s.split(/\r?\n/)){
  if(!line)continue;
  const row=line.split("|");
  if(row.length!==width)throw Error("Unexpected catalog column count: "+path);
  const key=row.slice(0,2).join(":");
  if(map.has(key))throw Error("Duplicate source catalog identity: "+key);
  map.set(key,row);
 }
 return map;
}
function verify(payrollFile,bridgeFile){
 const blocked=[];
 const chain=readRows(payrollFile,7);
 if(chain.size!==expected.length)throw Error("Missing or extra G7/G8/G37/G64 prerequisite checks");
 for(const item of expected){
   const key=item.stage+":"+item.id;
   const row=chain.get(key);
   if(!row)throw Error("Missing prerequisite: "+key);
   const [stage,id,kind,ref,extra,present,state]=row;
   if(stage!==item.stage||id!==item.id||kind!==item.kind||ref!==item.ref||
      extra!==item.extra)throw Error("Altered prerequisite metadata: "+key);
   if(present!=="t"&&present!=="f")throw Error("Bad prerequisite Boolean: "+key);
   if(state!==(present==="t"?"PRESENT_NOT_FINANCE_APPROVED":"MISSING_HOLD"))
     throw Error("Inconsistent prerequisite state: "+key);
   if(present!=="t")blocked.push("FOUNDATION:"+key);
 }
 const observed=readRows(bridgeFile,6);
 if(observed.size!==guards.length)throw Error("Missing or extra Gate64 posting engine guards");
 for(const [gate,signature] of guards){
  const key=gate+":"+signature;
  const row=observed.get(key);
  if(!row)throw Error("Missing Gate64 engine: "+key);
  const [,,legacy,policy,hash,status]=row;
  if(!["MISSING","ONE_GUARD_PATCHABLE","ALREADY_POLICY_AWARE","GUARD_MISMATCH_REVIEW_REQUIRED"].includes(status))
    throw Error("Unexpected Gate64 guard status: "+key);
  if(status==="MISSING"){
    if(legacy!==""||policy!==""||hash!=="")throw Error("Malformed missing engine: "+key);
    blocked.push("G64:MISSING:"+key);
  }else{
    if(!/^[a-f0-9]{32}$/.test(hash))throw Error("Unverifiable source checksum: "+key);
    const a=Number(legacy),b=Number(policy);
    if(!/^\d+$/.test(legacy)||!/^\d+$/.test(policy))throw Error("Malformed guard counts: "+key);
    if(status==="ONE_GUARD_PATCHABLE"&&(a!==1||b!==0))
      throw Error("Unsafe mismatched legacy guard counts: "+key);
    if(status==="ALREADY_POLICY_AWARE"&&(a!==0||b!==1))
      throw Error("Unsafe mismatched policy guard counts: "+key);
    if(status==="GUARD_MISMATCH_REVIEW_REQUIRED")blocked.push("G64:SOURCE_DRIFT:"+key);
  }
 }
 return blocked;
}
if(process.argv.length!==4){
 console.error("Usage: node scripts/onexa-g37-g64-foundation-gate.mjs chain.psv guard.psv");
 process.exit(2);
}
try{
 const blocked=verify(process.argv[2],process.argv[3]);
 if(blocked.length){
   console.log("ONEXA PAYROLL/G64 STAGING HOLD ("+blocked.length+" source/catalog blockers)");
   for(const s of blocked)console.log(" - "+s);
   process.exitCode=1;
 }else{
   console.log("ONEXA G7/G8/G37/G64 CATALOG CHECKS PRESENT — NO PRODUCTION OR FINANCE APPROVAL.");
   console.log("Restore-independent Staging, full ledger UAT, manual SQL and signed change control still required.");
 }
}catch(error){
 console.error("ONEXA PAYROLL/G64 STAGING HOLD: "+error.message);
 process.exitCode=2;
}
