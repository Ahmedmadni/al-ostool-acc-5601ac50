-- Read-only Gate 39 validation. Run after package and account mapping.
select 'onexa_customer_receipt_postings' as object_name,
  to_regclass('public.onexa_customer_receipt_postings') is not null as ready
union all select 'onexa_customer_receipt_allocations',
  to_regclass('public.onexa_customer_receipt_allocations') is not null
union all select 'onexa_post_customer_receipt',
  to_regprocedure('public.onexa_post_customer_receipt(uuid,text)') is not null;

select c.relname as table_name, c.relrowsecurity as rls_enabled,
  not has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE') as authenticated_direct_writes_denied
from pg_class c where c.oid in (
  'public.onexa_customer_receipt_postings'::regclass,
  'public.onexa_customer_receipt_allocations'::regclass
);

select c.relname as view_name, coalesce(c.reloptions @> array['security_invoker=true'], false) as security_invoker
from pg_class c where c.oid in (
  'public.onexa_customer_receivables_reconciliation'::regclass,
  'public.onexa_customer_receipt_configuration_gaps'::regclass
);

select has_function_privilege('anon', 'public.onexa_post_customer_receipt(uuid,text)', 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', 'public.onexa_post_customer_receipt(uuid,text)', 'EXECUTE') as authenticated_can_execute;

select tenant_id, legal_entity_code, account_role
from public.onexa_customer_receipt_configuration_gaps
order by tenant_id, legal_entity_code, account_role;

select tenant_id, legal_entity_id, document_number, reconciliation_status,
  invoiced_amount, collected_amount, outstanding_amount
from public.onexa_customer_receivables_reconciliation
where reconciliation_status <> 'reconciled' or outstanding_amount < 0
order by tenant_id, legal_entity_id, document_number;
