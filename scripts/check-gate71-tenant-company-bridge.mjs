import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate71_onexa_tenant_company_module_scopes.sql");
const postcheck = read("supabase/manual-packages/gate71_postcheck.sql");
const g13 = read("supabase/migrations/20260914090000_gate13_holding_multicompany_foundation.sql");
const g14pre = read("supabase/migrations/20260914105900_gate14_maintenance_preflight.sql");
const g14 = read("supabase/migrations/20260914110000_gate14_maintenance_operations_engine.sql");
const gate15 = read("supabase/migrations/20260914120100_gate15_real_estate_foundation.sql");
const guard = read("src/components/group/module-access-guard.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const runbook = read("docs/runbooks/onexa-gate71-tenant-company-bridge-acceptance.md");
const manifest = JSON.parse(read("scripts/production-db/migration-manifest.json"));
const pkg = JSON.parse(read("package.json"));

for (const [migration, pattern] of [
  [g13, /ONEXA_GATE13_GLOBAL_COMPANY_SCHEMA_FORBIDDEN/],
  [g14pre, /ONEXA_GATE14_GLOBAL_OPERATIONS_SCHEMA_FORBIDDEN/],
  [g14, /ONEXA_GATE14_GLOBAL_OPERATIONS_SCHEMA_FORBIDDEN/],
  [gate15, /ONEXA_GATE15_SAAS_TENANT_SCOPE_REQUIRED/],
]) {
  assert.match(migration, pattern, "ONEXA tenant-aware data planes must reject old global migrations");
  assert.match(migration, /to_regclass\('public\.onexa_tenants'\) IS NOT NULL/);
}
assert.match(sql, /ONEXA_GATE71_PARTIAL_OR_ALREADY_INSTALLED_STOP/);
assert.match(sql, /ONEXA_GATE71_TENANT_MEMBERSHIP_AND_MODULE_RBAC_REQUIRED/);
assert.match(sql, /onexa_legal_entities_tenant_id_id_uq/);
assert.match(sql, /foreign key \(tenant_id,legal_entity_id\)/);
assert.match(sql, /references public\.onexa_legal_entities\(tenant_id,id\)/);
assert.match(sql, /unique \(tenant_id,legacy_company_code\)/);
assert.match(sql, /unique \(tenant_id,legal_entity_id,module_key\)/);
assert.match(sql, /ONEXA_COMPANY_MODULE_SCOPE_IDENTITY_IMMUTABLE/);
assert.match(sql, /onexa_guard_company_module_scope_identity/);
assert.match(sql, /enable row level security/);
assert.match(sql, /for select to authenticated/);
assert.match(sql, /tenant_id=onexa_private\.claim_tenant_id\(\)/);
assert.match(sql, /onexa_private\.is_active_member\(auth\.uid\(\)\)/);
assert.match(sql, /onexa_private\.has_module_action\(auth\.uid\(\),scope\.module_key,'read'\)/);
assert.match(sql, /security definer/);
assert.match(sql, /security_invoker=true/);
assert.match(sql, /legacy_company_code='RE'[\s\S]*?_legacy_module_key='real_estate'/);
assert.match(sql, /legacy_company_code='OM'[\s\S]*?_legacy_module_key='maintenance'/);
assert.match(sql, /legacy_company_code='CORE'[\s\S]*?_legacy_module_key='corporate_erp'/);
assert.match(sql, /revoke all on public\.onexa_company_module_scopes from public,anon,authenticated/);
assert.match(sql, /grant select on public\.onexa_company_module_scopes to authenticated/);
assert.match(sql, /revoke all on function public\.onexa_has_company_module_access\(text,text\)[\s\S]*?from public,anon/);
assert.doesNotMatch(sql, /insert into public\.onexa_company_module_scopes/i,
  "Gate 71 must not seed alias rows or fictitious company mappings");

for (const x of [
  "tenant_and_entity_composite_fk", "tenant_identity_guard",
  "view_security_invoker", "company_scope_rls",
  "anon_can_execute_access", "authenticated_can_write_scope",
  "has_explicit_tenant_filter",
]) assert.ok(postcheck.includes(x), "Postcheck missing: " + x);

assert.match(guard, /if \(ONEXA_TENANT_COMPANY_SCOPES_ENABLED\)/);
assert.match(guard, /rpc\(\s*"onexa_has_company_module_access"/);
assert.match(guard, /_company_code: companyCode, _legacy_module_key: moduleKey/);
assert.match(guard, /setState\(!error && data === true \? "allowed" : "denied"\)/);
assert.match(flags, /VITE_ENABLE_ONEXA_TENANT_COMPANY_SCOPES === "true"/);
assert.match(env, /VITE_ENABLE_ONEXA_TENANT_COMPANY_SCOPES=""/);
assert.match(runbook, /two independent/);
assert.match(runbook, /NOT installed/);
assert.ok(
  ["03_holding","04_maintenance","05_real_estate"].every((id) =>
    manifest.batches.some((b) =>
      b.id === id && b.onexa_saas_status === "BLOCKED_UNPARTITIONED_LEGACY_SCHEMA"
    )
  ), "Old deployment manifest must prohibit unpartitioned legacy rollouts"
);
assert.equal(pkg.scripts["check:gate71-tenant-company-bridge"],
  "node scripts/check-gate71-tenant-company-bridge.mjs");
assert.match(pkg.scripts.verify,/check:gate71-tenant-company-bridge/);
console.log("Gate 71 tenant-native company-module bridge structural checks passed");
