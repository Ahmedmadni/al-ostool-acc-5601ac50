-- Gate 66 read-only postcheck. First result must be READY; gap/error queries return zero rows.
select check_name,status from (values
  ('scope_table',case when to_regclass('public.onexa_maintenance_work_order_scopes') is not null then 'READY' else 'MISSING' end),
  ('posting_table',case when to_regclass('public.onexa_maintenance_work_order_cost_postings') is not null then 'READY' else 'MISSING' end),
  ('save_scope_rpc',case when to_regprocedure('public.onexa_save_maintenance_work_order_scope(uuid,uuid)') is not null then 'READY' else 'MISSING' end),
  ('posting_rpc',case when to_regprocedure('public.onexa_post_maintenance_work_order_cost(uuid,text)') is not null then 'READY' else 'MISSING' end),
  ('reconciliation_view',case when to_regclass('public.onexa_maintenance_work_order_cost_reconciliation') is not null then 'READY' else 'MISSING' end),
  ('gate64_guard',case when to_regprocedure('onexa_private.guard_approval_posting()') is not null
    and exists (select 1 from pg_trigger t
      where t.tgname='onexa_guard_approval_posting'
        and t.tgrelid=to_regclass('public.onexa_business_documents')
        and t.tgenabled<>'D' and not t.tgisinternal)
    then 'READY' else 'MISSING' end)
) checks(check_name,status) order by check_name;

select c.relname,c.relrowsecurity as rls_enabled,
  not has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as direct_writes_denied
from pg_class c where c.oid in (
  'public.onexa_maintenance_work_order_scopes'::regclass,
  'public.onexa_maintenance_work_order_cost_postings'::regclass
) order by c.relname;

select c.relname,coalesce(c.reloptions @> array['security_invoker=true'],false) as security_invoker
from pg_class c where c.oid in (
  'public.onexa_maintenance_work_order_cost_scopes'::regclass,
  'public.onexa_maintenance_work_order_cost_reconciliation'::regclass,
  'public.onexa_maintenance_posting_configuration_gaps'::regclass
) order by c.relname;

select has_function_privilege('anon','public.onexa_post_maintenance_work_order_cost(uuid,text)','EXECUTE') as anon_can_post,
  has_function_privilege('authenticated','public.onexa_post_maintenance_work_order_cost(uuid,text)','EXECUTE') as authenticated_can_post,
  has_function_privilege('anon','public.onexa_save_maintenance_work_order_scope(uuid,uuid)','EXECUTE') as anon_can_save_scope,
  has_function_privilege('authenticated','public.onexa_save_maintenance_work_order_scope(uuid,uuid)','EXECUTE') as authenticated_can_save_scope;

select tenant_id,legal_entity_id,account_role,'MISSING' as status
from public.onexa_maintenance_posting_configuration_gaps
order by tenant_id,legal_entity_id,account_role;

select scope.id,scope.tenant_id,scope.work_order_id,'INVALID_SCOPE' as status
from public.onexa_maintenance_work_order_scopes scope
left join public.onexa_project_cost_centers center
  on center.id=scope.project_cost_center_id and center.tenant_id=scope.tenant_id
left join public.ops_work_orders work_order on work_order.id=scope.work_order_id
where center.id is null or work_order.id is null
  or scope.legal_entity_id<>center.legal_entity_id or scope.branch_id<>center.branch_id;

select tenant_id,document_number,reconciliation_status,gross_total,posted_amount
from public.onexa_maintenance_work_order_cost_reconciliation
where status='posted' and reconciliation_status<>'reconciled';

-- Disaggregate ledger and project-scope exceptions for finance reconciliation.
select reconciliation_status,count(*) as document_count
from public.onexa_maintenance_work_order_cost_reconciliation
where status='posted' and reconciliation_status in
  ('journal_reversed_or_missing','journal_source_or_amount_mismatch',
   'scope_entity_branch_mismatch','journal_mismatch','amount_mismatch')
group by reconciliation_status order by reconciliation_status;
