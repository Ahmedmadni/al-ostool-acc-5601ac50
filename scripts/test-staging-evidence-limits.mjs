import assert from 'node:assert/strict';
import {audit} from './audit-staging-evidence.mjs';
import {writeFileSync,unlinkSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const oversized={production:{},staging:{},validation:{},padding:'x'.repeat(17000)};
assert.ok(audit(oversized).errors.includes('EVIDENCE_TOO_LARGE'));
const path='/tmp/onexa-evidence-oversized-fixture.json';
try{
 writeFileSync(path,JSON.stringify(oversized));
 const processResult=spawnSync(process.execPath,['scripts/audit-staging-evidence.mjs',path],{encoding:'utf8'});
 assert.equal(processResult.status,2);
 assert.match(processResult.stderr,/EVIDENCE_FILE_TOO_LARGE/);
}finally{unlinkSync(path);}
console.log('Gate158: oversized evidence denied by both library and CLI');
