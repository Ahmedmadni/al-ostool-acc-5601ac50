-- ONEXA ERP — AOA Gate 35 account-role mapping
-- Creates three missing detail accounts and maps all five sales posting roles.
-- Safe to rerun. Any mismatch aborts the whole transaction.

begin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'service_role',
    'app_metadata', jsonb_build_object(
      'onexa_tenant_id', 'tenant-001-al-ostool'
    )
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
  if not exists (
    select 1
    from public.onexa_legal_entities entity
    where entity.id = _legal_entity_id
      and entity.tenant_id = _tenant_id
      and entity.code = 'AOA'
      and entity.is_active = true
  ) then
    raise exception 'ONEXA_AOA_ACTIVE_LEGAL_ENTITY_REQUIRED';
  end if;

  if onexa_private.claim_tenant_id() is distinct from _tenant_id then
    raise exception 'ONEXA_AOA_MIGRATION_TENANT_CONTEXT_FAILED';
  end if;

  if exists (
    select 1
    from public.chart_of_accounts account
    where account.code in ('2160', '4500', '5600')
      and account.tenant_id <> _tenant_id
  ) then
    raise exception 'ONEXA_AOA_ACCOUNT_CODE_USED_BY_ANOTHER_TENANT';
  end if;

  if not exists (
    select 1
    from public.chart_of_accounts account
    where account.tenant_id = _tenant_id
      and account.code = '1120'
      and account.account_type::text = 'detail'
      and account.category::text = 'assets'
      and account.is_active is true
  ) then
    raise exception 'ONEXA_AOA_ACCOUNTS_RECEIVABLE_1120_INVALID';
  end if;

  if not exists (
    select 1
    from public.chart_of_accounts account
    where account.tenant_id = _tenant_id
      and account.code = '1130'
      and account.account_type::text = 'detail'
      and account.category::text = 'assets'
      and account.is_active is true
  ) then
    raise exception 'ONEXA_AOA_INVENTORY_1130_INVALID';
  end if;

  if not exists (
    select 1
    from public.chart_of_accounts account
    where account.tenant_id = _tenant_id
      and account.code = '2100'
      and account.account_type::text = 'header'
      and account.category::text = 'liabilities'
      and account.is_active is true
  ) then
    raise exception 'ONEXA_AOA_CURRENT_LIABILITIES_2100_INVALID';
  end if;

  if not exists (
    select 1
    from public.chart_of_accounts account
    where account.tenant_id = _tenant_id
      and account.code = '4000'
      and account.account_type::text = 'header'
      and account.category::text = 'revenue'
      and account.is_active is true
  ) then
    raise exception 'ONEXA_AOA_REVENUE_HEADER_4000_INVALID';
  end if;

  if not exists (
    select 1
    from public.chart_of_accounts account
    where account.tenant_id = _tenant_id
      and account.code = '5000'
      and account.account_type::text = 'header'
      and account.category::text = 'cost_of_revenue'
      and account.is_active is true
  ) then
    raise exception 'ONEXA_AOA_COST_OF_REVENUE_HEADER_5000_INVALID';
  end if;

  if exists (
    select 1
    from public.onexa_account_role_mappings mapping
    where mapping.legal_entity_id = _legal_entity_id
      and mapping.account_role in (
        'accounts_receivable', 'sales_revenue', 'output_vat',
        'inventory', 'cost_of_goods_sold'
      )
      and mapping.tenant_id <> _tenant_id
  ) then
    raise exception 'ONEXA_AOA_EXISTING_MAPPING_TENANT_MISMATCH';
  end if;
end;
$preflight$;

insert into public.chart_of_accounts (
  tenant_id, code, name_ar, name_en, account_type,
  category, parent_id, level, is_active
)
select
  'tenant-001-al-ostool',
  '2160',
  'ضريبة القيمة المضافة - مخرجات',
  'Output VAT Payable',
  'detail'::public.account_type,
  'liabilities'::public.account_category,
  parent.id,
  3,
  true
from public.chart_of_accounts parent
where parent.tenant_id = 'tenant-001-al-ostool'
  and parent.code = '2100'
  and not exists (
    select 1 from public.chart_of_accounts account where account.code = '2160'
  );

insert into public.chart_of_accounts (
  tenant_id, code, name_ar, name_en, account_type,
  category, parent_id, level, is_active
)
select
  'tenant-001-al-ostool',
  '4500',
  'إيرادات المبيعات',
  'Sales Revenue',
  'detail'::public.account_type,
  'revenue'::public.account_category,
  parent.id,
  2,
  true
from public.chart_of_accounts parent
where parent.tenant_id = 'tenant-001-al-ostool'
  and parent.code = '4000'
  and not exists (
    select 1 from public.chart_of_accounts account where account.code = '4500'
  );

