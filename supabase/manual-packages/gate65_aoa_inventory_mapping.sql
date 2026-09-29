-- Gate 65 AOA mapping. Review account codes with the chief accountant before execution.
begin;
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','app_metadata',
  jsonb_build_object('onexa_tenant_id','tenant-001-al-ostool'))::text,true);
lock table public.chart_of_accounts in share row exclusive mode;
lock table public.onexa_account_role_mappings in share row exclusive mode;

do $preflight$
begin
  if not exists (select 1 from public.onexa_legal_entities where id='3ba2a953-db1d-4c1f-a192-c7343a93ab36'
    and tenant_id='tenant-001-al-ostool' and code='AOA' and is_active=true) then
    raise exception 'ONEXA_AOA_ACTIVE_LEGAL_ENTITY_REQUIRED'; end if;
  if onexa_private.claim_tenant_id() is distinct from 'tenant-001-al-ostool' then
    raise exception 'ONEXA_AOA_MIGRATION_TENANT_CONTEXT_FAILED'; end if;
  if exists (select 1 from public.chart_of_accounts where code in ('2120','5700')
    and tenant_id<>'tenant-001-al-ostool') then
    raise exception 'ONEXA_GATE65_ACCOUNT_CODE_USED_BY_ANOTHER_TENANT'; end if;
  if not exists (select 1 from public.chart_of_accounts where tenant_id='tenant-001-al-ostool'
    and code='1130' and account_type::text='detail' and category::text='assets' and is_active=true) then
    raise exception 'ONEXA_AOA_INVENTORY_1130_INVALID'; end if;
end;
$preflight$;

insert into public.chart_of_accounts
  (tenant_id,code,name_ar,name_en,account_type,category,parent_id,level,is_active)
select 'tenant-001-al-ostool','2120','بضاعة مستلمة غير مفوترة','Goods Received Not Invoiced',
  'detail'::public.account_type,'liabilities'::public.account_category,parent.id,3,true
from public.chart_of_accounts parent where parent.tenant_id='tenant-001-al-ostool'
  and parent.code='2100' and parent.account_type::text='header'
  and not exists (select 1 from public.chart_of_accounts where code='2120');

insert into public.chart_of_accounts
  (tenant_id,code,name_ar,name_en,account_type,category,parent_id,level,is_active)
select 'tenant-001-al-ostool','5700','تكلفة صرف المخزون للمشاريع والمصروفات',
  'Inventory Issue Project Cost or Expense','detail'::public.account_type,
  'cost_of_revenue'::public.account_category,parent.id,2,true
from public.chart_of_accounts parent where parent.tenant_id='tenant-001-al-ostool'
  and parent.code='5000' and parent.account_type::text='header'
  and not exists (select 1 from public.chart_of_accounts where code='5700');

do $validate$
begin
  if (select count(*) from public.chart_of_accounts where tenant_id='tenant-001-al-ostool'
      and code in ('1130','2120','5700') and account_type::text='detail' and is_active=true)<>3 then
    raise exception 'ONEXA_GATE65_EXPECTED_THREE_VALID_ACCOUNTS'; end if;
end;
$validate$;

insert into public.onexa_account_role_mappings
  (tenant_id,legal_entity_id,account_role,account_code,is_active)
values
  ('tenant-001-al-ostool','3ba2a953-db1d-4c1f-a192-c7343a93ab36','inventory','1130',true),
  ('tenant-001-al-ostool','3ba2a953-db1d-4c1f-a192-c7343a93ab36','goods_received_not_invoiced','2120',true),
  ('tenant-001-al-ostool','3ba2a953-db1d-4c1f-a192-c7343a93ab36','project_cost_cogs_or_expense','5700',true)
on conflict (legal_entity_id,account_role) do update set tenant_id=excluded.tenant_id,
  account_code=excluded.account_code,is_active=true,updated_at=now();

do $final$
begin
  if exists (select 1 from public.onexa_inventory_posting_configuration_gaps
    where tenant_id='tenant-001-al-ostool' and legal_entity_id='3ba2a953-db1d-4c1f-a192-c7343a93ab36') then
    raise exception 'ONEXA_AOA_INVENTORY_POSTING_CONFIGURATION_GAPS_REMAIN'; end if;
end;
$final$;
commit;

select mapping.account_role,mapping.account_code,account.name_ar as account_name,
  case when mapping.is_active and account.is_active then 'READY' else 'FAILED' end as status
from public.onexa_account_role_mappings mapping join public.chart_of_accounts account
  on account.tenant_id=mapping.tenant_id and account.code=mapping.account_code
where mapping.tenant_id='tenant-001-al-ostool'
  and mapping.legal_entity_id='3ba2a953-db1d-4c1f-a192-c7343a93ab36'
  and mapping.account_role in ('inventory','goods_received_not_invoiced','project_cost_cogs_or_expense')
order by mapping.account_role;
