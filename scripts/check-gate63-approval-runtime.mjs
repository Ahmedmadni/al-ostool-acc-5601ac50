import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = (path) => readFileSync(path,"utf8");
const sql=read("supabase/manual-packages/gate63_approval_workflow_runtime.sql");
const service=read("src/lib/documents/business-document-service.ts");
const queue=read("src/components/accounting/document-work-queue.tsx");
for (const marker of [
  "onexa_approval_instances","onexa_approval_decisions","approval_actor_matches_step",
  "onexa_approval_task_inbox","minimum_approvals","can_current_user_act",
  "onexa_transition_business_document","ONEXA_APPROVAL_STEP_NOT_ASSIGNED_TO_ACTOR",
]) assert.ok(sql.includes(marker),`runtime contract missing: ${marker}`);
assert.ok(service.includes('.from("onexa_approval_task_inbox")'));
assert.ok(service.includes("can_current_user_act"));
assert.ok(queue.includes("item.can_current_user_act"));
assert.ok(queue.includes("current_step_name"));
assert.ok(!queue.includes("currentUser.data === item.created_by"));
console.log("Gate 63 approval runtime checks passed ✓");
