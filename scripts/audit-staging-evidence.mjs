#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const REF=/^[a-z]{20}$/;
function parseProject(value) {
 try {
  const u=new URL(value);
  const m=u.hostname.match(/^([a-z]{20})\.supabase\.co$/);
  if(u.protocol!=='https:'||!m||u.port||u.username||u.password||u.search||u.hash||u.pathname!=='/')return null;
  return {url:u.origin,ref:m[1]};
 }catch{return null;}
}
export function audit(m) {
 if(!m||typeof m!=='object'||Array.isArray(m))return {ready:false,errors:['INVALID_MANIFEST']};
 const errors=[];
 function secrets(o) {
  if(Array.isArray(o))return o.some(secrets);
  if(o&&typeof o==='object')return Object.entries(o).some(([k,v])=>/^(service_role|anon_key|secret|password|access_token|refresh_token|api_key|authorization|private_key|jwt|connection_string|database_url)$/i.test(k)||secrets(v));
  return false;
 }
 if(secrets(m))errors.push('SECRET_FIELDS_FORBIDDEN');
 const p=parseProject(m.production?.supabase_url),s=parseProject(m.staging?.supabase_url);
 if(!p||!REF.test(m.production?.project_ref||'')||p.ref!==m.production.project_ref)errors.push('PRODUCTION_PROJECT_EVIDENCE_INVALID');
 if(!s||!REF.test(m.staging?.project_ref||'')||s.ref!==m.staging.project_ref)errors.push('STAGING_PROJECT_EVIDENCE_INVALID');
 if(p&&s&&p.ref===s.ref)errors.push('PROJECT_REFS_NOT_ISOLATED');
 if(p&&s&&p.url===s.url)errors.push('PROJECT_URLS_NOT_ISOLATED');
 if(m.staging?.data_classification!=='synthetic_only')errors.push('STAGING_SYNTHETIC_DATA_UNCONFIRMED');
 if(m.staging?.database_write_approval!==false||m.production?.database_write_approval!==false)errors.push('DATABASE_WRITES_MUST_REMAIN_UNAPPROVED');
 for(const [field,error] of [['separate_auth_users_confirmed','SEPARATE_AUTH_USERS_UNCONFIRMED'],['tenant_rls_test_passed','TENANT_RLS_TEST_UNCONFIRMED'],['staging_restore_test_passed','BACKUP_RESTORE_TEST_UNCONFIRMED'],['finance_mapping_approved','FINANCE_MAPPING_NOT_APPROVED']])if(m.validation?.[field]!==true)errors.push(error);
 if(m.validation?.release_authorized!==false)errors.push('RELEASE_AUTHORIZATION_MUST_REMAIN_FALSE');
 return {ready:errors.length===0,errors,scope:'DECLARATIONS_ONLY_NOT_LIVE_VERIFICATION'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
 try {
  if(process.argv.length!==3)throw Error('Usage: node scripts/audit-staging-evidence.mjs manifest.json');
  const result=audit(JSON.parse(readFileSync(process.argv[2],'utf8')));
  console.log(JSON.stringify(result,null,2));
  if(!result.ready)process.exitCode=1;
 }catch(e){console.error(e.message);process.exitCode=2;}
}
