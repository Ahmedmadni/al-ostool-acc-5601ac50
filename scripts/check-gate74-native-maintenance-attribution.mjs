import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate74_native_maintenance_posted_cost_attribution.sql");
const postcheck = read("supabase/manual-packages/gate74_postcheck.sql");
const runbook = read("docs/runbooks/onexa-gate74-native-maintenance-cost-acceptance.md");
const panel = read("src/components/maintenance/onexa-native-cost-attribution-panel.tsx");
const route = read("src/routes/_authenticated/maintenance.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const pkg = JSON.parse(read("package.json"));

for (const str of [
  "ONEXA_GATE74_PARTIAL_OR_ALREADY_INSTALLED_STOP",
  "ONEXA_GATE74_G42_G71_G72_G73_AND_B4_REQUIRED",
  "onexa_native_wo_tenant_entity_branch_id_uq",
  "onexa_project_center_tenant_entity_branch_id_uq",
  "onexa_project_posting_tenant_entity_center_document_uq",
  "create table public.onexa_native_maintenance_cost_scopes",
  "create table public.onexa_native_maintenance_cost_attributions",
  "foreign key (tenant_id,legal_entity_id,branch_id,work_order_id)",
  "foreign key (tenant_id,legal_entity_id,branch_id,project_cost_center_id)",
  "foreign key (tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)",
  "foreign key (tenant_id,legal_entity_id,project_cost_center_id,document_id)",
  "unique(tenant_id,document_id)",
  "onexa.gate74_write_authorized",
  "ONEXA_GATE74_FINANCE_ATTRIBUTION_IMMUTABLE",
  "ONEXA_GATE74_AUTHORIZED_RPC_REQUIRED",
  "ONEXA_GATE74_ACCEPTED_NATIVE_WORK_ORDER_REQUIRED",
  "ONEXA_GATE74_COST_CENTER_REASSIGNMENT_FORBIDDEN",
  "ONEXA_GATE74_PROJECT_COST_ALREADY_ATTRIBUTED_ELSEWHERE",
  "ONEXA_GATE74_ORIGINAL_GL_JOURNAL_REVERSED_OR_MISMATCHED",
  "ONEXA_GATE74_FINANCE_ATTRIBUTION_SEPARATION_REQUIRED",
  "ONEXA_GATE74_ATTRIBUTOR_MUST_DIFFER_FROM_POSTER",
  "ONEXA_GATE74_SOURCE_DOCUMENT_NOT_POSTED_PROJECT_COST",
  "onexa_private.has_module_action(_actor,'projects','create')",
  "onexa_private.has_module_action(_actor,'projects','approve')",
  "onexa_private.has_module_action(_actor,'finance','read')",
  "public.onexa_has_company_module_access('OM','maintenance')",
  "or _document.origin<>'native'",
  "_document.source_snapshot->>'source_kind' is distinct from 'unpaid_direct_cost'",
  "_posting.project_cost_center_id is distinct from _scope.project_cost_center_id",
  "_posting.journal_id is distinct from _document.posted_journal_id",
  "_journal.reversal_journal_id is not null",
  "_journal.reversal_of_id is not null",
  "_journal.source_document_type is distinct from 'project_cost'",
  "_journal.total_debit is distinct from _document.gross_total",
  "_journal.total_credit is distinct from _document.gross_total",
  "from public.onexa_native_maintenance_cost_reconciliation r",
  "reconciliation_status='reconciled'",
  "with (security_invoker=true)",
]) assert.ok(sql.includes(str), "Missing Gate74 accounting/tenant invariant: "+str);

assert.equal((sql.match(/set search_path=pg_catalog,public as \$\$/g)??[]).length,3,
  "Gate74 must have three SECURITY DEFINER trigger/RPC definitions");
assert.equal((sql.match(/\$\$;/g)??[]).length,3,"Gate74 must close all PL/pgSQL dollar quotes");
assert.doesNotMatch(sql,/^\$;\s*$/m, "Malformed SQL dollar quoting");
assert.doesNotMatch(sql,/\bonexa_post_journal\s*\(/i,
  "Attribution MUST NOT POST a second GL journal");
assert.doesNotMatch(sql,/insert into public\.onexa_business_documents|update public\.onexa_business_documents/i,
  "Attribution must not create or modify the GL posting source");
assert.doesNotMatch(sql,/insert into public\.ops_work_orders/i,
  "Do not use tenant-unaware Gate14 work orders");
assert.match(sql,/revoke all on public\.onexa_native_maintenance_cost_scopes,/);
assert.match(sql,/grant select on public\.onexa_native_maintenance_cost_scopes,/);
assert.match(sql,/grant execute on function public\.onexa_save_native_maintenance_cost_scope/);
assert.match(sql,/create policy onexa_native_maintenance_attributions_read/);
assert.match(sql,/tenant_id=onexa_private\.claim_tenant_id\(\)/);
assert.match(sql,/when j.id is null or j.state<>'posted' or j.reversal_journal_id is not null/);

for (const field of [
  "onexa_native_maintenance_cost_scopes",
  "onexa_native_maintenance_cost_attributions",
  "onexa_native_maintenance_cost_reconciliation",
  "anon_can_attribute_cost",
  "anon_can_select",
  "authenticated_can_insert",
  "convalidated",
  "reconciliation_status<>'reconciled'",
]) assert.ok(postcheck.includes(field), "Missing postcheck: "+field);
assert.doesNotMatch(postcheck,/^\s*(?:begin|commit|create|alter|drop|truncate|insert|update|delete|grant|revoke|call)\b/im,
  "Postcheck must be read only");

assert.match(runbook,/does not recognize new unpaid maintenance costs/i);
assert.match(runbook,/two \*independent test tenants\*/);
assert.match(runbook,/Gate 66 legacy/i);
assert.match(panel,/from\("onexa_native_maintenance_work_order_cost_totals"\)/);
assert.doesNotMatch(panel,/useMutation|rpc\(|onexa_post_journal/i,"UI must remain read only");
assert.match(panel,/500/,"Partial dashboard result must disclose limit");
assert.match(route,/native && ONEXA_NATIVE_COST_ATTRIBUTION_ENABLED && <OnexaNativeCostAttributionPanel/);
assert.match(flags,/ONEXA_NATIVE_COST_ATTRIBUTION_ENABLED\s*=\s*ONEXA_NATIVE_WORK_ORDERS_ENABLED/);
assert.match(env,/VITE_ENABLE_ONEXA_NATIVE_COST_ATTRIBUTION=""/);
assert.equal(pkg.scripts["check:gate74-native-maintenance-attribution"],
  "node scripts/check-gate74-native-maintenance-attribution.mjs");
assert.match(pkg.scripts.verify,/check:gate74-native-maintenance-attribution/);
console.log("Gate 74 no-double-GL maintenance cost attribution invariants passed");
