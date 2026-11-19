import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

const c=JSON.parse(readFileSync("docs/runbooks/onexa-g37-g64-prerequisite-contract.json","utf8"));
const engines=[
 ["G35","public.onexa_post_sales_invoice(uuid,text)"],
 ["G36","public.onexa_post_purchase_invoice(uuid,text)"],
 ["G39","public.onexa_post_customer_receipt(uuid,text)"],
 ["G40","public.onexa_post_supplier_payment(uuid,text)"],
 ["G41","public.onexa_post_bank_transfer(uuid,text)"],
 ["G42","public.onexa_post_project_cost(uuid,text)"],
 ["G43","public.onexa_post_fleet_trip_cost(uuid,text)"],
];
const dir=mkdtempSync(join(tmpdir(),"onexa-g37-g64-"));
const f1=join(dir,"payroll.psv"),f2=join(dir,"g64.psv");
const run=()=>spawnSync(process.execPath,["scripts/onexa-g37-g64-foundation-gate.mjs",f1,f2],{encoding:"utf8"});
const lines=()=>c.checks.map(x=>[x.stage,x.id,x.kind,x.ref,x.extra,"t","PRESENT_NOT_FINANCE_APPROVED"].join("|")).join("\n")+"\n";
const bridge=()=>engines.map(([gate,sig])=>[gate,sig,"1","0","a".repeat(32),"ONE_GUARD_PATCHABLE"].join("|")).join("\n")+"\n";
try{
 assert.equal(c.checks.length,35,"Stage13 checks must remain exact and source-pinned");
 writeFileSync(f1,lines());
 writeFileSync(f2,bridge());
 let r=run();
 assert.equal(r.status,0,"Synthetic fully installed catalog must pass structural parser");
 assert.match(r.stdout,/NO PRODUCTION OR FINANCE APPROVAL/);

 const scenarios=[
  ["G7 missing",lines().replace("G7_PRE|attendance_periods|relation|public.hr_attendance_periods||t|PRESENT_NOT_FINANCE_APPROVED",
    "G7_PRE|attendance_periods|relation|public.hr_attendance_periods||f|MISSING_HOLD"),"FOUNDATION:G7_PRE:attendance_periods"],
  ["G8 missing",lines().replace("G8_INST|employer_cost_fn|function|public.hr_payroll_employer_cost(numeric,numeric,numeric,numeric,numeric,numeric,numeric)||t|PRESENT_NOT_FINANCE_APPROVED",
    "G8_INST|employer_cost_fn|function|public.hr_payroll_employer_cost(numeric,numeric,numeric,numeric,numeric,numeric,numeric)||f|MISSING_HOLD"),"FOUNDATION:G8_INST:employer_cost_fn"],
  ["G37 missing",lines().replace("G37_INST|payroll_journal_rpc|function|public.onexa_post_payroll_run(uuid,uuid,uuid,text)||t|PRESENT_NOT_FINANCE_APPROVED",
    "G37_INST|payroll_journal_rpc|function|public.onexa_post_payroll_run(uuid,uuid,uuid,text)||f|MISSING_HOLD"),"FOUNDATION:G37_INST:payroll_journal_rpc"],
 ];
 for(const [name,fixture,match] of scenarios){
  assert.notEqual(fixture,lines(),name+" fixture must actually change");
  writeFileSync(f1,fixture);
  r=run();
  assert.equal(r.status,1,name+" must HOLD");
  assert.ok(r.stdout.includes(match),name+" must identify its exact failing prerequisite");
 }
 writeFileSync(f1,lines());
 let broken=bridge().replace(
  "G42|public.onexa_post_project_cost(uuid,text)|1|0|"+("a".repeat(32))+"|ONE_GUARD_PATCHABLE",
  "G42|public.onexa_post_project_cost(uuid,text)||||MISSING");
 assert.notEqual(broken,bridge());
 writeFileSync(f2,broken);
 r=run();
 assert.equal(r.status,1,"Missing Gate64 publisher must HOLD");
 assert.match(r.stdout,/G64:MISSING:G42:/);
 broken=bridge().replace(
  "G35|public.onexa_post_sales_invoice(uuid,text)|1|0|",
  "G35|public.onexa_post_sales_invoice(uuid,text)|2|0|");
 writeFileSync(f2,broken);
 assert.equal(run().status,2,"Guard status/count contradiction must fail closed");
 broken=bridge().replace(
  "G35|public.onexa_post_sales_invoice(uuid,text)|1|0|",
  "G35|public.onexa_post_sales_invoice(uuid,text)|0|0|")
 .replace("G35|public.onexa_post_sales_invoice(uuid,text)|0|0|"+("a".repeat(32))+"|ONE_GUARD_PATCHABLE",
  "G35|public.onexa_post_sales_invoice(uuid,text)|0|0|"+("a".repeat(32))+"|GUARD_MISMATCH_REVIEW_REQUIRED");
 writeFileSync(f2,broken);
 r=run();assert.equal(r.status,1,"Ambiguous Gate64 rewrite must HOLD");
 assert.match(r.stdout,/G64:SOURCE_DRIFT:G35:/);
 writeFileSync(f2,bridge());
 writeFileSync(f1,lines().replace("G7_PRE|attendance_days","G7_PRE|renamed_days"));
 assert.equal(run().status,2,"Unreviewed prerequisite name must fail closed");
 writeFileSync(f1,lines());
 writeFileSync(f2,bridge().replace("a".repeat(32),"invalid-hash"));
 assert.equal(run().status,2,"Unverifiable source hash must fail closed");
 console.log("Payroll G7/G8/G37 and Gate64 offline stage checks passed: 35 preflights, 7 guards, malformed/source drift denial ✓");
}finally{rmSync(dir,{recursive:true,force:true});}
