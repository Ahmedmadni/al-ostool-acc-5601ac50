import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = p => readFileSync(new URL('../'+p,import.meta.url),'utf8');
const sql=read('scripts/sql-fixtures/native-g64-real-approval-posting-smoke.sql');
const workflow=read('.github/workflows/native-tenant-sql-smoke.yml');
for(const name of [
  'SMOKE_G104_MISSING_TENANT_POST_ALLOWED',
  'SMOKE_G105_NONMEMBER_POST_ALLOWED',
  'SMOKE_G106_INVALID_MONTH_POST_ALLOWED',
  'SMOKE_G106_DENIED_ATTEMPTS_LEFT_ACCOUNTING_ROWS',
  'SMOKE_G107_REVERSED_JOURNAL_REPOST_ALLOWED',
  'SMOKE_G108_REVERSAL_RETRY_DUPLICATED_ACCOUNTING',
  'ONEXA_PROJECT_COST_JOURNAL_REVERSED_OR_MISSING',
  'SMOKE_G96_POSTING_TOTALS_OR_ENTITY_MISMATCH',
  'SMOKE_G98_REVERSAL_ERASED_SOURCE_EVIDENCE'
]) assert.ok(sql.includes(name),'Missing finance denial/reversal invariant: '+name);
assert.match(sql,/rollback;\s*select/i);
assert.match(workflow,/native-g64-real-approval-posting-smoke\.sql/);
console.log('Gate109: negative financial posting/reversal assertions anchored to real G42 and G64 CI smoke.');
