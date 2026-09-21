-- ONEXA ERP — Al Ostool Gate 37 payroll account-role mapping.
-- Adds only missing detail accounts. Safe to rerun; mismatches abort.

begin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'service_role',
    'app_metadata', jsonb_build_object('onexa_tenant_id', 'tenant-001-al-ostool')
  )::text,
  true
);

lock table public.chart_of_accounts in share row exclusive mode;
lock table public.onexa_account_role_mappings in share row exclusive mode;

do $preflight$
declare
  _tenant_id constant text := 'tenant-001-al-ostool';
  _legal_entity_id constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
begin
  if onexa_private.claim_tenant_id() is distinct from _tenant_id then
    raise exception 'ONEXA_AOA_MIGRATION_TENANT_CONTEXT_FAILED';
  end if;
  if not exists (
    select 1 from public.onexa_legal_entities
    where id = _legal_entity_id and tenant_id = _tenant_id
      and code = 'AOA' and is_active = true
  ) then raise exception 'ONEXA_AOA_ACTIVE_LEGAL_ENTITY_REQUIRED'; end if;
  if not exists (
    select 1 from public.chart_of_accounts
    where tenant_id = _tenant_id and code = '1100'
      and account_type::text = 'header' and category::text = 'assets' and is_active is true
  ) then raise exception 'ONEXA_AOA_CURRENT_ASSETS_1100_INVALID'; end if;
  if not exists (
    select 1 from public.chart_of_accounts
    where tenant_id = _tenant_id and code = '2100'
      and account_type::text = 'header' and category::text = 'liabilities' and is_active is true
  ) then raise exception 'ONEXA_AOA_CURRENT_LIABILITIES_2100_INVALID'; end if;
  if exists (
    select 1 from public.chart_of_accounts
    where code in ('1170', '2170') and tenant_id <> _tenant_id
  ) then raise exception 'ONEXA_AOA_PAYROLL_ACCOUNT_CODE_USED_BY_ANOTHER_TENANT'; end if;
end;
$preflight$;

insert into public.chart_of_accounts (
  tenant_id, code, name_ar, name_en, account_type,
  category, parent_id, level, is_active
)
select 'tenant-001-al-ostool', '1170', 'سلف وقروض الموظفين',
  'Employee Loans Receivable', 'detail'::public.account_type,
  'assets'::public.account_category, parent.id, 3, true
from public.chart_of_accounts parent
where parent.tenant_id = 'tenant-001-al-ostool' and parent.code = '1100'
  and not exists (select 1 from public.chart_of_accounts where code = '1170');

insert into public.chart_of_accounts (
  tenant_id, code, name_ar, name_en, account_type,
  category, parent_id, level, is_active
)
select 'tenant-001-al-ostool', '2170', 'التأمينات الاجتماعية المستحقة',
  'GOSI Payable', 'detail'::public.account_type,
  'liabilities'::public.account_category, parent.id, 3, true
from public.chart_of_accounts parent
where parent.tenant_id = 'tenant-001-al-ostool' and parent.code = '2100'
  and not exists (select 1 from public.chart_of_accounts where code = '2170');

do $validate_accounts$
declare _valid_count integer;
begin
  with expected(code, category) as (
    values
      ('6100'::text, 'expenses'::text),
      ('2140', 'liabilities'),
      ('2170', 'liabilities'),
      ('1170', 'assets')
  )
  select count(*) into _valid_count
  from expected join public.chart_of_accounts account
    on account.tenant_id = 'tenant-001-al-ostool' and account.code = expected.code
  where account.is_active is true
    and account.account_type::text = 'detail'
    and account.category::text = expected.category;
  if _valid_count <> 4 then
    raise exception 'ONEXA_AOA_EXPECTED_FOUR_VALID_PAYROLL_ACCOUNTS: found %', _valid_count;
  end if;
end;
$validate_accounts$;

insert into public.onexa_account_role_mappings (
  tenant_id, legal_entity_id, account_role, account_code, is_active
)
values
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'payroll_expense_or_project_cost', '6100', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'employee_payables', '2140', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'gosi_payable', '2170', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'employee_loans_receivable', '1170', true)
on conflict (legal_entity_id, account_role)
do update set tenant_id = excluded.tenant_id, account_code = excluded.account_code,
  is_active = true, updated_at = now();

do $final_gate$
declare _gap_count integer;
begin
  select count(*) into _gap_count
  from public.onexa_payroll_posting_configuration_gaps
  where tenant_id = 'tenant-001-al-ostool'
    and legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  if _gap_count <> 0 then
    raise exception 'ONEXA_AOA_PAYROLL_POSTING_CONFIGURATION_GAPS_REMAIN:%', _gap_count;
  end if;
end;
$final_gate$;

commit;

select mapping.account_role, mapping.account_code, account.name_ar as account_name,
  case when mapping.is_active and account.is_active is true then 'ready' else 'failed' end as status
from public.onexa_account_role_mappings mapping
join public.chart_of_accounts account
  on account.tenant_id = mapping.tenant_id and account.code = mapping.account_code
where mapping.tenant_id = 'tenant-001-al-ostool'
  and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
  and mapping.account_role in (
    'payroll_expense_or_project_cost', 'employee_payables',
    'gosi_payable', 'employee_loans_receivable'
  )
order by mapping.account_role;

