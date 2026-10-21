import assert from 'node:assert/strict';
import { stagingTarget, probeStaging } from './probe-staging-health.mjs';
const p='a'.repeat(20), s='b'.repeat(20);
const manifest={
 production:{project_ref:p,supabase_url:'https://'+p+'.supabase.co/',database_write_approval:false},
 staging:{project_ref:s,supabase_url:'https://'+s+'.supabase.co/',data_classification:'synthetic_only',database_write_approval:false},
 validation:{separate_auth_users_confirmed:true,tenant_rls_test_passed:true,staging_restore_test_passed:true,finance_mapping_approved:true,release_authorized:false}
};
assert.equal(stagingTarget(manifest).allowed,true);
let requests=0;
const fake=async(url, options)=>{
 requests++;
 assert.equal(url,'https://'+s+'.supabase.co/auth/v1/health');
 assert.equal(options.method,'GET');
 assert.equal(options.redirect,'manual');
 assert.equal(options.credentials,'omit');
 assert.equal(options.headers.Accept,'application/json');
 assert.equal(options.headers.Authorization,undefined);
 return {status:200};
};
assert.equal((await probeStaging(manifest,fake)).status,'reachable');
assert.equal(requests,1);
const unsafe=structuredClone(manifest);
unsafe.staging.project_ref=p;
unsafe.staging.supabase_url=unsafe.production.supabase_url;
assert.equal((await probeStaging(unsafe,fake)).status,'blocked');
assert.equal(requests,1);
const missing=structuredClone(manifest);
missing.validation.tenant_rls_test_passed=false;
assert.equal((await probeStaging(missing,fake)).status,'blocked');
assert.equal(requests,1);
assert.equal((await probeStaging(manifest,async()=>({status:401}))).status,'unverified');
assert.equal((await probeStaging(manifest,async()=>{throw Error('network');})).status,'unreachable');
assert.equal((await probeStaging(manifest,async()=>({status:204}))).status,'unverified');
assert.equal((await probeStaging(manifest,async()=>({status:302}))).status,'unverified');
console.log('Staging-only preflight tests passed: GET-only, zero credentials, fail-closed, error/401 paths.');
