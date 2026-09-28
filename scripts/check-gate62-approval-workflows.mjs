import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql = readFileSync(
  "supabase/manual-packages/gate62_tenant_approval_workflows.sql",
  "utf8",
);
const page = readFileSync(
  "src/routes/_authenticated/settings/workflows.tsx",
  "utf8",
);
const shell = readFileSync(
  "src/components/settings/settings-workspace.tsx",
  "utf8",
);

for (const token of [
  "onexa_approval_workflows",
  "onexa_approval_workflow_steps",
  "onexa_save_approval_workflow",
  "onexa_approval_separation_required",
  "allow_creator_approval",
  "allow_same_actor_all_steps",
  "minimum_approvals",
  "onexa_approval_workflow_audit",
])
  assert.match(sql, new RegExp(token));

assert.match(page, /خرائط سير الاعتماد/);
assert.match(page, /onexa_save_approval_workflow/);
assert.match(page, /allow_same_actor_all_steps/);
assert.match(shell, /\/settings\/workflows/);
console.log("Gate 62 approval workflow checks passed");
