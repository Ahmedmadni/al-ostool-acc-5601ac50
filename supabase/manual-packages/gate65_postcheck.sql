-- Gate 65 read-only postcheck. Every status must be READY; final query must return zero rows.
select check_name,status from (
  values
    ('posting_runs_table',case when to_regclass('public.onexa_inventory_posting_runs') is not null then 'READY' else 'MISSING' end),
    ('posting_rpc',case when to_regprocedure('public.onexa_post_inventory_document(uuid,text)') is not null then 'READY' else 'MISSING' end),
    ('reconciliation_view',case when to_regclass('public.onexa_inventory_document_reconciliation') is not null then 'READY' else 'MISSING' end),
    ('gate64_guard',case when to_regprocedure('onexa_private.guard_approval_posting()') is not null then 'READY' else 'MISSING' end),
    ('inventory_reversal_guard',case when
      to_regprocedure('public.onexa_guard_inventory_journal_reversal()') is not null
      and exists (select 1 from pg_trigger t
        where t.tgrelid=to_regclass('public.onexa_journal_headers')
          and t.tgname='onexa_guard_inventory_journal_reversal'
          and t.tgenabled <> 'D' and not t.tgisinternal)
      then 'READY' else 'MISSING' end),
    ('inventory_balances',case when to_regclass('public.onexa_inventory_balances') is not null then 'READY' else 'MISSING' end)
) checks(check_name,status) order by check_name;

select c.relname,c.relrowsecurity as rls_enabled,
  not has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as direct_writes_denied
from pg_class c where c.oid='public.onexa_inventory_posting_runs'::regclass;

select c.relname,
  not has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as legacy_direct_writes_denied
from pg_class c where c.oid in (
  'public.inventory_receipts'::regclass,'public.inventory_receipt_lines'::regclass,
  'public.inventory_issues'::regclass,'public.inventory_issue_lines'::regclass,
  'public.inventory_stock_layers'::regclass
) order by c.relname;

select coalesce(c.reloptions @> array['security_invoker=true'],false) as reconciliation_security_invoker
from pg_class c where c.oid='public.onexa_inventory_document_reconciliation'::regclass;

select has_function_privilege('anon','public.onexa_post_inventory_document(uuid,text)','EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated','public.onexa_post_inventory_document(uuid,text)','EXECUTE') as authenticated_can_execute;

select tenant_id,legal_entity_id,account_role,'MISSING' as status
from public.onexa_inventory_posting_configuration_gaps order by tenant_id,legal_entity_id,account_role;

select tenant_id,document_number,document_type,reconciliation_status,
  posted_inventory_value,movement_inventory_value,expected_movement_count,actual_movement_count
from public.onexa_inventory_document_reconciliation
where status='posted' and reconciliation_status<>'reconciled';

-- Reversed/missing GL journals must not be interpreted as valid stock valuation.
-- Stock movement reversal is deliberately unavailable without compensation.
select reconciliation_status,count(*) as document_count
from public.onexa_inventory_document_reconciliation
where status='posted'
  and reconciliation_status in (
    'journal_reversed_or_missing','journal_source_or_value_mismatch',
    'movement_missing','inventory_value_mismatch'
  )
group by reconciliation_status order by reconciliation_status;
