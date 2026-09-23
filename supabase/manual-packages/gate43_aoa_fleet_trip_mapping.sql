-- Accountant: inspect active detail accounts and completed tenant trips first.
-- Confirm an unpaid accrual liability, not a cash account or an AP invoice
-- already recognized elsewhere. Replace every placeholder before execution.
select code,name_ar,name_en,category,account_type,is_active
from public.chart_of_accounts where tenant_id='tenant-001-al-ostool' and is_active order by code;
select id,trip_no,vehicle_id,status,tenant_id from public.fleet_trips
where tenant_id='tenant-001-al-ostool' and status::text='completed' order by created_at desc;

begin;
do $mapping$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _entity constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _branch uuid;
  _trip_id uuid := '00000000-0000-0000-0000-000000000000';
  _cost_center text := 'REPLACE_CONFIRMED_FLEET_COST_CENTER';
  _debit text := 'REPLACE_FLEET_EXPENSE_OR_WIP_GL_CODE';
  _credit text := 'REPLACE_UNPAID_TRIP_ACCRUAL_GL_CODE';
  _trip public.fleet_trips%rowtype;
  _vehicle public.fleet_vehicles%rowtype;
begin
  if _trip_id='00000000-0000-0000-0000-000000000000'::uuid
    or _debit like 'REPLACE_%' or _credit like 'REPLACE_%'
    or _cost_center like 'REPLACE_%' then
    raise exception 'ONEXA_GATE43_CONFIRMED_TRIP_AND_ACCOUNTS_REQUIRED'; end if;
  if _debit=_credit then raise exception 'ONEXA_GATE43_DISTINCT_ACCOUNTS_REQUIRED'; end if;
  select id into _branch from public.onexa_branches
    where tenant_id=_tenant and legal_entity_id=_entity and code='RUH-HQ' and is_active;
  if _branch is null or not exists (select 1 from public.onexa_legal_entities
    where id=_entity and tenant_id=_tenant and code='AOA' and is_active) then
    raise exception 'ONEXA_GATE43_ENTITY_BRANCH_REQUIRED'; end if;
  select * into _trip from public.fleet_trips where id=_trip_id and tenant_id=_tenant;
  select * into _vehicle from public.fleet_vehicles
    where id=_trip.vehicle_id and tenant_id=_tenant;
  if _trip.id is null or _trip.status::text<>'completed' or _vehicle.id is null then
    raise exception 'ONEXA_GATE43_COMPLETED_TENANT_TRIP_REQUIRED'; end if;
  if not exists (select 1 from public.chart_of_accounts
    where tenant_id=_tenant and code=_debit and is_active and account_type::text='detail'
      and category::text in ('assets','expenses','cost_of_revenue'))
    or not exists (select 1 from public.chart_of_accounts
    where tenant_id=_tenant and code=_credit and is_active and account_type::text='detail'
      and category::text='liabilities') then
    raise exception 'ONEXA_GATE43_ACCOUNT_CATEGORY_INVALID'; end if;
  insert into public.onexa_account_role_mappings
    (tenant_id,legal_entity_id,account_role,account_code,is_active)
  values (_tenant,_entity,'logistics_or_project_cost',_debit,true),
         (_tenant,_entity,'cash_ap_or_clearing',_credit,true)
  on conflict (legal_entity_id,account_role) do update set
    tenant_id=excluded.tenant_id,account_code=excluded.account_code,
    is_active=true,updated_at=now();
  insert into public.onexa_fleet_trip_scopes
    (trip_id,tenant_id,legal_entity_id,branch_id,vehicle_id,
     trip_label,vehicle_label,cost_center_code)
  values (_trip.id,_tenant,_entity,_branch,_vehicle.id,
    coalesce(_trip.trip_no,_trip.id::text),_vehicle.plate_no,_cost_center)
  on conflict (trip_id) do update set is_active=true
    where public.onexa_fleet_trip_scopes.tenant_id=excluded.tenant_id
      and public.onexa_fleet_trip_scopes.legal_entity_id=excluded.legal_entity_id
      and public.onexa_fleet_trip_scopes.branch_id=excluded.branch_id
      and public.onexa_fleet_trip_scopes.vehicle_id=excluded.vehicle_id
      and public.onexa_fleet_trip_scopes.cost_center_code=excluded.cost_center_code;
  if not exists (select 1 from public.onexa_fleet_trip_scopes
    where trip_id=_trip.id and tenant_id=_tenant and legal_entity_id=_entity
      and branch_id=_branch and vehicle_id=_vehicle.id and cost_center_code=_cost_center
      and is_active) then raise exception 'ONEXA_GATE43_TRIP_MAPPING_INCOMPLETE'; end if;
end;
$mapping$;
commit;
