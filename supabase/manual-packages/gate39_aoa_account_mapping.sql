-- Al Ostool Gate 39 mapping.
-- Account 1110 (النقد وما في حكمه) was confirmed from the production chart
-- on 2026-09-27. Reuse the active accounts-receivable role from Gate 35.
select code, name_ar, name_en, category, account_type, is_active
from public.chart_of_accounts
where tenant_id = 'tenant-001-al-ostool' and is_active is true
  and category::text = 'assets'
order by code;

-- The guarded transaction verifies both account roles before persisting 1110.
begin;
do $mapping$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _entity constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _cash_account constant text := '1110';
  _ar_account text;
begin
  if not exists (select 1 from public.onexa_legal_entities
    where id = _entity and tenant_id = _tenant and code = 'AOA' and is_active) then
    raise exception 'ONEXA_GATE39_AOA_ENTITY_REQUIRED';
  end if;
  if not exists (select 1 from public.chart_of_accounts
    where tenant_id = _tenant and code = _cash_account and is_active
      and account_type::text = 'detail' and category::text = 'assets') then
    raise exception 'ONEXA_GATE39_CASH_ACCOUNT_INVALID';
  end if;
  select account_code
  into _ar_account
  from public.onexa_account_role_mappings
  where tenant_id = _tenant
    and legal_entity_id = _entity
    and account_role = 'accounts_receivable'
    and is_active is true;

  if _ar_account is null then
    raise exception 'ONEXA_GATE39_AR_MAPPING_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.chart_of_accounts
    where tenant_id = _tenant
      and code = _ar_account
      and is_active is true
      and account_type::text = 'detail'
      and category::text = 'assets'
  ) then
    raise exception 'ONEXA_GATE39_AR_MAPPING_INVALID';
  end if;
  insert into public.onexa_account_role_mappings
    (tenant_id, legal_entity_id, account_role, account_code, is_active)
  values (_tenant, _entity, 'cash_or_bank', _cash_account, true)
  on conflict (legal_entity_id, account_role) do update set
    account_code = excluded.account_code, tenant_id = excluded.tenant_id,
    is_active = true, updated_at = now();
end;
$mapping$;
commit;
