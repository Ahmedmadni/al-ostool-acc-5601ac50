import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const sql=read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow=read('.github/workflows/native-tenant-sql-smoke.yml');
for(const k of ['SMOKE_G141_REVERSAL_POSTING_LINK_LOST','SMOKE_G142_REVERSAL_DOCUMENT_JOURNAL_CHANGED','SMOKE_G143_REVERSAL_LOST_BALANCED_HISTORICAL_JOURNAL','SMOKE_G138_REVERSAL_RECONCILIATION_STATE_MISMATCH'])assert.ok(sql.includes(k),'Missing reversal invariant '+k);
assert.match(sql,/rollback;\s*select/i);
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
console.log('Gate144 historical reversed-journal integrity contract verified.');