insert into public.chart_of_accounts (
  tenant_id, code, name_ar, name_en, account_type,
  category, parent_id, level, is_active
)
select
  'tenant-001-al-ostool',
  '5600',
  'تكلفة البضاعة المباعة',
  'Cost of Goods Sold',
  'detail'::public.account_type,
  'cost_of_revenue'::public.account_category,
  parent.id,
  2,
  true
from public.chart_of_accounts parent
where parent.tenant_id = 'tenant-001-al-ostool'
  and parent.code = '5000'
  and not exists (
    select 1 from public.chart_of_accounts account where account.code = '5600'
  );

do $validate_accounts$
declare
  _valid_count integer;
begin
  with expected(code, category, parent_code, level, required_name_ar) as (
    values
      ('1120'::text, 'assets'::text, '1100'::text, 3, null::text),
      ('1130', 'assets', '1100', 3, null),
      ('2160', 'liabilities', '2100', 3, 'ضريبة القيمة المضافة - مخرجات'),
      ('4500', 'revenue', '4000', 2, 'إيرادات المبيعات'),
      ('5600', 'cost_of_revenue', '5000', 2, 'تكلفة البضاعة المباعة')
  )
  select count(*) into _valid_count
  from expected
  join public.chart_of_accounts account
    on account.tenant_id = 'tenant-001-al-ostool'
   and account.code = expected.code
  join public.chart_of_accounts parent
    on parent.tenant_id = account.tenant_id
   and parent.id = account.parent_id
   and parent.code = expected.parent_code
  where account.is_active is true
    and account.account_type::text = 'detail'
    and account.category::text = expected.category
    and account.level = expected.level
    and (
      expected.required_name_ar is null
      or account.name_ar = expected.required_name_ar
    );

  if _valid_count <> 5 then
    raise exception 'ONEXA_AOA_EXPECTED_FIVE_VALID_POSTING_ACCOUNTS: found %', _valid_count;
  end if;
end;
$validate_accounts$;

insert into public.onexa_account_role_mappings (
  tenant_id, legal_entity_id, account_role, account_code, is_active
)
values
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'accounts_receivable', '1120', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'sales_revenue', '4500', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'output_vat', '2160', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'inventory', '1130', true),
  ('tenant-001-al-ostool', '3ba2a953-db1d-4c1f-a192-c7343a93ab36', 'cost_of_goods_sold', '5600', true)
on conflict (legal_entity_id, account_role)
do update set
  tenant_id = excluded.tenant_id,
  account_code = excluded.account_code,
  is_active = true,
  updated_at = now();

do $final_gate$
declare
  _valid_mapping_count integer;
  _gap_count integer;
begin
  select count(*) into _valid_mapping_count
  from public.onexa_account_role_mappings mapping
  join public.chart_of_accounts account
    on account.tenant_id = mapping.tenant_id
   and account.code = mapping.account_code
  where mapping.tenant_id = 'tenant-001-al-ostool'
    and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
    and mapping.account_role in (
      'accounts_receivable', 'sales_revenue', 'output_vat',
      'inventory', 'cost_of_goods_sold'
    )
    and mapping.is_active is true
    and account.is_active is true
    and account.account_type::text = 'detail';

  if _valid_mapping_count <> 5 then
    raise exception 'ONEXA_AOA_EXPECTED_FIVE_VALID_ACCOUNT_MAPPINGS: found %', _valid_mapping_count;
  end if;

  select count(*) into _gap_count
  from public.onexa_sales_posting_configuration_gaps gap
  where gap.tenant_id = 'tenant-001-al-ostool'
    and gap.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36';

  if _gap_count <> 0 then
    raise exception 'ONEXA_AOA_SALES_POSTING_CONFIGURATION_GAPS_REMAIN: %', _gap_count;
  end if;
end;
$final_gate$;

commit;

with mapping_rows as (
  select
    'account_mapping'::text as check_type,
    mapping.account_role,
    mapping.account_code,
    account.name_ar as account_name,
    case
      when mapping.is_active and account.is_active is true
        and account.account_type::text = 'detail' then 'ready'
      else 'failed'
    end::text as status
  from public.onexa_account_role_mappings mapping
  join public.chart_of_accounts account
    on account.tenant_id = mapping.tenant_id
   and account.code = mapping.account_code
  where mapping.tenant_id = 'tenant-001-al-ostool'
    and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
    and mapping.account_role in (
      'accounts_receivable', 'sales_revenue', 'output_vat',
      'inventory', 'cost_of_goods_sold'
    )
), gap_summary as (
  select
    'mapping_summary'::text as check_type,
    'sales_posting_accounts'::text as account_role,
    null::text as account_code,
    format('remaining_gaps=%s', count(*))::text as account_name,
    case when count(*) = 0 then 'ready' else 'failed' end::text as status
  from public.onexa_sales_posting_configuration_gaps gap
  where gap.tenant_id = 'tenant-001-al-ostool'
    and gap.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
)
select * from mapping_rows
union all
select * from gap_summary
order by check_type, account_role;
