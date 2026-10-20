import assert from 'node:assert/strict';
import {audit} from './audit-staging-evidence.mjs';
const prod='a'.repeat(20),stage='b'.repeat(20);
const base={
 production:{project_ref:prod,supabase_url:'https://'+prod+'.supabase.co/',database_write_approval:false},
 staging:{project_ref:stage,supabase_url:'https://'+stage+'.supabase.co/',data_classification:'synthetic_only',database_write_approval:false},
 validation:{separate_auth_users_confirmed:true,tenant_rls_test_passed:true,staging_restore_test_passed:true,finance_mapping_approved:true,release_authorized:false}
};
assert.equal(audit(base).ready,true);
for(const [name,mutate] of [
 ['PROJECT_REFS_NOT_ISOLATED',m=>{m.staging.project_ref=prod;m.staging.supabase_url='https://'+prod+'.supabase.co/';}],
 ['STAGING_PROJECT_EVIDENCE_INVALID',m=>{m.staging.supabase_url='https://example.com/';}],
 ['STAGING_SYNTHETIC_DATA_UNCONFIRMED',m=>{m.staging.data_classification='unknown';}],
 ['TENANT_RLS_TEST_UNCONFIRMED',m=>{m.validation.tenant_rls_test_passed=false;}],
 ['BACKUP_RESTORE_TEST_UNCONFIRMED',m=>{m.validation.staging_restore_test_passed=false;}],
 ['FINANCE_MAPPING_NOT_APPROVED',m=>{m.validation.finance_mapping_approved=false;}],
 ['RELEASE_AUTHORIZATION_MUST_REMAIN_FALSE',m=>{m.validation.release_authorized=true;}],
 ['SECRET_FIELDS_FORBIDDEN',m=>{m.staging.service_role='SAMPLE';}],
 ['DATABASE_WRITES_MUST_REMAIN_UNAPPROVED',m=>{m.production.database_write_approval=true;}]
]){const v=structuredClone(base);mutate(v);assert.ok(audit(v).errors.includes(name),name);}
assert.deepEqual(audit(null).errors,['INVALID_MANIFEST']);
console.log('Gate150: 10 staging isolation/safety test cases passed.');
