import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`,import.meta.url),"utf8");
const sql = read("supabase/manual-packages/gate75_native_maintenance_unpaid_source_review.sql");
const post = read("supabase/manual-packages/gate75_postcheck.sql");
const runtimeSmoke = read("scripts/sql-fixtures/native-maintenance-two-tenant-smoke.sql");
const doc = read("docs/runbooks/onexa-gate75-unpaid-maintenance-source-acceptance.md");
const svc = read("src/lib/maintenance/native-unpaid-source-service.ts");
const panel = read("src/components/maintenance/onexa-unpaid-maintenance-source-panel.tsx");
const route = read("src/routes/_authenticated/maintenance.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const pkg = JSON.parse(read("package.json"));

for (const item of [
  "ONEXA_GATE75_PARTIAL_OR_ALREADY_INSTALLED_STOP",
  "ONEXA_GATE75_G42_G71_TO_G74_AND_RBAC_REQUIRED",
  "create table public.onexa_native_maintenance_unpaid_sources",
  "onexa_native_unpaid_claim_scope_fk",
  "onexa_native_unpaid_claim_document_fk",
  "foreign key(tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id)",
  "foreign key(tenant_id,legal_entity_id,linked_document_id)",
  "onexa_native_unpaid_claim_tenant_source_unique",
  "unique(tenant_id,legal_entity_id,source_reference)",
  "onexa_native_unpaid_claim_document_once",
  "onexa_gate75_one_active_document_per_claim_uq",
  "source_snapshot->>'maintenance_source_claim_id'",
  "source_kind in ('unbilled_subcontract','other_unpaid_direct')",
  "ONEXA_GATE75_SOURCE_APPEND_ONLY",
  "ONEXA_GATE75_SOURCE_IDENTITY_IMMUTABLE",
  "ONEXA_GATE75_AUTHORIZED_RPC_REQUIRED",
  "ONEXA_GATE75_SOURCE_TERMINAL_IMMUTABLE",
  "ONEXA_GATE75_SOURCE_INVALID_TRANSITION",
  "ONEXA_GATE75_SOURCE_REGISTRATION_NOT_AUTHORIZED",
  "ONEXA_GATE75_NEW_UNPAID_EVIDENCE_REQUIRED",
  "ONEXA_GATE75_INDEPENDENT_FINANCE_REVIEW_REQUIRED",
  "ONEXA_GATE75_SOURCE_REFERENCE_ALREADY_EXISTS_IN_DOCUMENTS",
  "ONEXA_GATE75_POSTED_DOCUMENT_PROVENANCE_MISMATCH",
  "ONEXA_GATE75_POSTED_PROJECT_COST_MISMATCH",
  "ONEXA_GATE75_SOURCE_JOURNAL_REVERSED_OR_INVALID",
  "ONEXA_GATE75_GATE74_WORK_ORDER_ATTRIBUTION_REQUIRED",
  "ONEXA_GATE75_BUSINESS_DOCUMENT_CLAIM_IMMUTABLE",
  "ONEXA_GATE75_UNAPPROVED_OR_MISMATCHED_BUSINESS_DOCUMENT",
  "onexa_native_maintenance_source_reconciliation",
  "with (security_invoker=true)",
  "original_journal_reversed_or_missing",
  "onexa_private.has_module_action(_actor,'projects','create')",
  "onexa_private.has_module_action(_actor,'projects','approve')",
  "onexa_private.has_module_action(_actor,'finance','read')",
  "public.onexa_has_company_module_access('OM','maintenance')",
]) assert.ok(sql.includes(item),"Missing G75 tenant-source/finance safeguard: "+item);

assert.match(sql,/create trigger onexa_guard_native_unpaid_source_write[\s\S]*before insert or update or delete/);
assert.match(sql,/ONEXA_GATE75_RESERVED_SOURCE_REFERENCE_REQUIRES_APPROVED_CLAIM/);
assert.equal((sql.match(/pg_advisory_xact_lock\(hashtextextended\(/g) ?? []).length,2,
  "Registration and document guard must share serialized tenant/entity/reference lock");
assert.match(runtimeSmoke,/SMOKE_UNTAGGED_G42_REFERENCE_BYPASS_ALLOWED/);
assert.match(runtimeSmoke,/ONEXA_GATE75_RESERVED_SOURCE_REFERENCE_REQUIRES_APPROVED_CLAIM/);
assert.match(sql,/create trigger onexa_guard_native_claim_business_document[\s\S]*before insert or update of source_snapshot/);
assert.equal((sql.match(/as \$\$/g)??[]).length,5,"Expected five guarded G75 PLpgSQL functions");
assert.equal((sql.match(/^\$\$;$/gm)??[]).length,5,"Every G75 PLpgSQL function must close with $$;");
assert.doesNotMatch(sql,/^\$;$/m,"Never allow single-dollar terminators");
assert.doesNotMatch(sql,/\bonexa_post_journal\s*\(|\bonexa_post_project_cost\s*\(/i,
  "Gate75 must not post GL directly");
assert.doesNotMatch(sql,/insert into public\.onexa_journal_headers|insert into public\.onexa_business_documents/i,
  "SQL registration must not create accounting entries or duplicate G42 source");
assert.match(sql,/revoke all on public\.onexa_native_maintenance_unpaid_sources from public,anon,authenticated/);
assert.match(sql,/grant select on public\.onexa_native_maintenance_unpaid_sources to authenticated/);
assert.match(sql,/grant execute on function public\.onexa_register_native_unpaid_maintenance_source/);

for(const marker of [
 "onexa_native_unpaid_claim_scope_fk",
 "onexa_native_unpaid_claim_document_fk",
 "anon_can_register",
 "anon_can_review",
 "anon_can_link",
 "onexa_guard_native_claim_business_document",
 "onexa_guard_native_unpaid_source_write",
 "onexa_gate75_one_active_document_per_claim_uq",
 "original_journal_reversed_or_missing",
]) assert.ok(post.includes(marker),"Missing G75 postcheck: "+marker);
assert.doesNotMatch(post,/^\s*(?:begin|commit|create|alter|drop|truncate|insert|update|delete|grant|revoke|call)\b/im,
  "Financial production preflight is SELECT only");

assert.match(svc,/ONEXA_NATIVE_UNPAID_SOURCES_ENABLED/);
assert.match(svc,/onexa_register_native_unpaid_maintenance_source/);
assert.match(svc,/onexa_review_native_unpaid_maintenance_source/);
assert.match(svc,/onexa_link_native_unpaid_maintenance_source/);
assert.match(svc,/createBusinessDocument\(/);
assert.match(svc,/documentType: "project_cost"/);
assert.match(svc,/maintenance_source_claim_id: source\.id/);
assert.match(svc,/source_kind: "unpaid_direct_cost"/);
assert.doesNotMatch(svc,/onexa_post_journal|onexa_post_project_cost|transitionBusinessDocument/,
  "Source preparation may only create G42 DRAFT, not submit/approve/post");
assert.match(panel,/listNativeUnpaidMaintenanceSources/);
assert.doesNotMatch(panel,/useMutation|\.rpc\(|createBusinessDocument/);
assert.match(panel,/data\?\.length \?\? 0\) === 100/,"UI must disclose 100-row limit");
assert.match(route,/native && ONEXA_NATIVE_UNPAID_SOURCES_ENABLED && <OnexaUnpaidMaintenanceSourcePanel/);
assert.match(flags,/ONEXA_NATIVE_UNPAID_SOURCES_ENABLED\s*=\s*ONEXA_NATIVE_COST_ATTRIBUTION_ENABLED/);
assert.match(flags,/ONEXA_PROJECT_COST_POSTING_ENABLED &&/);
assert.match(env,/VITE_ENABLE_ONEXA_NATIVE_UNPAID_SOURCES=""/);
assert.match(doc,/two \*independent\*|two independently provisioned \*\*disposable staging test tenants\*\*/i);
assert.match(doc,/Gate42.*standard approval|Gate42.*approval/i);
assert.match(doc,/cannot prove|cannot prove.*never/i);
assert.equal(pkg.scripts["check:gate75-native-unpaid-source-evidence"],
  "node scripts/check-gate75-native-unpaid-source-evidence.mjs");
assert.match(pkg.scripts.verify,/check:gate75-native-unpaid-source-evidence/);
console.log("Gate 75 independent evidence review + G42 claim document/source controls passed");
