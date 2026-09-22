-- Gate 40 Al Ostool mapping validation: reuse the account selected for Gate 39.
-- Read-only. Never overwrite an already selected cash/bank account.
select mapping.account_role, mapping.account_code, account.name_ar,
  account.category, account.account_type, account.is_active
from public.onexa_account_role_mappings mapping
join public.chart_of_accounts account
  on account.tenant_id = mapping.tenant_id and account.code = mapping.account_code
where mapping.tenant_id = 'tenant-001-al-ostool'
  and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
  and mapping.account_role in ('accounts_payable', 'cash_or_bank')
order by mapping.account_role;

do $validation$
begin
  if not exists (select 1 from public.onexa_legal_entities
    where tenant_id = 'tenant-001-al-ostool'
      and id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
      and code = 'AOA' and is_active) then
    raise exception 'ONEXA_GATE40_AOA_ENTITY_REQUIRED';
  end if;
  if not exists (
    select 1 from public.onexa_account_role_mappings mapping
    join public.chart_of_accounts account
      on account.tenant_id = mapping.tenant_id
      and account.code = mapping.account_code
    where mapping.tenant_id = 'tenant-001-al-ostool'
      and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
      and mapping.account_role = 'accounts_payable'
      and mapping.account_code = '2110'
      and mapping.is_active and account.is_active
      and account.category::text = 'liabilities'
      and account.account_type::text = 'detail'
  ) then raise exception 'ONEXA_GATE40_AP_MAPPING_REQUIRED'; end if;
  if not exists (
    select 1 from public.onexa_account_role_mappings mapping
    join public.chart_of_accounts account
      on account.tenant_id = mapping.tenant_id
      and account.code = mapping.account_code
    where mapping.tenant_id = 'tenant-001-al-ostool'
      and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
      and mapping.account_role = 'cash_or_bank'
      and mapping.is_active and account.is_active
      and account.category::text = 'assets'
      and account.account_type::text = 'detail'
  ) then raise exception 'ONEXA_GATE40_CASH_ACCOUNT_MAPPING_REQUIRED'; end if;
end;
$validation$;
