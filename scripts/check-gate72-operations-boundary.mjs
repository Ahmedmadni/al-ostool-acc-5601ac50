import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/gate72_onexa_native_operations_sites_assets.sql");
const postcheck = read("supabase/manual-packages/gate72_postcheck.sql");
const runbook = read("docs/runbooks/onexa-gate72-native-operations-acceptance.md");
const pkg = JSON.parse(read("package.json"));
assert.doesNotMatch(sql, /^\$;\s*$/m, "Invalid one-dollar PL/pgSQL terminator");
assert.equal((sql.match(/\$\$;/g) ?? []).length, 4,
  "Both native operations guard and create function definitions must close with $;");
assert.equal((sql.match(/set search_path=pg_catalog,public as \$\$/g) ?? []).length, 4,
  "Expected two trigger functions and two creation RPCs");

for (const name of ["onexa_operations_sites","onexa_operations_assets"]) {
  assert.match(sql,new RegExp("create table public\\."+name));
  assert.match(sql,new RegExp("alter table public\\."+name+" enable row level security"));
  assert.match(sql,new RegExp("revoke all on public\\.onexa_operations_sites,public\\.onexa_operations_assets"));
}
for (const marker of [
  "ONEXA_GATE72_ALREADY_OR_PARTIALLY_INSTALLED_STOP",
  "ONEXA_GATE72_TENANT_COMPANY_SCOPE_BRANCH_RBAC_REQUIRED",
  "onexa_branches_tenant_entity_id_uq",
  "onexa_company_module_scopes_tenant_entity_id_uq",
  "foreign key (tenant_id,legal_entity_id,branch_id)",
  "foreign key (tenant_id,legal_entity_id,company_scope_id)",
  "foreign key (tenant_id,legal_entity_id,branch_id,site_id)",
  "ONEXA_OPERATIONS_SITE_SCOPE_IMMUTABLE",
  "ONEXA_OPERATIONS_ASSET_SCOPE_IMMUTABLE",
  "ONEXA_OPERATIONS_SITE_SCOPE_INVALID",
  "ONEXA_OPERATIONS_ASSET_PARENT_SITE_INVALID",
  "before insert or update on public.onexa_operations_sites",
  "before insert or update on public.onexa_operations_assets",
  "onexa_private.is_active_member(auth.uid())",
  "onexa_private.has_module_action(auth.uid(),'projects','read')",
  "onexa_private.has_module_action(_actor,'projects','create')",
  "public.onexa_has_company_module_access('OM','maintenance')",
  "scope.tenant_id=_tenant and scope.legal_entity_id=_legal_entity_id",
  "onexa_operations_assets.tenant_id",
  "and branch.is_active and entity.is_active",
  "where site.id=site_id and site.is_active",
  "onexa_guard_native_operations_site_identity",
  "onexa_guard_native_operations_asset_identity",
]) assert.ok(sql.includes(marker), "Missing site/asset tenant safety: "+marker);
assert.match(sql, /create function public\.onexa_create_operations_site/);
assert.match(sql, /create function public\.onexa_create_operations_asset/);
assert.match(sql, /security definer/);
assert.match(sql, /grant select on public\.onexa_operations_sites,public\.onexa_operations_assets\s+to authenticated/);
assert.doesNotMatch(sql, /insert into public\.onexa_operations_sites[\s\S]*?values\s*\('tenant-001/,
  "No auto-created site data is allowed");
for(const marker of ["asset_site_composite_fk","site_branch_and_company_fks",
  "asset_scope_rls","site_scope_rls","anon_can_create_site","authenticated_can_write_sites"]) {
  assert.ok(postcheck.includes(marker), "Missing gate72 postcheck: "+marker);
}
assert.match(runbook, /two independent TEST tenants/);
assert.match(runbook, /NOT INSTALLED/);
assert.equal(pkg.scripts["check:gate72-operations-boundary"],
  "node scripts/check-gate72-operations-boundary.mjs");
assert.match(pkg.scripts.verify, /check:gate72-operations-boundary/);
console.log("Gate 72 native operations site/asset boundaries verified");
