-- Gate 74 READ-ONLY acceptance check. Run AFTER approved G42 + G71-74 SQL.
-- First section can be run before migration to see missing prerequisites.
with required(stage,object_kind,object_name) as (
 values
 ('G42','table','public.onexa_project_cost_centers'),
 ('G42','table','public.onexa_project_cost_postings'),
 ('B4','table','public.onexa_journal_headers'),
 ('G71','table','public.onexa_company_module_scopes'),
 ('G72','table','public.onexa_operations_sites'),
 ('G73','table','public.onexa_operations_work_orders'),
 ('G74','table','public.onexa_native_maintenance_cost_scopes'),
 ('G74','table','public.onexa_native_maintenance_cost_attributions'),
 ('G74','view','public.onexa_native_maintenance_cost_reconciliation'),
 ('G74','view','public.onexa_native_maintenance_work_order_cost_totals'),
 ('G74','function','public.onexa_save_native_maintenance_cost_scope(uuid,uuid)'),
 ('G74','function','public.onexa_attribute_posted_project_cost(uuid,uuid)')
)
select stage,object_name,
 case when object_kind='function' then to_regprocedure(object_name) is not null
   else to_regclass(object_name) is not null end as installed,
 'PRESENCE_ONLY_NOT_UAT' as check_qualification
from required order by stage,object_name;

-- Only after Gate 74 installation; all safety rows below must be true.
select c.relname as table_name,c.relrowsecurity as rls_enabled,
 has_table_privilege('anon',c.oid,'SELECT') as anon_can_select,
 has_table_privilege('authenticated',c.oid,'SELECT') as authenticated_can_select,
 has_table_privilege('authenticated',c.oid,'INSERT') as authenticated_can_insert,
 has_table_privilege('authenticated',c.oid,'UPDATE') as authenticated_can_update,
 has_table_privilege('authenticated',c.oid,'DELETE') as authenticated_can_delete
from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
where ns.nspname='public' and c.relname in
('onexa_native_maintenance_cost_scopes','onexa_native_maintenance_cost_attributions');

select c.conname,c.contype,c.convalidated,
 pg_get_constraintdef(c.oid) as definition
from pg_constraint c
where c.conrelid in
  (to_regclass('public.onexa_native_maintenance_cost_scopes'),
   to_regclass('public.onexa_native_maintenance_cost_attributions'))
 and c.conname in
  ('onexa_native_cost_scope_work_order_fk','onexa_native_cost_scope_center_fk',
   'onexa_native_cost_attr_scope_fk','onexa_native_cost_attr_posted_source_fk',
   'onexa_native_cost_attr_document_once_uq')
order by c.conname;

select t.tgname,t.tgenabled
from pg_trigger t where t.tgrelid in
 (to_regclass('public.onexa_native_maintenance_cost_scopes'),
  to_regclass('public.onexa_native_maintenance_cost_attributions'))
 and not t.tgisinternal order by t.tgname;

select c.relname,c.reloptions
from pg_class c
where c.oid in
 (to_regclass('public.onexa_native_maintenance_cost_reconciliation'),
  to_regclass('public.onexa_native_maintenance_work_order_cost_totals'));

select
 has_function_privilege('anon','public.onexa_save_native_maintenance_cost_scope(uuid,uuid)','EXECUTE') as anon_can_map_center,
 has_function_privilege('anon','public.onexa_attribute_posted_project_cost(uuid,uuid)','EXECUTE') as anon_can_attribute_cost,
 has_function_privilege('authenticated','public.onexa_attribute_posted_project_cost(uuid,uuid)','EXECUTE') as authenticated_can_request_attribution;

-- Every row in the following result is a currently unresolved finance issue.
-- "reversed" sources must not contribute to a reconciled work order cost.
select *
from public.onexa_native_maintenance_cost_reconciliation
where reconciliation_status<>'reconciled'
order by work_order_id,attribution_id;

-- Duplicate project-cost documents are prohibited by DB unique constraint.
select tenant_id,document_id,count(*) as duplicate_count
from public.onexa_native_maintenance_cost_attributions
group by tenant_id,document_id having count(*)>1;

-- Purely attributed costs, not newly accrued GL costs.
select * from public.onexa_native_maintenance_work_order_cost_totals
order by tenant_id,work_order_id;
