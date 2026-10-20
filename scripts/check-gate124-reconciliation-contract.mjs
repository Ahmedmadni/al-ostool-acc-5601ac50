import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const sql=read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow=read('.github/workflows/native-tenant-sql-smoke.yml');
for(const marker of ['SMOKE_G121_REVIEWED_SOURCE_LINK_MISMATCH','SMOKE_G122_FOREIGN_RECONCILIATION_VISIBLE','SMOKE_G123_REVERSAL_SOURCE_HISTORY_LOST','SMOKE_G107_REVERSED_JOURNAL_REPOST_ALLOWED','SMOKE_G98_REVERSAL_ERASED_SOURCE_EVIDENCE']){
 assert.ok(sql.includes(marker), 'Missing finance reconciliation safeguard: '+marker);
}
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
assert.match(sql,/rollback;\s*select/i);
console.log('Gate124: Gate42/G64 reconciliation isolation, audit and rollback assertions preserved.');
