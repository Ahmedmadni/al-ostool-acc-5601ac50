-- Gate75 READ-ONLY inventory and acceptance postflight. Nothing here mutates data.
with required(stage,kind,signature) as (values
 ('G42','table','public.onexa_project_cost_postings'),
 ('G71','table','public.onexa_company_module_scopes'),
 ('G72','table','public.onexa_operations_sites'),
 ('G73','table','public.onexa_operations_work_orders'),
 ('G74','table','public.onexa_native_maintenance_cost_scopes'),
 ('G74','table','public.onexa_native_maintenance_cost_attributions'),
 ('G75','table','public.onexa_native_maintenance_unpaid_sources'),
 ('G75','view','public.onexa_native_maintenance_source_reconciliation'),
 ('G75','procedure','public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text)'),
 ('G75','procedure','public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text)'),
 ('G75','procedure','public.onexa_link_native_unpaid_maintenance_source(uuid,uuid)')
)
select stage,signature,
 case when kind='procedure' then to_regprocedure(signature) is not null
      else to_regclass(signature) is not null end as installed,
 'OBJECT_PRESENCE_NOT_ACCEPTANCE' as qualification
from required order by stage,signature;

-- Run remaining queries ONLY after all Gate75 objects exist.
select c.relname as table_name,c.relrowsecurity as rls_enabled,
 has_table_privilege('anon',c.oid,'SELECT') as anon_can_read,
 has_table_privilege('authenticated',c.oid,'SELECT') as authenticated_can_read,
 has_table_privilege('authenticated',c.oid,'INSERT') as authenticated_can_insert,
 has_table_privilege('authenticated',c.oid,'UPDATE') as authenticated_can_update,
 has_table_privilege('authenticated',c.oid,'DELETE') as authenticated_can_delete
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname='onexa_native_maintenance_unpaid_sources';

select conname,contype,convalidated,pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid=to_regclass('public.onexa_native_maintenance_unpaid_sources')
and conname in ('onexa_native_unpaid_claim_scope_fk',
 'onexa_native_unpaid_claim_document_fk',
 'onexa_native_unpaid_claim_tenant_source_unique',
 'onexa_native_unpaid_claim_document_once')
order by conname;

select t.tgname,t.tgenabled,t.tgisinternal
from pg_trigger t
where (t.tgrelid=to_regclass('public.onexa_native_maintenance_unpaid_sources')
  and t.tgname='onexa_guard_native_unpaid_source_write')
or (t.tgrelid=to_regclass('public.onexa_business_documents')
  and t.tgname='onexa_guard_native_claim_business_document');

select c.relname,c.reloptions
from pg_class c
where c.oid=to_regclass('public.onexa_native_maintenance_source_reconciliation');

select has_function_privilege('anon',
 'public.onexa_register_native_unpaid_maintenance_source(uuid,text,text,numeric,text)','EXECUTE') as anon_can_register,
 has_function_privilege('anon',
 'public.onexa_review_native_unpaid_maintenance_source(uuid,boolean,text)','EXECUTE') as anon_can_review,
 has_function_privilege('anon',
 'public.onexa_link_native_unpaid_maintenance_source(uuid,uuid)','EXECUTE') as anon_can_link;

-- Must have no same-tenant/entity/source-reference collisions, and no
-- two linked sources pointing at the same G42 document.
select tenant_id,legal_entity_id,source_reference,count(*) as duplicate_count
from public.onexa_native_maintenance_unpaid_sources
group by tenant_id,legal_entity_id,source_reference having count(*)>1;

select tenant_id,linked_document_id,count(*) as duplicate_count
from public.onexa_native_maintenance_unpaid_sources
where linked_document_id is not null
group by tenant_id,linked_document_id having count(*)>1;

-- Reconciliation with reversed or mismatched GL journals must NEVER be
-- presented as reconciled. Examine every exception with finance.
select tenant_id,legal_entity_id,work_order_id,id,source_reference,status,
       current_reconciliation_status,linked_document_id
from public.onexa_native_maintenance_source_reconciliation
where status='linked' and current_reconciliation_status<>'reconciled'
order by tenant_id,work_order_id,id;

-- Approval completeness, for financial review, not automated approval.
select id,tenant_id,source_reference,status,created_by,reviewed_by,linked_document_id
from public.onexa_native_maintenance_unpaid_sources
where (status in ('approved','linked') and (reviewed_by is null or reviewed_by=created_by))
  or (status='linked' and linked_document_id is null);

-- Verify business-document active claim key uniqueness is installed.
select indexname,indexdef from pg_indexes
where schemaname='public' and tablename='onexa_business_documents'
and indexname='onexa_gate75_one_active_document_per_claim_uq';
