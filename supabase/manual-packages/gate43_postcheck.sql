-- Read-only. All permissions and reconciliation flags must be correct.
select 'trip_scopes' object_name,to_regclass('public.onexa_fleet_trip_scopes') is not null ready
union all select 'postings',to_regclass('public.onexa_fleet_trip_cost_postings') is not null
union all select 'rpc',to_regprocedure('public.onexa_post_fleet_trip_cost(uuid,text)') is not null;
select c.relname,c.relrowsecurity as rls_enabled,
 not has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as direct_writes_denied
from pg_class c where c.oid in ('public.onexa_fleet_trip_scopes'::regclass,
  'public.onexa_fleet_trip_cost_postings'::regclass);
select coalesce(c.reloptions @> array['security_invoker=true'],false) as security_invoker
from pg_class c where c.oid='public.onexa_fleet_trip_cost_reconciliation'::regclass;
select has_function_privilege('anon','public.onexa_post_fleet_trip_cost(uuid,text)','EXECUTE') as anon_can_execute,
 has_function_privilege('authenticated','public.onexa_post_fleet_trip_cost(uuid,text)','EXECUTE') as authenticated_can_execute;
select s.trip_id,s.tenant_id,s.legal_entity_id,s.branch_id,s.cost_center_code,
  (t.id is not null and t.status::text='completed' and t.vehicle_id=s.vehicle_id
    and v.id is not null) as valid_trip_scope
from public.onexa_fleet_trip_scopes s
left join public.fleet_trips t on t.id=s.trip_id and t.tenant_id=s.tenant_id
left join public.fleet_vehicles v on v.id=s.vehicle_id and v.tenant_id=s.tenant_id;
-- The journal must still be active and match the completed trip cost.
select tenant_id,document_number,reconciliation_status,gross_total,posted_amount
from public.onexa_fleet_trip_cost_reconciliation
where status='posted' and reconciliation_status<>'reconciled';

-- Detect missing/misclassified mappings even when no role mapping row exists.
with roles(account_role) as (
  values ('logistics_or_project_cost'::text),('cash_ap_or_clearing'::text)
)
select e.tenant_id,e.code as legal_entity_code,roles.account_role,m.account_code,
  case when m.id is not null and m.is_active and a.is_active
      and a.account_type::text='detail'
      and ((roles.account_role='logistics_or_project_cost'
        and a.category::text in ('assets','expenses','cost_of_revenue'))
       or (roles.account_role='cash_ap_or_clearing' and a.category::text='liabilities'))
    then 'READY' else 'MAPPING_REQUIRED' end as mapping_status
from public.onexa_legal_entities e cross join roles
left join public.onexa_account_role_mappings m on m.tenant_id=e.tenant_id
  and m.legal_entity_id=e.id and m.account_role=roles.account_role
left join public.chart_of_accounts a on a.tenant_id=m.tenant_id and a.code=m.account_code
where e.is_active order by e.code,roles.account_role;

select reconciliation_status,count(*) as document_count
from public.onexa_fleet_trip_cost_reconciliation
where status='posted' and reconciliation_status in
  ('journal_reversed_or_missing','journal_source_or_amount_mismatch',
   'trip_scope_mismatch','journal_mismatch','amount_mismatch')
group by reconciliation_status order by reconciliation_status;
