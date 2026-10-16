import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (p) => readFileSync(new URL(`../${p}`,import.meta.url),"utf8");
const sql = read("supabase/manual-packages/gate73_onexa_native_operations_work_orders.sql");
const post = read("supabase/manual-packages/gate73_postcheck.sql");
const docs = read("docs/runbooks/onexa-gate73-work-orders-acceptance.md");
const route = read("src/routes/_authenticated/maintenance.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const pkg = JSON.parse(read("package.json"));

for(const name of ["onexa_operations_work_orders","onexa_operations_work_order_events"]) {
  assert.match(sql,new RegExp("create table public\\."+name));
  assert.match(sql,new RegExp("alter table public\\."+name+" enable row level security"));
}
for(const marker of [
  "ONEXA_GATE73_ALREADY_OR_PARTIALLY_INSTALLED_STOP",
  "ONEXA_GATE73_G71_G72_AND_TENANT_CORE_REQUIRED",
  "onexa_customers_tenant_id_id_uq",
  "onexa_contracts_tenant_id_id_customer_uq",
  "onexa_operations_assets_scope_site_id_uq",
  "foreign key (tenant_id,legal_entity_id,branch_id,site_id)",
  "foreign key (tenant_id,legal_entity_id,branch_id,site_id,asset_id)",
  "foreign key (tenant_id,customer_id)",
  "foreign key (tenant_id,contract_id,customer_id)",
  "foreign key (tenant_id,work_order_id)",
  "ONEXA_WORK_ORDER_IDENTITY_IMMUTABLE",
  "ONEXA_WORK_ORDER_TRANSITION_RPC_REQUIRED",
  "ONEXA_WORK_ORDER_TERMINAL_IMMUTABLE",
  "ONEXA_WORK_ORDER_AUDIT_APPEND_ONLY",
  "ONEXA_WORK_ORDER_EVENT_RPC_REQUIRED",
  "ONEXA_WORK_ORDER_SITE_NOT_ACCESSIBLE",
  "ONEXA_WORK_ORDER_ASSET_SCOPE_INVALID",
  "ONEXA_WORK_ORDER_CUSTOMER_NOT_ACCESSIBLE",
  "ONEXA_WORK_ORDER_CONTRACT_SCOPE_INVALID",
  "ONEXA_WORK_ORDER_CREATOR_CANNOT_APPROVE",
  "ONEXA_WORK_ORDER_ACCEPTANCE_SEPARATION_REQUIRED",
  "ONEXA_WORK_ORDER_ACTIVE_ASSIGNEE_REQUIRED",
  "ONEXA_WORK_ORDER_INVALID_TRANSITION",
  "onexa_private.has_module_action(_actor,'projects','create')",
  "onexa_private.has_module_action(_actor,'projects','approve')",
  "onexa_private.is_active_member(_actor)",
  "contract.customer_id=_customer_id",
  "contract.tenant_id=_tenant",
  "site.tenant_id=_tenant",
  "for update",
  "set_config('onexa.wo_transition_authorized','true',true)",
  "set_config('onexa.wo_event_authorized','true',true)",
  "scope.legacy_company_code='OM'",
  "grant select on public.onexa_operations_work_orders",
]) assert.ok(sql.includes(marker), "Missing operational order control: "+marker);

const uniqueIndexAt=sql.indexOf("create unique index onexa_work_order_tenant_id_uq");
const eventsTableAt=sql.indexOf("create table public.onexa_operations_work_order_events");
assert.ok(uniqueIndexAt>=0 && uniqueIndexAt<eventsTableAt,
  "Event composite FK needs its referenced unique work-order index BEFORE CREATE TABLE");
assert.doesNotMatch(sql, /^\$;\s*$/m,"Malformed PostgreSQL dollar quote");
assert.equal((sql.match(/\$\$;/g)||[]).length,4,
  "Four trigger/RPC PLpgSQL definitions must close with $$;");
assert.equal((sql.match(/set search_path=pg_catalog,public as \$\$/g)||[]).length,4);
assert.match(sql, /create trigger onexa_guard_native_work_order_events\s+before insert or update or delete/i);
assert.match(sql, /when _target_status='assigned'/);
assert.match(sql, /contract\.status::text='active'/);
assert.match(sql, /and \(contract\.end_date is null or contract\.end_date>=current_date\)/);
assert.doesNotMatch(sql, /onexa_post_journal\(/i,"Work order workflow must not post GL");
assert.doesNotMatch(sql, /insert into public\.ops_work_orders/i,"Never touch global legacy work orders");
assert.match(sql,/revoke all on public\.onexa_operations_work_orders/);
assert.match(sql,/grant execute on function public\.onexa_create_operations_work_order/);
for(const m of ["work_order_composite_scope_fks","work_order_event_tenant_fk",
  "work_order_append_only_guard","anon_can_transition_order"]) {
  assert.ok(post.includes(m),"Postcheck missing: "+m);
}
assert.match(docs,/two independent staging tenants/);
assert.match(docs,/NOT compatible/);
assert.equal(pkg.scripts["check:gate73-work-order-lifecycle"],
  "node scripts/check-gate73-work-order-lifecycle.mjs");
assert.match(pkg.scripts.verify,/check:gate73-work-order-lifecycle/);
const wrapperAt = route.indexOf("function MaintenanceModuleLanding()");
const innerAt = route.indexOf("function MaintenanceModuleContent()");
const queryAt = route.indexOf("const { data, isLoading, error } = useQuery(",innerAt);
assert.ok(wrapperAt>=0 && wrapperAt<innerAt && innerAt<queryAt,
  "Maintenance queries must be mounted after ModuleAccessGuard");
assert.match(route.slice(wrapperAt,innerAt), /<ModuleAccessGuard companyCode="OM" moduleKey="maintenance">/);
assert.match(route.slice(wrapperAt,innerAt), /<MaintenanceModuleContent\s*\/>/);
assert.match(route, /enabled: legacy \|\| native/);
assert.match(route, /if \(native\) \{/);
assert.match(route, /from\("onexa_operations_work_orders"\)/);
assert.match(route, /from\("onexa_operations_assets"\)/);
assert.match(route, /!legacy && !native/);
assert.match(route, /legacy && <OnexaMaintenanceCostsPanel \/>/);
assert.match(flags, /ONEXA_NATIVE_WORK_ORDERS_ENABLED\s*=\s*ONEXA_TENANT_COMPANY_SCOPES_ENABLED/);
assert.match(env, /VITE_ENABLE_ONEXA_NATIVE_WORK_ORDERS=""/);
console.log("Gate 73 native work order lifecycle source invariants passed");
