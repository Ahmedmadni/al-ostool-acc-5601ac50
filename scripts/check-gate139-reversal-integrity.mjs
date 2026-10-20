import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const sql=read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow=read('.github/workflows/native-tenant-sql-smoke.yml');
for(const key of ['SMOKE_G136_REVERSAL_LOST_DECISION_JOURNAL_LINK','SMOKE_G137_REVERSAL_DUPLICATED_APPROVAL','SMOKE_G138_REVERSAL_RECONCILIATION_STATE_MISMATCH','SMOKE_G133_REVERSAL_CHANGED_COMPLETED_APPROVAL'])assert.ok(sql.includes(key),key);
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
assert.match(sql,/rollback;\s*select/i);
console.log('Gate139 reversal audit/reconciliation contract verified.');
