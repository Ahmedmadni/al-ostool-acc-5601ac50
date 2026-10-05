-- Gate 67 AOA example mapping. Review account 4510 and the legal entity before execution.
-- For another legal entity, adapt tenant/entity and select its own active detail accounts.
-- Reuse verified Gate 35/39 mappings: AR 1120, output VAT 2160, cash/bank 1110.
begin;
select set_config('request.jwt.claims',jsonb_build_object('role','service_role','app_metadata',
  jsonb_build_object('onexa_tenant_id','tenant-001-al-ostool'))::text,true);
lock table public.chart_of_accounts in share row exclusive mode;
lock table public.onexa_account_role_mappings in share row exclusive mode;

do $preflight$
begin
  if not exists (select 1 from public.onexa_legal_entities
    where id='3ba2a953-db1d-4c1f-a192-c7343a93ab36'
      and tenant_id='tenant-001-al-ostool' and code='AOA' and is_active) then
    raise exception 'ONEXA_AOA_ACTIVE_LEGAL_ENTITY_REQUIRED'; end if;
  if onexa_private.claim_tenant_id() is distinct from 'tenant-001-al-ostool' then
    raise exception 'ONEXA_AOA_MIGRATION_TENANT_CONTEXT_FAILED'; end if;
  if exists (select 1 from public.chart_of_accounts where code='4510'
    and tenant_id<>'tenant-001-al-ostool') then
    raise exception 'ONEXA_GATE67_RENTAL_REVENUE_CODE_USED_BY_ANOTHER_TENANT'; end if;
  if not exists (select 1 from public.chart_of_accounts where tenant_id='tenant-001-al-ostool'
    and code='4000' and account_type::text='header' and category::text='revenue' and is_active) then
    raise exception 'ONEXA_AOA_REVENUE_HEADER_REQUIRED'; end if;
end;
$preflight$;

insert into public.chart_of_accounts
  (tenant_id,code,name_ar,name_en,account_type,category,parent_id,level,is_active)
select 'tenant-001-al-ostool','4510','إيرادات الإيجارات','Rental Revenue',
  'detail'::public.account_type,'revenue'::public.account_category,parent.id,2,true
from public.chart_of_accounts parent
where parent.tenant_id='tenant-001-al-ostool' and parent.code='4000'
  and not exists (select 1 from public.chart_of_accounts where code='4510');

do $validate$
declare _role text; _code text; _category text;
begin
  if not exists (select 1 from public.chart_of_accounts where tenant_id='tenant-001-al-ostool'
    and code='4510' and category::text='revenue' and account_type::text='detail' and is_active) then
    raise exception 'ONEXA_GATE67_RENTAL_REVENUE_ACCOUNT_INVALID'; end if;
  for _role,_category in select * from (values
    ('accounts_receivable'::text,'assets'::text),('output_vat','liabilities'),('cash_or_bank','assets')
  ) expected loop
    select account_code into _code from public.onexa_account_role_mappings
    where tenant_id='tenant-001-al-ostool'
      and legal_entity_id='3ba2a953-db1d-4c1f-a192-c7343a93ab36'
      and account_role=_role and is_active;
    if _code is null or not exists (select 1 from public.chart_of_accounts
      where tenant_id='tenant-001-al-ostool' and code=_code and is_active
        and account_type::text='detail' and category::text=_category) then
      raise exception 'ONEXA_GATE67_EXISTING_MAPPING_INVALID:%',_role; end if;
  end loop;
end;
$validate$;

insert into public.onexa_account_role_mappings
  (tenant_id,legal_entity_id,account_role,account_code,is_active)
values ('tenant-001-al-ostool','3ba2a953-db1d-4c1f-a192-c7343a93ab36','rental_revenue','4510',true)
on conflict (legal_entity_id,account_role) do update set
  tenant_id=excluded.tenant_id,account_code=excluded.account_code,is_active=true,updated_at=now();

do $final$
begin
  if exists (select 1 from public.onexa_lease_posting_configuration_gaps
    where tenant_id='tenant-001-al-ostool'
      and legal_entity_id='3ba2a953-db1d-4c1f-a192-c7343a93ab36') then
    raise exception 'ONEXA_AOA_LEASE_POSTING_CONFIGURATION_GAPS_REMAIN'; end if;
end;
$final$;
commit;

select mapping.account_role,mapping.account_code,account.name_ar as account_name,
  case when mapping.is_active and account.is_active then 'READY' else 'FAILED' end as status
from public.onexa_account_role_mappings mapping join public.chart_of_accounts account
  on account.tenant_id=mapping.tenant_id and account.code=mapping.account_code
where mapping.tenant_id='tenant-001-al-ostool'
  and mapping.legal_entity_id='3ba2a953-db1d-4c1f-a192-c7343a93ab36'
  and mapping.account_role in ('accounts_receivable','rental_revenue','output_vat','cash_or_bank')
order by mapping.account_role;
