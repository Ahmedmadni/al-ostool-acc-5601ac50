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
-- Any posted source whose original B4 journal has been reversed cannot be
-- treated as a recognized project cost in the operational reconciliation.
-- Report missing and misclassified accounting role mappings, even when
-- no mapping row exists yet. Do not invent fallback GL account codes.
with roles(account_role) as (
  values ('project_wip_or_expense'::text),('cost_source_or_clearing'::text)
)
select e.tenant_id,e.code as entity_code,roles.account_role,m.account_code,
  case when m.id is not null and m.is_active and a.is_active
      and a.account_type::text='detail' and
      ((roles.account_role='project_wip_or_expense'
        and a.category::text in ('assets','expenses','cost_of_revenue'))
        or (roles.account_role='cost_source_or_clearing' and a.category::text='liabilities'))
    then 'READY' else 'MAPPING_REQUIRED' end as mapping_status
from public.onexa_legal_entities e
cross join roles
left join public.onexa_account_role_mappings m on m.tenant_id=e.tenant_id
  and m.legal_entity_id=e.id and m.account_role=roles.account_role
left join public.chart_of_accounts a on a.tenant_id=m.tenant_id and a.code=m.account_code
where e.is_active order by e.code,roles.account_role;

select tenant_id,document_number,reconciliation_status,gross_total,posted_amount
from public.onexa_project_cost_reconciliation
where status='posted' and reconciliation_status<>'reconciled';

select reconciliation_status,count(*) as document_count
from public.onexa_project_cost_reconciliation
where status='posted' and reconciliation_status in
  ('journal_reversed_or_missing','journal_source_or_amount_mismatch',
   'project_scope_mismatch','journal_mismatch','amount_mismatch')
group by reconciliation_status order by reconciliation_status;
