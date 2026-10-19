import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read = path => readFileSync(new URL('../'+path, import.meta.url),'utf8');
const sql = read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow = read('.github/workflows/native-tenant-sql-smoke.yml');
const guards = [
  'SMOKE_G92_DENIED_SELF_POST_CREATED_LEDGER',
  'SMOKE_G93_DUPLICATED_POST_DECISION',
  'SMOKE_G96_POSTING_TOTALS_OR_ENTITY_MISMATCH',
  'SMOKE_G97_APPROVAL_JOURNAL_AUDIT_MISMATCH',
  'SMOKE_G98_REVERSAL_ERASED_POSTING_AUDIT',
  'SMOKE_G98_REVERSAL_ERASED_SOURCE_EVIDENCE',
  'SMOKE_REVERSED_GL_STILL_RECONCILED'
];
for(const key of guards) assert.ok(sql.includes(key), 'Missing real G42/G64 accounting invariant: '+key);
assert.match(sql,/j\.total_debit=125 and j\.total_credit=125/);
assert.match(sql,/a\.reason='journal:' \|\| j\.id::text/);
assert.match(sql,/rollback;\s*select/i);
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
assert.doesNotMatch(workflow,/\$\{\{\s*secrets\./);
console.log('Gate 99: real Gate42+Gate64 ledger, approval, source evidence and reversal coverage guarded.');
