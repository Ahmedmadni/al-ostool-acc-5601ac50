-- Inspect active detail accounts first. The two role codes below require
-- accountant confirmation. The credit must be a genuine unpaid accrual/clearing
-- liability; settled AP, payroll and inventory costs must not be entered here.
select code, name_ar, name_en, category, account_type, is_active
from public.chart_of_accounts
where tenant_id = 'tenant-001-al-ostool' and is_active
order by code;

begin;
do $mapping$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _entity constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _branch uuid;
  _debit text := 'REPLACE_PROJECT_WIP_OR_EXPENSE_GL_CODE';
  _credit text := 'REPLACE_UNPAID_COST_CLEARING_GL_CODE';
  _project text := 'REPLACE_CONFIRMED_PROJECT_CODE';
  _cost_center text := 'REPLACE_CONFIRMED_COST_CENTER_CODE';
  _project_name text := 'REPLACE_CONFIRMED_PROJECT_NAME';
begin
  if _debit like 'REPLACE_%' or _credit like 'REPLACE_%'
    or _project like 'REPLACE_%' or _cost_center like 'REPLACE_%'
    or _project_name like 'REPLACE_%' then
    raise exception 'ONEXA_GATE42_CONFIRMED_MAPPING_REQUIRED';
  end if;
  if _debit = _credit then raise exception 'ONEXA_GATE42_DISTINCT_GL_ACCOUNTS_REQUIRED'; end if;
  select id into _branch from public.onexa_branches
  where tenant_id=_tenant and legal_entity_id=_entity and code='RUH-HQ' and is_active;
  if _branch is null or not exists (select 1 from public.onexa_legal_entities
    where id=_entity and tenant_id=_tenant and code='AOA' and is_active) then
    raise exception 'ONEXA_GATE42_AOA_SCOPE_REQUIRED'; end if;
  if not exists (select 1 from public.chart_of_accounts
    where tenant_id=_tenant and code=_debit and is_active and account_type::text='detail'
      and category::text in ('assets','expenses','cost_of_revenue'))
    or not exists (select 1 from public.chart_of_accounts
    where tenant_id=_tenant and code=_credit and is_active and account_type::text='detail'
      and category::text='liabilities') then
    raise exception 'ONEXA_GATE42_ACCOUNT_CATEGORY_INVALID'; end if;
  insert into public.onexa_account_role_mappings
    (tenant_id,legal_entity_id,account_role,account_code,is_active)
  values (_tenant,_entity,'project_wip_or_expense',_debit,true),
         (_tenant,_entity,'cost_source_or_clearing',_credit,true)
  on conflict (legal_entity_id,account_role) do update set
    tenant_id=excluded.tenant_id,account_code=excluded.account_code,
    is_active=true,updated_at=now();
  insert into public.onexa_project_cost_centers
    (tenant_id,legal_entity_id,branch_id,project_code,project_name,cost_center_code)
  values (_tenant,_entity,_branch,_project,_project_name,_cost_center)
  on conflict (tenant_id,legal_entity_id,branch_id,project_code,cost_center_code)
  do update set project_name=excluded.project_name,is_active=true;
end;
$mapping$;
commit;
