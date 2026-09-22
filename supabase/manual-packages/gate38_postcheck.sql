-- Gate 38 read-only production verification.

with objects(object_name, expected_type) as (
  values
    ('onexa_asset_depreciation_postings'::text, 'table'::text),
    ('onexa_asset_accounting_reconciliation', 'view'),
    ('onexa_asset_posting_configuration_gaps', 'view')
)
select
  'object'::text as check_type,
  object_name,
  case
    when expected_type = 'table'
      and to_regclass('public.' || object_name) is not null
      then 'ready'
    when expected_type = 'view'
      and exists (
        select 1
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = object_name
          and c.relkind = 'v'
          and coalesce(c.reloptions, array[]::text[])
            @> array['security_invoker=true']
      )
      then 'ready'
    else 'missing_or_unsafe'
  end::text as status,
  expected_type as details
from objects
union all
select
  'function',
  'onexa_post_asset_depreciation',
  case
    when to_regprocedure(
      'public.onexa_post_asset_depreciation(uuid,text,date)'
    ) is not null
      and has_function_privilege(
        'authenticated',
        'public.onexa_post_asset_depreciation(uuid,text,date)',
        'execute'
      )
      and not has_function_privilege(
        'anon',
        'public.onexa_post_asset_depreciation(uuid,text,date)',
        'execute'
      )
      then 'ready'
    else 'missing_or_unsafe'
  end,
  'authenticated=true; anon=false'
union all
select
  'table_rls',
  'onexa_asset_depreciation_postings',
  case when c.relrowsecurity then 'ready' else 'disabled' end,
  'rls=' || c.relrowsecurity::text
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'onexa_asset_depreciation_postings'
union all
select
  'direct_writes',
  'onexa_asset_depreciation_postings',
  case
    when not has_table_privilege(
      'authenticated',
      'public.onexa_asset_depreciation_postings',
      'insert,update,delete'
    )
      then 'ready'
    else 'unsafe'
  end,
  'authenticated direct insert/update/delete must remain false'
union all
select
  'asset_columns',
  'fixed_assets_gate38',
  case
    when (
      select count(*)
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'fixed_assets'
        and column_name in (
          'legal_entity_id',
          'branch_id',
          'salvage_value',
          'depreciation_start_date',
          'opening_accumulated_depreciation',
          'depreciation_method'
        )
    ) = 6
      then 'ready'
    else 'missing'
  end,
  'six governed asset accounting fields required'
order by check_type, object_name;

select
  'account_mapping'::text as check_type,
  legal_entity_code || '.' || account_role as object_name,
  'configuration_required'::text as status,
  'tenant=' || tenant_id
    || '; legal_entity_id=' || legal_entity_id::text as details
from public.onexa_asset_posting_configuration_gaps
order by legal_entity_code, account_role;

select
  reconciliation_status,
  count(*) as asset_count,
  sum(cost) as total_cost,
  sum(accumulated_depreciation) as accumulated_depreciation,
  sum(net_book_value) as net_book_value
from public.onexa_asset_accounting_reconciliation
group by reconciliation_status
order by reconciliation_status;
