-- Gate73 acceptance diagnostics (READ ONLY; run AFTER approved SQL install).
-- Before installation: only use the general capability inventory instead.
with checks(name,ready) as (
values
 ('work_orders_table',to_regclass('public.onexa_operations_work_orders') is not null),
 ('work_order_events_table',to_regclass('public.onexa_operations_work_order_events') is not null),
 ('work_order_sequence',to_regclass('public.onexa_operations_work_order_seq') is not null),
 ('work_order_create_rpc',to_regprocedure('public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text)') is not null),
 ('work_order_transition_rpc',to_regprocedure('public.onexa_transition_operations_work_order(uuid,text,uuid,text)') is not null),
 ('work_order_rls',exists(select 1 from pg_class where oid=to_regclass('public.onexa_operations_work_orders') and relrowsecurity)),
 ('work_order_events_rls',exists(select 1 from pg_class where oid=to_regclass('public.onexa_operations_work_order_events') and relrowsecurity)),
 ('work_order_state_guard',exists(select 1 from pg_trigger where tgrelid=to_regclass('public.onexa_operations_work_orders')
   and tgname='onexa_guard_native_work_order_state' and tgenabled in ('O','A') and not tgisinternal)),
 ('work_order_append_only_guard',exists(select 1 from pg_trigger where tgrelid=to_regclass('public.onexa_operations_work_order_events')
   and tgname='onexa_guard_native_work_order_events' and tgenabled in ('O','A') and not tgisinternal)),
 ('work_order_composite_scope_fks',(select count(*) from pg_constraint
    where conrelid=to_regclass('public.onexa_operations_work_orders') and contype='f' and convalidated
      and conname in ('onexa_wo_tenant_entity_branch_site_fk',
        'onexa_wo_tenant_entity_branch_site_asset_fk','onexa_wo_tenant_customer_fk',
        'onexa_wo_tenant_contract_customer_fk'))=4),
 ('work_order_event_tenant_fk',exists(select 1 from pg_constraint
   where conrelid=to_regclass('public.onexa_operations_work_order_events')
     and conname='onexa_wo_event_tenant_order_fk' and contype='f' and convalidated))
)
select name,case when ready then 'READY' else 'MISSING' end as status
from checks order by name;

select
 has_table_privilege('anon','public.onexa_operations_work_orders','SELECT') as anon_can_read_work_orders,
 has_table_privilege('authenticated','public.onexa_operations_work_orders','SELECT') as authenticated_can_read_work_orders,
 has_table_privilege('authenticated','public.onexa_operations_work_orders','INSERT,UPDATE,DELETE') as authenticated_can_write_work_orders,
 has_table_privilege('authenticated','public.onexa_operations_work_order_events','INSERT,UPDATE,DELETE') as authenticated_can_write_events,
 has_function_privilege('anon','public.onexa_create_operations_work_order(uuid,uuid,uuid,uuid,text,text)','EXECUTE') as anon_can_create_order,
 has_function_privilege('anon','public.onexa_transition_operations_work_order(uuid,text,uuid,text)','EXECUTE') as anon_can_transition_order;

-- Must return zero mismatched parent records. The composites should prevent them,
-- including under privileged service-role operations.
select w.id,w.tenant_id,w.legal_entity_id,w.branch_id,w.site_id,w.asset_id,w.customer_id,w.contract_id
from public.onexa_operations_work_orders w
left join public.onexa_operations_sites site
 on site.id=w.site_id and site.tenant_id=w.tenant_id and site.legal_entity_id=w.legal_entity_id and site.branch_id=w.branch_id
left join public.onexa_operations_assets asset
 on asset.id=w.asset_id and asset.tenant_id=w.tenant_id and asset.legal_entity_id=w.legal_entity_id
 and asset.branch_id=w.branch_id and asset.site_id=w.site_id
left join public.customers customer
 on customer.id=w.customer_id and customer.tenant_id=w.tenant_id
left join public.contracts contract
 on contract.id=w.contract_id and contract.tenant_id=w.tenant_id and contract.customer_id=w.customer_id
where site.id is null or (w.asset_id is not null and asset.id is null)
 or customer.id is null or (w.contract_id is not null and contract.id is null);

-- Must return zero missing creation/history events and completed/accepted audit gaps.
select w.id,w.tenant_id,w.status
from public.onexa_operations_work_orders w
where not exists (select 1 from public.onexa_operations_work_order_events e
  where e.work_order_id=w.id and e.tenant_id=w.tenant_id and e.from_status is null and e.to_status='draft')
or (w.status in ('completed','accepted')
    and (w.completed_at is null or w.completed_by is null or nullif(btrim(w.completion_note),'') is null))
or (w.status='accepted' and (w.accepted_at is null or w.accepted_by is null
    or w.accepted_by in (w.created_by,w.completed_by)));
