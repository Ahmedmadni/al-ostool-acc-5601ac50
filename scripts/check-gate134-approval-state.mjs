import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const sql=read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow=read('.github/workflows/native-tenant-sql-smoke.yml');
for(const marker of ['SMOKE_G131_DENIED_POST_CHANGED_APPROVAL','SMOKE_G132_DENIED_POST_CHANGED_DOCUMENT','SMOKE_G133_REVERSAL_CHANGED_COMPLETED_APPROVAL','SMOKE_G127_POSTING_LEFT_PENDING_APPROVAL','SMOKE_G128_REVERSAL_MUTATED_APPROVAL_ACTOR']) assert.ok(sql.includes(marker),'Missing approval-state assertion: '+marker);
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
assert.match(sql,/rollback;\s*select/i);
console.log('Gate134 approval transition and rollback regression guard passed');
