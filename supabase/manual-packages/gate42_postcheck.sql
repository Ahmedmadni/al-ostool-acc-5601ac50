-- Gate 42 read-only checks; every ready/permission value must be correct.
select 'cost_centers' as object_name,
  to_regclass('public.onexa_project_cost_centers') is not null as ready
union all select 'cost_postings',to_regclass('public.onexa_project_cost_postings') is not null
union all select 'posting_rpc',to_regprocedure('public.onexa_post_project_cost(uuid,text)') is not null;
select c.relname, c.relrowsecurity as rls_enabled,
  not has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as direct_writes_denied
from pg_class c where c.oid in ('public.onexa_project_cost_centers'::regclass,
  'public.onexa_project_cost_postings'::regclass);
select coalesce(c.reloptions @> array['security_invoker=true'],false) as security_invoker
from pg_class c where c.oid='public.onexa_project_cost_reconciliation'::regclass;
select has_function_privilege('anon','public.onexa_post_project_cost(uuid,text)','EXECUTE') as anon_can_execute,
 has_function_privilege('authenticated','public.onexa_post_project_cost(uuid,text)','EXECUTE') as authenticated_can_execute;
select m.tenant_id,m.legal_entity_id,m.account_role,m.account_code,
  (a.code is not null and a.is_active and a.account_type::text='detail') as valid_account
from public.onexa_account_role_mappings m
left join public.chart_of_accounts a on a.tenant_id=m.tenant_id and a.code=m.account_code
where m.account_role in ('project_wip_or_expense','cost_source_or_clearing');
select tenant_id,document_number,reconciliation_status,gross_total,posted_amount
from public.onexa_project_cost_reconciliation
where status='posted' and reconciliation_status<>'reconciled';
