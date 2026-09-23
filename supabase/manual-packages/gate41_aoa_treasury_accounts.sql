-- Gate 41 Al Ostool treasury accounts. Review candidates, then replace both
-- placeholder codes and labels with two distinct, accountant-confirmed bank GL
-- detail accounts. This package never guesses account numbers.
select code, name_ar, name_en, account_type, category, is_active
from public.chart_of_accounts
where tenant_id = 'tenant-001-al-ostool' and category::text = 'assets'
order by code;

begin;
do $mapping$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _entity constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _branch uuid;
  _source_code text := 'REPLACE_SOURCE_BANK_GL_CODE';
  _destination_code text := 'REPLACE_DESTINATION_BANK_GL_CODE';
  _source_label text := 'REPLACE_SOURCE_BANK_LABEL';
  _destination_label text := 'REPLACE_DESTINATION_BANK_LABEL';
  _code text;
begin
  if _source_code like 'REPLACE_%' or _destination_code like 'REPLACE_%'
    or _source_label like 'REPLACE_%' or _destination_label like 'REPLACE_%' then
    raise exception 'ONEXA_GATE41_CONFIRMED_BANK_ACCOUNTS_REQUIRED';
  end if;
  if _source_code = _destination_code then
    raise exception 'ONEXA_GATE41_DISTINCT_BANK_ACCOUNTS_REQUIRED';
  end if;
  select branch.id into _branch from public.onexa_branches branch
  where branch.tenant_id = _tenant and branch.legal_entity_id = _entity
    and branch.code = 'RUH-HQ' and branch.is_active;
  if _branch is null or not exists (select 1 from public.onexa_legal_entities
    where id = _entity and tenant_id = _tenant and code = 'AOA' and is_active) then
    raise exception 'ONEXA_GATE41_AOA_ENTITY_BRANCH_REQUIRED';
  end if;
  foreach _code in array array[_source_code, _destination_code] loop
    if not exists (select 1 from public.chart_of_accounts
      where tenant_id = _tenant and code = _code and is_active
        and account_type::text = 'detail' and category::text = 'assets') then
      raise exception 'ONEXA_GATE41_BANK_GL_ACCOUNT_INVALID:%', _code;
    end if;
  end loop;
  insert into public.onexa_treasury_accounts
    (tenant_id, legal_entity_id, branch_id, account_code, display_name, currency)
  values
    (_tenant, _entity, _branch, _source_code, _source_label, 'SAR'),
    (_tenant, _entity, _branch, _destination_code, _destination_label, 'SAR')
  on conflict (tenant_id, legal_entity_id, account_code) do update
    set display_name = excluded.display_name
    where public.onexa_treasury_accounts.branch_id = excluded.branch_id
      and public.onexa_treasury_accounts.currency = excluded.currency
      and public.onexa_treasury_accounts.is_active;
  if (select count(*) from public.onexa_treasury_accounts
    where tenant_id = _tenant and legal_entity_id = _entity and branch_id = _branch
      and account_code in (_source_code, _destination_code) and is_active) <> 2 then
    raise exception 'ONEXA_GATE41_TREASURY_MAPPING_INCOMPLETE';
  end if;
end;
$mapping$;
commit;
