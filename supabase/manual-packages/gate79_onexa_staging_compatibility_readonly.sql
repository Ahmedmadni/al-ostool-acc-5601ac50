-- Gate 79: SAFE SELECT-ONLY inventory to evaluate a future separate ONEXA staging clone.
-- Never creates, migrates, backfills, seeds, posts, or modifies company data.
-- Use with authorized read access on ONEXA production to document prerequisites,
-- then separately compare with a RESTORABLE clone. Presence != deploy readiness.

-- 1. Required objects: gate 13-15 unpartitioned legacy is intentionally excluded.
with expected(stage,kind,object_name) as (
values
 ('BASE','table','public.onexa_tenants'),
 ('BASE','table','public.onexa_legal_entities'),
 ('BASE','table','public.onexa_branches'),
 ('BASE','table','public.onexa_workspace_memberships'),
 ('BASE','table','public.onexa_business_documents'),
 ('BASE','table','public.onexa_business_document_lines'),
 ('BASE','table','public.onexa_business_document_events'),
 ('BASE','table','public.onexa_journal_headers'),
 ('BASE','table','public.onexa_account_role_mappings'),
 ('BASE','table','public.chart_of_accounts'),
 ('BASE','function','onexa_private.claim_tenant_id()'),
 ('BASE','function','onexa_private.is_active_member(uuid)'),
 ('BASE','function','onexa_private.has_module_action(uuid,text,text)'),
 ('B4','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'),
 ('G42','table','public.onexa_project_cost_centers'),
 ('G42','table','public.onexa_project_cost_postings'),
 ('G42','function','public.onexa_post_project_cost(uuid,text)'),
 ('G63','table','public.onexa_approval_workflows'),
 ('G63','table','public.onexa_approval_workflow_steps'),
 ('G63','table','public.onexa_approval_instances'),
 ('G63','table','public.onexa_approval_decisions'),
 ('G63','function','onexa_private.approval_actor_matches_step(uuid,uuid,uuid)'),
 ('G63','function','public.onexa_approval_separation_required(text,text)'),
 ('G64','function','onexa_private.guard_approval_posting()'),
 ('G64','function','onexa_private.finalize_approval_posting()'),
 ('G64','function','public.onexa_can_post_business_document(uuid)'),
 ('G64','function','public.onexa_post_sales_invoice(uuid,text)'),
 ('G64','function','public.onexa_post_purchase_invoice(uuid,text)'),
 ('G64','function','public.onexa_post_customer_receipt(uuid,text)'),
 ('G64','function','public.onexa_post_supplier_payment(uuid,text)'),
 ('G64','function','public.onexa_post_bank_transfer(uuid,text)'),
 ('G64','function','public.onexa_post_fleet_trip_cost(uuid,text)'),
 ('G71','table','public.onexa_company_module_scopes'),
 ('G71','function','public.onexa_has_company_module_access(text,text)'),
 ('G72','table','public.onexa_operations_sites'),
 ('G72','table','public.onexa_operations_assets'),
 ('G72','function','public.onexa_create_operations_site(uuid,uuid,text,text)'),
 ('G72','function','public.onexa_create_operations_asset(uuid,text,text,text)'),
 ('G73','table','public.onexa_operations_work_orders'),
 ('G73','table','public.onexa_operations_work_order_events'),
 ('G73','function','public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text)'),
 ('G73','function','public.onexa_transition_operations_work_order(uuid,text,uuid,text)'),
 ('G74','table','public.onexa_native_maintenance_cost_scopes'),
 ('G74','table','public.onexa_native_maintenance_cost_attributions'),
 ('G74','view','public.onexa_native_maintenance_cost_reconciliation'),
 ('G74','function','public.onexa_save_native_maintenance_cost_scope(uuid,uuid)'),
 ('G74','function','public.onexa_attribute_posted_project_cost(uuid,uuid)'),
 ('G75','table','public.onexa_native_maintenance_unpaid_sources'),
 ('G75','view','public.onexa_native_maintenance_source_reconciliation'),
 ('G75','function','public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text)'),
 ('G75','function','public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text)'),
 ('G75','function','public.onexa_link_native_unpaid_maintenance_source(uuid,uuid)')
)
select stage,kind,object_name,
 case
   when kind='function' and to_regprocedure(object_name) is not null then 'PRESENT'
   when kind<>'function' and to_regclass(object_name) is not null then 'PRESENT'
   else 'MISSING'
 end as status,
 'PRESENCE_ONLY_NOT_APPROVED_FOR_DEPLOYMENT' as qualification
from expected order by stage,kind,object_name;

