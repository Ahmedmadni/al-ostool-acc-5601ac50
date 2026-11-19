-- ONEXA module SQL dependency/installation inventory — STRICT SELECT ONLY.
-- This reads ONLY PostgreSQL catalog objects, functions and trigger metadata;
-- NEVER production ledger rows, journal amounts, invoices, tenants or clients.
-- Passing a catalog existence check is NOT finance UAT or deployment approval.
-- Built against version-pinned source manifest, no automatic SQL migrations.
with
nodes(node_id,wave,policy,sql_package,depends_on) as (
  values
    ('b4',0,'foundation','',''),
    ('g35',1,'standard','supabase/manual-packages/gate35_sales_inventory_posting.sql','b4'),
    ('g37',1,'standard','supabase/manual-packages/gate37_payroll_gl_posting.sql','b4'),
    ('g38',1,'standard','supabase/manual-packages/gate38_fixed_assets_gl_posting.sql','b4'),
    ('g41',1,'standard','supabase/manual-packages/gate41_bank_transfers.sql','b4'),
    ('g42',1,'standard','supabase/manual-packages/gate42_project_costs.sql','b4'),
    ('g43',1,'standard','supabase/manual-packages/gate43_fleet_trip_costs.sql','b4'),
    ('g58',1,'manual_journal_source_fix','supabase/manual-packages/gate58_manual_journal_workflow.sql','b4'),
    ('g62',1,'standard','supabase/manual-packages/gate62_tenant_approval_workflows.sql','b4'),
    ('g63',2,'standard','supabase/manual-packages/gate63_approval_workflow_runtime.sql','g62'),
    ('g36',2,'standard','supabase/manual-packages/gate36_procurement_inventory_posting.sql','g35'),
    ('g39',2,'standard','supabase/manual-packages/gate39_customer_receipts.sql','g35'),
    ('g40',3,'standard','supabase/manual-packages/gate40_supplier_payments.sql','g36'),
    ('g64',4,'strict_posting_bridge','supabase/manual-packages/gate64_approval_posting_bridge.sql','g35,g36,g39,g40,g41,g42,g43,g63'),
    ('g65',5,'standard','supabase/manual-packages/gate65_inventory_gl_posting.sql','g35,g64'),
    ('g67',5,'legacy_real_estate_review','supabase/manual-packages/gate67_lease_invoice_receipt_posting.sql','g64'),
    ('g66',6,'saas_forbidden_legacy_engine','supabase/manual-packages/gate66_maintenance_work_order_costs.sql','g42,g64')
),
requirements(node_id,object_kind,object_ref,extra) as (
  values
    ('b4','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('b4','function','public.onexa_reverse_journal(uuid,date,text,text)',''),
    ('b4','table','public.onexa_journal_headers',''),
    ('b4','table','public.onexa_journal_lines',''),
    ('b4','table','public.onexa_posting_registry',''),
    ('g35','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g35','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g35','table','public.onexa_account_role_mappings',''),
    ('g37','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g37','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g37','function','public.hr_payroll_attendance_is_stale(uuid)',''),
    ('g37','function','public.hr_payroll_employer_cost(numeric,numeric,numeric,numeric,numeric,numeric,numeric)',''),
    ('g37','table','public.hr_payroll_runs',''),
    ('g37','table','public.hr_payroll_lines',''),
    ('g37','table','public.cost_entries',''),
    ('g37','table','public.onexa_account_role_mappings',''),
    ('g38','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g38','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g38','function','onexa_private.claim_tenant_id()',''),
    ('g38','table','public.fixed_assets',''),
    ('g38','table','public.onexa_account_role_mappings',''),
    ('g41','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g41','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g41','table','public.onexa_business_documents',''),
    ('g41','table','public.onexa_journal_headers',''),
    ('g41','table','public.chart_of_accounts',''),
    ('g42','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g42','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g42','table','public.onexa_business_documents',''),
    ('g42','table','public.onexa_journal_headers',''),
    ('g42','table','public.onexa_account_role_mappings',''),
    ('g43','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g43','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g43','table','public.fleet_trips',''),
    ('g43','table','public.fleet_vehicles',''),
    ('g43','table','public.onexa_business_documents',''),
    ('g43','table','public.onexa_journal_headers',''),
    ('g43','column','public.fleet_trips','tenant_id'),
    ('g43','column','public.fleet_vehicles','tenant_id'),
    ('g58','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g58','function','public.onexa_reverse_journal(uuid,date,text,text)',''),
    ('g58','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g58','function','onexa_private.claim_tenant_id()',''),
    ('g58','table','public.chart_of_accounts',''),
    ('g58','table','public.onexa_legal_entities',''),
    ('g58','table','public.onexa_branches',''),
    ('g62','table','public.onexa_workspace',''),
    ('g62','table','public.onexa_workspace_memberships',''),
    ('g62','function','onexa_private.claim_tenant_id()',''),
    ('g63','table','public.onexa_approval_workflows',''),
    ('g63','table','public.onexa_approval_workflow_steps',''),
    ('g63','table','public.onexa_business_documents',''),
    ('g63','function','public.onexa_approval_separation_required(text,text)',''),
    ('g36','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g36','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g36','function','onexa_private.claim_tenant_id()',''),
    ('g36','table','public.onexa_business_documents',''),
    ('g36','table','public.onexa_business_document_lines',''),
    ('g36','table','public.onexa_business_document_events',''),
    ('g36','table','public.onexa_legal_entities',''),
    ('g36','table','public.onexa_inventory_balances',''),
    ('g36','table','public.onexa_inventory_movements',''),
    ('g36','table','public.onexa_account_role_mappings',''),
    ('g36','table','public.chart_of_accounts',''),
    ('g39','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g39','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g39','table','public.onexa_sales_posting_runs',''),
    ('g40','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g40','function','onexa_private.has_module_action(uuid,text,text)',''),
    ('g40','function','onexa_private.claim_tenant_id()',''),
    ('g40','table','public.onexa_purchase_posting_runs',''),
    ('g40','table','public.onexa_journal_headers',''),
    ('g40','table','public.onexa_business_documents',''),
    ('g40','table','public.onexa_business_document_lines',''),
    ('g40','table','public.onexa_business_document_events',''),
    ('g40','table','public.onexa_legal_entities',''),
    ('g40','table','public.onexa_account_role_mappings',''),
    ('g40','table','public.chart_of_accounts',''),
    ('g64','function','public.onexa_approval_separation_required(text,text)',''),
    ('g64','function','onexa_private.approval_actor_matches_step(uuid,uuid,uuid)',''),
    ('g64','function','public.onexa_post_sales_invoice(uuid,text)',''),
    ('g64','function','public.onexa_post_purchase_invoice(uuid,text)',''),
    ('g64','function','public.onexa_post_customer_receipt(uuid,text)',''),
    ('g64','function','public.onexa_post_supplier_payment(uuid,text)',''),
    ('g64','function','public.onexa_post_bank_transfer(uuid,text)',''),
    ('g64','function','public.onexa_post_project_cost(uuid,text)',''),
    ('g64','function','public.onexa_post_fleet_trip_cost(uuid,text)',''),
    ('g64','table','public.onexa_approval_instances',''),
    ('g64','table','public.onexa_approval_decisions',''),
    ('g65','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g65','function','public.onexa_approval_separation_required(text,text)',''),
    ('g65','function','onexa_private.guard_approval_posting()',''),
    ('g65','table','public.onexa_inventory_balances',''),
    ('g65','table','public.onexa_inventory_movements',''),
    ('g65','table','public.onexa_business_documents',''),
    ('g65','table','public.onexa_journal_headers',''),
    ('g65','trigger','public.onexa_business_documents','onexa_guard_approval_posting'),
    ('g67','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g67','function','public.re_has_company_access(uuid)',''),
    ('g67','function','public.onexa_approval_separation_required(text,text)',''),
    ('g67','function','onexa_private.guard_approval_posting()',''),
    ('g67','table','public.onexa_business_documents',''),
    ('g67','table','public.onexa_journal_headers',''),
    ('g67','table','public.re_tenant_leases',''),
    ('g67','table','public.re_lease_schedules',''),
    ('g67','table','public.re_properties',''),
    ('g67','trigger','public.onexa_business_documents','onexa_guard_approval_posting'),
    ('g66','function','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',''),
    ('g66','function','public.ops_has_company_access(uuid)',''),
    ('g66','function','public.onexa_approval_separation_required(text,text)',''),
    ('g66','function','onexa_private.guard_approval_posting()',''),
    ('g66','table','public.onexa_business_documents',''),
    ('g66','table','public.onexa_journal_headers',''),
    ('g66','table','public.onexa_project_cost_centers',''),
    ('g66','table','public.ops_work_orders',''),
    ('g66','trigger','public.onexa_business_documents','onexa_guard_approval_posting')
),
targets(node_id,object_kind,object_ref,extra) as (
  values
    ('g35','function','public.onexa_post_sales_invoice(uuid,text)',''),
    ('g37','function','public.onexa_post_payroll_run(uuid,uuid,uuid,text)',''),
    ('g38','function','public.onexa_post_asset_depreciation(uuid,text,date)',''),
    ('g41','function','public.onexa_post_bank_transfer(uuid,text)',''),
    ('g42','function','public.onexa_post_project_cost(uuid,text)',''),
    ('g43','function','public.onexa_post_fleet_trip_cost(uuid,text)',''),
    ('g58','function','public.onexa_post_manual_journal(uuid)',''),
    ('g62','function','public.onexa_approval_separation_required(text,text)',''),
    ('g62','table','public.onexa_approval_workflows',''),
    ('g62','table','public.onexa_approval_workflow_steps',''),
    ('g63','function','onexa_private.approval_actor_matches_step(uuid,uuid,uuid)',''),
    ('g63','table','public.onexa_approval_instances',''),
    ('g63','table','public.onexa_approval_decisions',''),
    ('g36','function','public.onexa_post_purchase_invoice(uuid,text)',''),
    ('g39','function','public.onexa_post_customer_receipt(uuid,text)',''),
    ('g40','function','public.onexa_post_supplier_payment(uuid,text)',''),
    ('g64','function','onexa_private.guard_approval_posting()',''),
    ('g64','function','onexa_private.finalize_approval_posting()',''),
    ('g65','function','public.onexa_post_inventory_document(uuid,text)',''),
    ('g67','function','public.onexa_post_lease_invoice(uuid,text)',''),
    ('g67','function','public.onexa_post_lease_receipt(uuid,text)',''),
    ('g66','function','public.onexa_post_maintenance_work_order_cost(uuid,text)','')
),
objects as (
  select 'required'::text as class,r.node_id,r.object_kind,r.object_ref,r.extra
  from requirements r
  union all
  select 'installed_target',t.node_id,t.object_kind,t.object_ref,t.extra
  from targets t
),
probes as (
  select o.*,
    case
      when o.object_kind='table' then to_regclass(o.object_ref) is not null
      when o.object_kind='function' then to_regprocedure(o.object_ref) is not null
      when o.object_kind='column' then exists (
        select 1 from information_schema.columns col
        where col.table_schema=split_part(o.object_ref,'.',1)
          and col.table_name=split_part(o.object_ref,'.',2)
          and col.column_name=o.extra
      )
      when o.object_kind='trigger' then exists (
        select 1 from pg_trigger t
        where t.tgrelid=to_regclass(o.object_ref)
          and t.tgname=o.extra and not t.tgisinternal and t.tgenabled<>'D'
      )
      else false
    end as present
  from objects o
),
summary as (
  select n.node_id,n.wave,n.policy,n.sql_package,n.depends_on,
    count(*) filter (where p.class='required')::integer as requirements_count,
    count(*) filter (where p.class='required' and not p.present)::integer as missing_requirements_count,
    coalesce(string_agg(
      case when p.class='required' and not p.present
        then p.object_kind||':'||p.object_ref||
          case when p.extra='' then '' else ':'||p.extra end end,
      '; ' order by p.object_kind,p.object_ref,p.extra
    ),'') as missing_requirements,
    count(*) filter (where p.class='installed_target')::integer as installed_target_count,
    count(*) filter (where p.class='installed_target' and not p.present)::integer as missing_target_count,
    coalesce(string_agg(
      case when p.class='installed_target' and not p.present
        then p.object_kind||':'||p.object_ref end,
      '; ' order by p.object_kind,p.object_ref,p.extra
    ),'') as missing_targets
  from nodes n
  left join probes p on p.node_id=n.node_id
  group by n.node_id,n.wave,n.policy,n.sql_package,n.depends_on
),
source_types as (
  select exists(
    select 1 from pg_constraint c
    where c.conrelid=to_regclass('public.onexa_journal_headers')
      and c.conname='onexa_journal_headers_source_document_type_check'
      and pg_get_constraintdef(c.oid,true) like '%''manual_journal''%'
  ) as manual_allowed
)
select s.node_id,s.wave,s.sql_package,s.depends_on,
  s.requirements_count,s.missing_requirements_count,s.missing_requirements,
  s.installed_target_count,s.missing_target_count,s.missing_targets,
  case
    when s.policy='saas_forbidden_legacy_engine'
      and to_regclass('public.onexa_tenants') is not null
      then 'SAAS_LEGACY_WRITER_FORBIDDEN'
    when s.policy='legacy_real_estate_review'
      then 'LEGACY_REAL_ESTATE_COMPAT_REVIEW'
    when s.policy='manual_journal_source_fix' and not (select manual_allowed from source_types)
      then 'MANUAL_JOURNAL_ALLOWLIST_BLOCKED'
    when s.missing_requirements_count>0 then 'PREREQUISITES_MISSING'
    when s.missing_target_count>0 then 'INSTALLATION_MISSING'
    else 'CATALOG_PRESENT_STAGING_REQUIRED'
  end as dependency_status
from summary s order by s.wave,s.node_id;
