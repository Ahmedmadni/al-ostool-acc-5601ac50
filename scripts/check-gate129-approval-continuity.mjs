import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const s=read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow=read('.github/workflows/native-tenant-sql-smoke.yml');
for(const marker of ['SMOKE_G126_POSTER_AUDIT_ACTOR_MISMATCH','SMOKE_G127_POSTING_LEFT_PENDING_APPROVAL','SMOKE_G128_REVERSAL_MUTATED_APPROVAL_ACTOR','SMOKE_G93_DUPLICATED_POST_DECISION','SMOKE_G98_REVERSAL_ERASED_POSTING_AUDIT']) assert.ok(s.includes(marker),marker);
assert.match(s,/rollback;\s*select/i);
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
console.log('Gate129 approval continuity source assertions passed');
