import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflow = readFileSync('.github/workflows/native-tenant-sql-smoke.yml', 'utf8');
const jobs = workflow.split(/^  (?=[a-z][\w-]*:\s*$)/m).filter(block => /^\w[\w-]*:\s*$/m.test(block.split('\n')[0] ?? ''));
assert.ok(jobs.length >= 3, 'Expected independent disposable PostgreSQL smoke jobs');
assert.match(workflow, /pull_request:/, 'Must run on pull requests');
assert.match(workflow, /image:\s*postgres:16/, 'Must use disposable PostgreSQL');
assert.doesNotMatch(workflow, /\$\{\{\s*secrets\./, 'No production or hosted database secrets in disposable CI');
const banned = [
  /(?:^|[\s/'"])gate(?:13|14|15)_[\w-]*\.sql\b/i,
  /(?:^|[\s/'"])gate66_[\w-]*\.sql\b/i
];
for (const pattern of banned) assert.doesNotMatch(workflow, pattern, 'Blocked legacy migrations must not enter disposable SQL rollout');
for (const job of jobs) {
  if (!/psql\s/.test(job)) continue;
  assert.match(job, /Confirm (?:isolated database is empty|clean disposable PostgreSQL)/, 'Each SQL job must check clean disposable database');
  assert.match(job, /PGDATABASE:\s*onexa_gate_test/, 'Use only the designated disposable test database');
  const lines = job.split('\n');
  const g42 = lines.findIndex(line => /-f supabase\/manual-packages\/gate42_project_costs\.sql/.test(line));
  const g64 = lines.findIndex(line => /-f supabase\/manual-packages\/gate64_approval_posting_bridge\.sql/.test(line));
  if (g64 !== -1) {
    assert.ok(g42 !== -1 && g42 < g64, 'Gate 42 must precede Gate 64');
    assert.match(job, /native-g64-approval-parent\.sql/, 'Gate 64 requires isolated synthetic approval/posting fixtures');
  }
  const native = [71,72,73,74,75].map(n => job.indexOf('gate' + n + '_'));
  assert.ok(native.every(pos => pos >= 0), 'All native maintenance gates 71-75 must be tested together');
  assert.ok(native.every((pos,i) => i === 0 || pos > native[i-1]), 'Native gates must remain in dependency order');
}
console.log('Gate 81: disposable SQL workflow isolation, blocked legacy gates, and dependency ordering verified.');
