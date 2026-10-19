import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const bridge = read('supabase/manual-packages/gate64_approval_posting_bridge.sql');
const gate42 = read('supabase/manual-packages/gate42_project_costs.sql');
const workflow = read('.github/workflows/native-tenant-sql-smoke.yml');
const engines = [
  'sales_invoice', 'purchase_invoice', 'customer_receipt',
  'supplier_payment', 'bank_transfer', 'project_cost', 'fleet_trip_cost'
];
for (const engine of engines) {
  const signature = 'public.onexa_post_' + engine + '(uuid,text)';
  assert.ok(bridge.includes(signature), 'Gate64 prerequisite absent: ' + signature);
  assert.ok((bridge.match(new RegExp(signature.replace(/[.*+?^\x24{}()|[\]\\]/g, '\\$&'), 'g')) ?? []).length >= 2,
    'Engine must be checked during preflight and patch list: ' + signature);
}
assert.match(bridge, /ONEXA_GATE63_APPROVAL_RUNTIME_REQUIRED/);
assert.match(bridge, /ONEXA_GATE64_POSTING_ENGINE_REQUIRED/);
assert.match(bridge, /ONEXA_GATE64_GUARD_DEFINITION_AMBIGUOUS/);
assert.match(bridge, /ONEXA_GATE64_SEPARATION_GUARD_PATCH_FAILED/);
assert.match(bridge, /ONEXA_POST_STEP_NOT_ASSIGNED_TO_ACTOR/);
assert.match(bridge, /ONEXA_APPROVAL_POST_INSTANCE_REQUIRED/);
assert.match(bridge, /ONEXA_SEGREGATION_OF_DUTIES_REQUIRED/);
assert.match(bridge, /onexa_private\.approval_actor_matches_step\(/);
assert.match(bridge, /public\.onexa_approval_separation_required\(/);
assert.match(bridge, /when \(old\.status = 'approved' and new\.status = 'posted'\)/i);
assert.match(bridge, /with \(security_invoker = true\)/i);
assert.match(bridge, /public\.onexa_can_post_business_document\(document\.id\)/);
for (const column of ['approval_instance_id','posting_step_name','can_current_user_post']) {
  assert.ok(bridge.includes(column), 'Missing guarded accounting inbox projection: '+column);
}
assert.match(bridge, /revoke all on function public\.onexa_can_post_business_document\(uuid\) from public, anon;/i);
assert.match(bridge, /grant execute on function public\.onexa_can_post_business_document\(uuid\) to authenticated;/i);
assert.match(gate42, /onexa_post_project_cost\(/i);
assert.match(workflow, /native-g64-real-approval-posting-smoke\.sql/);
assert.match(workflow, /gate64_approval_posting_bridge\.sql/);
assert.doesNotMatch(workflow, /\$\{\{\s*secrets\./);
console.log('Gate83 approval/posting SQL contract and synthetic CI linkage verified.');
