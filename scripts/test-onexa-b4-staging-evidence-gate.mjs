import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const catalogCodes = [
  "B4_POST_RETRY_CONTENT_GUARD",
  "B4_PRIVATE_POST_NOT_DIRECTLY_EXECUTABLE",
  "B4_PRIVATE_REVERSE_NOT_DIRECTLY_EXECUTABLE",
  "B4_REVERSE_RETRY_CONTENT_GUARD",
  "B4_STRICT_MONEY_CHECKS",
  "G58_AMENDMENT_FUNCTION_INSTALLED",
  "G58_POST_REAL_GL_RECEIPT_VALIDATION",
  "G58_REVERSE_REPLAY_GL_VALIDATION",
  "G58_TABLE_RLS_ENABLED",
  "GL_HEADER_EXACTLY_BALANCED",
  "GL_MANUAL_SOURCE_ALLOWED"
];
const audit = readFileSync("supabase/manual-packages/onexa_b4_ledger_integrity_READ_ONLY.sql", "utf8");
const checks = Array.from(audit.matchAll(/^\s*\('([A-Z_]+)', '(?:BLOCK|REVIEW)'\),?$/gm), x=>x[1]);
assert.equal(checks.length, 17, "Mock acceptance must follow all actual audit categories");
const severities = new Map(Array.from(audit.matchAll(
  /^\s*\('([A-Z_]+)', '(BLOCK|REVIEW)'\),?$/gm), x => [x[1],x[2]]
));
const template = JSON.parse(readFileSync("docs/runbooks/onexa-b4-staging-attestation.example.json","utf8"));
const tmp = mkdtempSync(join(tmpdir(),"onexa-staging-gate-"));
const cat=join(tmp,"catalog.psv"), gl=join(tmp,"gl.psv"), evidence=join(tmp,"attestation.json");
const testGate = () => spawnSync(process.execPath,[
  "scripts/onexa-b4-staging-evidence-gate.mjs",cat,gl,evidence
],{encoding:"utf8"});
const catalogRows=()=>catalogCodes.map(code=>code+"|READY").join("\n")+"\n";
const cleanRows=()=>checks.map(code=>code+"|"+severities.get(code)+"|0").join("\n")+"\n";

try {
  writeFileSync(cat,catalogRows());
  writeFileSync(gl,cleanRows());
  writeFileSync(evidence,JSON.stringify(template));
  let r=testGate();
  assert.equal(r.status,1,"An unsigned staging review cannot pass");
  assert.match(r.stdout,/ONEXA STAGING RELEASE HOLD/);

  const approved=Object.fromEntries(Object.entries(template).map(([key,value]) =>
    [key,typeof value==="boolean"?true:value]
  ));
  approved.environment="independently_restored_staging";
  writeFileSync(evidence,JSON.stringify(approved));
  r=testGate();
  assert.equal(r.status,0,"SYNTHETIC positive evidence should pass gate parser");
  assert.match(r.stdout,/HUMAN FINANCE\/SECURITY RELEASE REVIEW STILL REQUIRED/);

  writeFileSync(cat,catalogRows().replace("B4_REVERSE_RETRY_CONTENT_GUARD|READY",
    "B4_REVERSE_RETRY_CONTENT_GUARD|HOLD"));
  r=testGate();
  assert.equal(r.status,1,"One unpatched B4 reversal must block staged activation");
  assert.match(r.stdout,/CATALOG:B4_REVERSE_RETRY_CONTENT_GUARD/);
  writeFileSync(cat,catalogRows());

  writeFileSync(gl,cleanRows().replace("HEADER_WITHOUT_REGISTRY|REVIEW|0",
    "HEADER_WITHOUT_REGISTRY|REVIEW|1"));
  r=testGate();
  assert.equal(r.status,1,"Even REVIEW findings require explicit accounting reconciliation");
  assert.match(r.stdout,/LEDGER:HEADER_WITHOUT_REGISTRY\(1\)/);
  writeFileSync(gl,cleanRows());

  writeFileSync(gl,cleanRows().replace("HEADER_IMBALANCED|BLOCK|0",
    "HEADER_IMBALANCED|BLOCK|x"));
  assert.equal(testGate().status,2,"Malformed finance counts must fail closed");
  writeFileSync(gl,cleanRows());

  writeFileSync(cat,catalogRows().replace("GL_MANUAL_SOURCE_ALLOWED|READY\n",""));
  assert.equal(testGate().status,2,"Missing catalog checks cannot silently pass");
  writeFileSync(cat,catalogRows());

  writeFileSync(evidence,JSON.stringify({...approved,feature_flags_disabled:false}));
  assert.equal(testGate().status,1,"Feature flags on before release signoff must block");
  writeFileSync(evidence,JSON.stringify(approved));

  writeFileSync(evidence,JSON.stringify({...approved,environment:"production"}));
  assert.equal(testGate().status,1,"Production-labelled evidence must never pass this stage-only gate");

  console.log("B4 offline Staging gate tests passed: unsigned, incomplete, REVIEW, invalid and production contexts fail closed ✓");
} finally {
  rmSync(tmp,{recursive:true,force:true});
}