-- 2. Columns and Postgres types required by Gate42 and native G71-G75.
-- Does not dereference missing tables; suitable for pre-install diagnostics.
with expected(table_name,column_name,udt_name) as (
values
 ('onexa_tenants','tenant_id','text'),
 ('onexa_legal_entities','tenant_id','text'),
 ('onexa_legal_entities','id','uuid'),
 ('onexa_legal_entities','is_active','bool'),
 ('onexa_branches','id','uuid'),
 ('onexa_branches','tenant_id','text'),
 ('onexa_branches','legal_entity_id','uuid'),
 ('onexa_branches','is_active','bool'),
 ('onexa_business_documents','id','uuid'),
 ('onexa_business_documents','tenant_id','text'),
 ('onexa_business_documents','legal_entity_id','uuid'),
 ('onexa_business_documents','branch_id','uuid'),
 ('onexa_business_documents','source_snapshot','jsonb'),
 ('onexa_business_documents','external_reference','text'),
 ('onexa_business_documents','status','text'),
 ('onexa_business_documents','origin','text'),
 ('onexa_business_documents','gross_total','numeric'),
 ('onexa_business_documents','revision','int4'),
 ('onexa_business_documents','posted_journal_id','uuid'),
 ('onexa_journal_headers','id','uuid'),
 ('onexa_journal_headers','tenant_id','text'),
 ('onexa_journal_headers','legal_entity_id','uuid'),
 ('onexa_journal_headers','state','text'),
 ('onexa_journal_headers','reversal_of_id','uuid'),
 ('onexa_journal_headers','reversal_journal_id','uuid'),
 ('onexa_journal_headers','source_revision','int4'),
 ('onexa_account_role_mappings','tenant_id','text'),
 ('onexa_account_role_mappings','legal_entity_id','uuid'),
 ('onexa_account_role_mappings','account_role','text'),
 ('onexa_account_role_mappings','account_code','text'),
 ('onexa_approval_instances','tenant_id','text'),
 ('onexa_approval_instances','document_id','uuid'),
 ('onexa_approval_instances','status','text'),
 ('onexa_approval_workflow_steps','action_key','text'),
 ('onexa_approval_decisions','decision','text')
)
select e.table_name,e.column_name,e.udt_name as required_pg_type,
 c.udt_name as observed_pg_type,
 case when c.column_name is null then 'MISSING_COLUMN'
      when c.udt_name<>e.udt_name then 'TYPE_MISMATCH'
      else 'PRESENT' end as status
from expected e
left join information_schema.columns c
 on c.table_schema='public' and c.table_name=e.table_name
 and c.column_name=e.column_name
order by e.table_name,e.column_name;

-- 3. Installed tenant-bearing table policies: warning if RLS disabled.
select cls.relname as table_name,cls.relrowsecurity as rls_enabled,
 cls.relforcerowsecurity as rls_force,
 count(pol.policyname) as policy_count,
 case when not cls.relrowsecurity then 'RLS_DISABLED' else 'INSPECT_POLICIES' end as status
from pg_class cls
join pg_namespace ns on ns.oid=cls.relnamespace
left join pg_policies pol on pol.schemaname=ns.nspname
  and pol.tablename=cls.relname
where ns.nspname='public'
  and cls.relkind in ('r','p')
  and cls.relname in (
   'onexa_legal_entities','onexa_branches','onexa_business_documents',
   'onexa_project_cost_centers','onexa_project_cost_postings',
   'onexa_company_module_scopes','onexa_operations_sites',
   'onexa_operations_assets','onexa_operations_work_orders',
   'onexa_operations_work_order_events',
   'onexa_native_maintenance_cost_scopes',
   'onexa_native_maintenance_cost_attributions',
   'onexa_native_maintenance_unpaid_sources'
  )
group by cls.relname,cls.relrowsecurity,cls.relforcerowsecurity
order by cls.relname;

-- 4. Required financial account mappings, counts only (no GL or customer data).
-- Do NOT auto-create accounts based on this report.
select e.id as legal_entity_id,
 count(m.id) filter (where m.account_role='project_wip_or_expense' and m.is_active) as active_project_expense_mappings,
 count(m.id) filter (where m.account_role='cost_source_or_clearing' and m.is_active) as active_clearing_mappings,
 case when count(m.id) filter (where m.account_role='project_wip_or_expense' and m.is_active)>0
  and count(m.id) filter (where m.account_role='cost_source_or_clearing' and m.is_active)>0
  then 'NEEDS_SEPARATE_ACCOUNT_VALIDATION'
  else 'MISSING_REQUIRED_FINANCE_MAPPING'
 end as status
from public.onexa_legal_entities e
left join public.onexa_account_role_mappings m
 on m.tenant_id=e.tenant_id and m.legal_entity_id=e.id
 and m.account_role in ('project_wip_or_expense','cost_source_or_clearing')
group by e.id,e.tenant_id
order by e.tenant_id,e.id;

-- 5. Existing indexes/constraints affecting same-tenant composite FKs;
-- examine DDL/locks on a disposable clone before migrations.
select tc.table_name,tc.constraint_name,tc.constraint_type,
 string_agg(kcu.column_name,',' order by kcu.ordinal_position) as columns
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
 on kcu.constraint_name=tc.constraint_name
 and kcu.constraint_schema=tc.constraint_schema
 and kcu.table_schema=tc.table_schema
 and kcu.table_name=tc.table_name
where tc.table_schema='public'
  and tc.constraint_type in ('PRIMARY KEY','UNIQUE','FOREIGN KEY')
  and tc.table_name in ('onexa_legal_entities','onexa_branches',
    'onexa_business_documents','onexa_approval_instances')
group by tc.table_name,tc.constraint_name,tc.constraint_type
order by tc.table_name,tc.constraint_name;

-- Completion of SELECT-only diagnostics is NOT permission to apply any migration.
