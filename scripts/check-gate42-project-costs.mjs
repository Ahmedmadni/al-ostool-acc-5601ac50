import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate42_project_costs.sql");
const mapping = read("supabase/manual-packages/gate42_aoa_project_cost_mapping.sql");
const postcheck = read("supabase/manual-packages/gate42_postcheck.sql");
const smoke = read("supabase/manual-packages/gate42_project_cost_smoke_test_rollback.sql");
const flags = read("src/lib/runtime-flags.ts");
const service = read("src/lib/projects/project-cost-service.ts");
const route = read("src/routes/_authenticated/projects/index.tsx");
for (const pattern of [
  /onexa_post_journal\(/, /onexa_post_project_cost\(/,
  /onexa_private\.claim_tenant_id\(\)/,
  /has_module_action\(_actor,'projects','post'\)/,
  /_document\.created_by = _actor/,
  /for update/, /source_revision/,
  /unique \(tenant_id, legal_entity_id, external_reference\)/,
  /with \(security_invoker = true\)/,
  /enable row level security/g,
  /revoke all on public\.onexa_project_cost_centers, public\.onexa_project_cost_postings/,
  /_debit = _credit/,
]) assert.match(sql, pattern);
assert.match(mapping, /REPLACE_PROJECT_WIP_OR_EXPENSE_GL_CODE/);
assert.match(mapping, /REPLACE_UNPAID_COST_CLEARING_GL_CODE/);
assert.match(mapping, /ONEXA_GATE42_CONFIRMED_MAPPING_REQUIRED/);
assert.match(postcheck, /direct_writes_denied/);
assert.match(postcheck, /anon_can_execute/);
assert.match(smoke, /_again := public\.onexa_post_project_cost/);
assert.match(smoke, /rollback;/i);
assert.match(flags, /ONEXA_PROJECT_COST_POSTING_ENABLED/);
assert.match(service, /documentType: "project_cost"/);
assert.match(route, /OnexaProjectCostsPanel/);
console.log("Gate 42 project cost checks passed");
