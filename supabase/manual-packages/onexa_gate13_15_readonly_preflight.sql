-- ONEXA Gates 13–15 Customer Data Plane: READ-ONLY rollout inventory.
-- Do NOT treat this report as authorization for migrations, data writes,
-- group-company provisioning or cross-tenant access. No business RPC is called.
-- Stage 13/14/15 are legacy group-company modules without native tenant_id.
-- WARNING: legacy company codes are global and cannot partition future SaaS tenants.

with required(gate, object_kind, object_name) as (
  values
  ('CORE','table','public.onexa_tenants'),
  ('CORE','table','public.onexa_legal_entities'),
  ('CORE','table','public.customers'),
  ('CORE','table','public.vendors'),
  ('CORE','table','public.contracts'),
  ('CORE','table','public.invoices'),
  ('CORE','table','public.cost_entries'),
  ('CORE','table','public.fixed_assets'),
  ('G13','table','public.group_companies'),
  ('G13','table','public.group_modules'),
  ('G13','table','public.group_company_modules'),
  ('G13','table','public.group_user_module_access'),
  ('G13','function','public.group_has_module_access(text,text)'),
  ('G14','table','public.ops_sites'),
  ('G14','table','public.ops_assets'),
  ('G14','table','public.ops_work_orders'),
  ('G14','function','public.ops_has_company_access(uuid)'),
  ('G15','table','public.re_properties'),
  ('G15','table','public.re_buildings'),
  ('G15','table','public.re_floors'),
  ('G15','table','public.re_units'),
  ('G15','table','public.re_master_leases'),
  ('G15','table','public.re_tenant_leases'),
  ('G15','table','public.re_lease_schedules'),
  ('G15','table','public.re_occupancy_events'),
  ('G15','table','public.re_facility_links'),
  ('G15','table','public.re_property_cost_links'),
  ('G15','table','public.re_status_events'),
  ('G15','sequence','public.re_master_lease_seq'),
  ('G15','sequence','public.re_tenant_lease_seq'),
  ('G15','function','public.re_create_property(text,text,text,text,text,numeric,numeric)'),
  ('G15','function','public.re_create_tenant_lease(uuid,uuid,date,date,numeric,numeric,text)'),
  ('G15','function','public.re_portfolio_snapshot()')
)
select gate,object_kind,object_name,
  case when object_kind='function'
    then to_regprocedure(object_name) is not null
    else to_regclass(object_name) is not null end as installed,
  'INSTALLATION_ONLY_NOT_SECURITY_OR_UAT_APPROVAL'::text as qualification
from required order by gate,object_kind,object_name;

-- Legacy holding/operations/real-estate records do NOT contain tenant_id in
-- checked-in Gate 13–15 migrations. Surface the architecture gap explicitly.
-- This diagnostic checks schema presence; a tenant_id column by itself still
-- does not prove that FK chains, policy predicates and definer RPCs isolate data.
with scopes(gate,table_name) as (
  values ('G13','group_companies'),('G13','group_user_module_access'),
  ('G14','ops_sites'),('G14','ops_assets'),('G14','ops_work_orders'),
  ('G15','re_properties'),('G15','re_tenant_leases'),('G15','re_lease_schedules')
)
select gate,'public.'||table_name as table_name,
  case
    when to_regclass('public.'||table_name) is null then 'NOT_INSTALLED'
    when exists (select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name=scopes.table_name
        and c.column_name='tenant_id') then 'TENANT_COLUMN_PRESENT_REVIEW_ISOLATION'
    else 'GLOBAL_COMPANY_SCOPE_NOT_SAAS_TENANT_ISOLATED'
  end as tenancy_readiness
from scopes order by gate,table_name;

-- Current customer tenancy is observed only, not mutated. One live tenant is
-- not proof that a global company design will remain safe for a second tenant.
select count(*) as tenant_count,
  min(tenant_id) as first_tenant_id,
  case when count(*)=1 then 'ONE_TENANT_OBSERVED_NOT_MULTI_TENANT_APPROVAL'
       when count(*)>1 then 'MULTI_TENANT_LEGACY_GLOBAL_COMPANY_DESIGN_BLOCKED'
       else 'NO_TENANT_FOUND_STOP' end as tenant_scope_warning
from public.onexa_tenants;

-- Distinguish a fresh Gate 15 from a partially installed one (or an
-- apparently complete set of markers). Migration 20260914120000 itself is
-- intentionally not permission to replay a package in either case.
with gate15_markers(marker,installed) as (
  values
  ('re_properties',to_regclass('public.re_properties') is not null),
  ('re_buildings',to_regclass('public.re_buildings') is not null),
  ('re_floors',to_regclass('public.re_floors') is not null),
  ('re_units',to_regclass('public.re_units') is not null),
  ('re_master_leases',to_regclass('public.re_master_leases') is not null),
  ('re_tenant_leases',to_regclass('public.re_tenant_leases') is not null),
  ('re_lease_schedules',to_regclass('public.re_lease_schedules') is not null),
  ('re_occupancy_events',to_regclass('public.re_occupancy_events') is not null),
  ('re_facility_links',to_regclass('public.re_facility_links') is not null),
  ('re_property_cost_links',to_regclass('public.re_property_cost_links') is not null),
  ('re_status_events',to_regclass('public.re_status_events') is not null),
  ('re_master_lease_seq',to_regclass('public.re_master_lease_seq') is not null),
  ('re_tenant_lease_seq',to_regclass('public.re_tenant_lease_seq') is not null),
  ('re_create_property',to_regprocedure('public.re_create_property(text,text,text,text,text,numeric,numeric)') is not null),
  ('re_create_tenant_lease',to_regprocedure('public.re_create_tenant_lease(uuid,uuid,date,date,numeric,numeric,text)') is not null),
  ('re_portfolio_snapshot',to_regprocedure('public.re_portfolio_snapshot()') is not null)
)
select count(*) filter (where installed) as installed_markers,
  count(*) as total_markers,
  case when count(*) filter (where installed)=0 then 'NO_GATE15_OBJECTS_FOUND'
       when count(*) filter (where installed)=count(*) then 'ALL_MARKERS_FOUND_REVIEW_MIGRATION_HISTORY'
       else 'PARTIAL_GATE15_STOP_AND_RECONCILE'
  end as installation_state
from gate15_markers;
