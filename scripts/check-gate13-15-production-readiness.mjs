import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (file) => readFileSync(new URL(`../${file}`, import.meta.url), "utf8");
const sql = read("supabase/manual-packages/onexa_gate13_15_readonly_preflight.sql");
const preflight = read("supabase/migrations/20260914120000_gate15_real_estate_preflight.sql");
const foundation = read("supabase/migrations/20260914120100_gate15_real_estate_foundation.sql");
const route = read("src/routes/_authenticated/real-estate.tsx");
const guard = read("src/components/group/module-access-guard.tsx");
const runbook = read("docs/runbooks/onexa-gate13-15-tenant-scope-acceptance.md");
const pkg = JSON.parse(read("package.json"));

for (const name of [
  "public.onexa_tenants",
  "public.group_companies",
  "public.group_user_module_access",
  "public.group_has_module_access(text,text)",
  "public.ops_sites",
  "public.ops_work_orders",
  "public.re_properties",
  "public.re_lease_schedules",
  "public.re_portfolio_snapshot()",
]) assert.ok(sql.includes(name), "Missing readiness prerequisite: " + name);

assert.match(sql, /GLOBAL_COMPANY_SCOPE_NOT_SAAS_TENANT_ISOLATED/);
assert.match(sql, /MULTI_TENANT_LEGACY_GLOBAL_COMPANY_DESIGN_BLOCKED/);
assert.match(sql, /PARTIAL_GATE15_STOP_AND_RECONCILE/);
assert.match(sql, /ONE_TENANT_OBSERVED_NOT_MULTI_TENANT_APPROVAL/);
assert.doesNotMatch(sql, /^\s*(?:begin|commit|create|alter|drop|truncate|insert|update|delete|grant|revoke|do|call)\b/im);
assert.match(preflight, /ONEXA_GATE15_SAAS_TENANT_SCOPE_REQUIRED/);
assert.match(foundation, /ONEXA_GATE15_SAAS_TENANT_SCOPE_REQUIRED/);
assert.match(foundation, /table_name='group_companies'/);
assert.match(foundation, /table_name='group_user_module_access'/);
assert.match(foundation, /table_name='ops_sites'/);
assert.match(preflight, /table_name='group_companies'/);
assert.match(preflight, /table_name='group_user_module_access'/);
assert.match(preflight, /table_name='ops_sites'/);
assert.match(preflight, /IF v_found > 0 THEN/);
assert.match(preflight, /already installed or appears partially applied/);

const outer = route.indexOf("function RealEstateModuleLanding()");
const child = route.indexOf("function RealEstateModuleContent()");
const fetchQuery = route.indexOf("const { data, isLoading, error } = useQuery(", outer);
assert.ok(outer >= 0 && child > outer && fetchQuery > child,
  "Dashboard query must be nested under the guard-controlled component");
const outerSource = route.slice(outer, child);
assert.match(outerSource, /<ModuleAccessGuard companyCode="RE" moduleKey="real_estate">/);
assert.match(outerSource, /<RealEstateModuleContent\s*\/>/);
assert.doesNotMatch(outerSource, /useQuery\(|loadRealEstateDashboard\(/);
assert.match(guard, /if \(state === "denied"\)/);
assert.match(runbook, /BLOCKED/);
assert.match(runbook, /two different actual test tenants/);
assert.equal(pkg.scripts["check:gate13-15-production-readiness"],
  "node scripts/check-gate13-15-production-readiness.mjs");
assert.match(pkg.scripts.verify,/check:gate13-15-production-readiness/);
console.log("Gate 13–15 tenant-scoping and authorization readiness controls passed");
