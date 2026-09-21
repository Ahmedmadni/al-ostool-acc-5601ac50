-- ONEXA Gate 34/35 post-install verification.
-- Safe to run after both SQL packages complete successfully.

with expected_objects(object_type, object_name) as (
  values
    ('table'::text, 'onexa_document_sequences'::text),
    ('table', 'onexa_business_documents'),
    ('table', 'onexa_business_document_lines'),
    ('table', 'onexa_business_document_events'),
    ('table', 'onexa_account_role_mappings'),
    ('table', 'onexa_inventory_balances'),
    ('table', 'onexa_inventory_movements'),
    ('table', 'onexa_sales_posting_runs'),
    ('view', 'onexa_accounting_inbox'),
    ('view', 'onexa_module_document_summary'),
    ('view', 'onexa_inventory_stock_valuation'),
    ('view', 'onexa_sales_inventory_reconciliation'),
    ('view', 'onexa_sales_posting_configuration_gaps')
)
select
  expected.object_type,
  expected.object_name,
  case when class.oid is null then 'missing' else 'ready' end as object_status,
  case
    when expected.object_type = 'table' and class.oid is not null and class.relrowsecurity then 'enabled'
    when expected.object_type = 'table' and class.oid is not null then 'disabled'
    else null
  end as rls_status,
  case
    when expected.object_type = 'view' and class.reloptions @> array['security_invoker=true'] then 'security_invoker'
    when expected.object_type = 'view' and class.oid is not null then 'check_required'
    else null
  end as view_security
from expected_objects expected
left join pg_class class
  on class.relnamespace = 'public'::regnamespace
 and class.relname = expected.object_name
 and class.relkind = case when expected.object_type = 'table' then 'r'::"char" else 'v'::"char" end
order by expected.object_type, expected.object_name;

select
  procedure.oid::regprocedure::text as function_signature,
  case when procedure.prosecdef then 'definer' else 'invoker' end as security_mode,
  procedure.proconfig as function_settings,
  has_function_privilege('anon', procedure.oid, 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', procedure.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc procedure
join pg_namespace namespace on namespace.oid = procedure.pronamespace
where namespace.nspname in ('public', 'private')
  and procedure.proname in (
    'onexa_create_business_document',
    'onexa_transition_business_document',
    'onexa_post_sales_invoice',
    'onexa_next_document_number',
    'onexa_guard_business_document_mutation'
  )
order by procedure.oid::regprocedure::text;

select
  schemaname,
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'onexa_business_documents',
    'onexa_business_document_lines',
    'onexa_business_document_events',
    'onexa_account_role_mappings',
    'onexa_inventory_balances',
    'onexa_inventory_movements',
    'onexa_sales_posting_runs'
  )
order by tablename, policyname;

-- Rows here are expected until the actual chart-of-accounts codes are mapped.
-- Do not enable sales posting while this query returns any row.
select *
from public.onexa_sales_posting_configuration_gaps
order by tenant_id, legal_entity_code, account_role;

-- These counts should all be zero immediately after a clean schema install.
select 'business_documents' as source, count(*) as row_count from public.onexa_business_documents
union all
select 'inventory_balances', count(*) from public.onexa_inventory_balances
union all
select 'inventory_movements', count(*) from public.onexa_inventory_movements
union all
select 'sales_posting_runs', count(*) from public.onexa_sales_posting_runs;
