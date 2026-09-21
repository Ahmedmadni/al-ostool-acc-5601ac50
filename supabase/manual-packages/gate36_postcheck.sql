-- Gate 36 read-only production verification.

with objects(object_name, expected_type) as (
  values
    ('onexa_purchase_posting_runs'::text, 'table'::text),
    ('onexa_purchase_inventory_reconciliation', 'view'),
    ('onexa_purchase_posting_configuration_gaps', 'view')
)
select
  'object'::text as check_type,
  object_name,
  case
    when expected_type = 'table' and to_regclass('public.' || object_name) is not null then 'ready'
    when expected_type = 'view' and exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = object_name and c.relkind = 'v'
        and coalesce(c.reloptions, array[]::text[]) @> array['security_invoker=true']
    ) then 'ready'
    else 'missing_or_unsafe'
  end::text as status,
  expected_type as details
from objects
union all
select
  'function', 'onexa_post_purchase_invoice',
  case when to_regprocedure('public.onexa_post_purchase_invoice(uuid,text)') is not null
    and has_function_privilege('authenticated', 'public.onexa_post_purchase_invoice(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.onexa_post_purchase_invoice(uuid,text)', 'execute')
    then 'ready' else 'missing_or_unsafe' end,
  'authenticated=true; anon=false'
union all
select
  'table_rls', 'onexa_purchase_posting_runs',
  case when c.relrowsecurity then 'ready' else 'disabled' end,
  'rls=' || c.relrowsecurity::text
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'onexa_purchase_posting_runs'
union all
select
  'direct_writes', 'onexa_purchase_posting_runs',
  case when not has_table_privilege('authenticated', 'public.onexa_purchase_posting_runs', 'insert,update,delete')
    then 'ready' else 'unsafe' end,
  'authenticated direct insert/update/delete must remain false'
order by check_type, object_name;

select
  'account_mapping'::text as check_type,
  legal_entity_code || '.' || account_role as object_name,
  'configuration_required'::text as status,
  'tenant=' || tenant_id || '; legal_entity_id=' || legal_entity_id::text as details
from public.onexa_purchase_posting_configuration_gaps
order by legal_entity_code, account_role;
