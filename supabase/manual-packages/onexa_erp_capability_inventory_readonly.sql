-- ONEXA pilot database feature inventory (READ ONLY)
-- Codes existing in GitHub are NOT evidence of applied SQL or successful accounting acceptance.
-- Execute only against the verified Customer Data Plane; never infer a change from this inventory.
-- "INSTALLED_OBJECT" means only the named object exists; check mappings, RLS, policies, roles and UAT separately.
with required(gate_code, capability, object_kind, object_signature) as (
 values
    ('CORE', 'Tenant workspace', 'table', 'public.onexa_workspace'),
    ('CORE', 'Legal entities', 'table', 'public.onexa_legal_entities'),
    ('CORE', 'Financial periods', 'table', 'public.onexa_fiscal_periods'),
    ('CORE', 'Accounting posting engine', 'procedure', 'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'),
    ('CORE', 'Business documents', 'table', 'public.onexa_business_documents'),
    ('CORE', 'Authorized document creation', 'procedure', 'public.onexa_create_business_document(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb)'),
    ('G35', 'Sales posting', 'procedure', 'public.onexa_post_sales_invoice(uuid,text)'),
    ('G36', 'Purchase posting', 'procedure', 'public.onexa_post_purchase_invoice(uuid,text)'),
    ('G39', 'Customer receipt posting', 'procedure', 'public.onexa_post_customer_receipt(uuid,text)'),
    ('G40', 'Supplier payment posting', 'procedure', 'public.onexa_post_supplier_payment(uuid,text)'),
    ('G41', 'Bank transfers', 'procedure', 'public.onexa_post_bank_transfer(uuid,text)'),
    ('G42', 'Project cost posting', 'procedure', 'public.onexa_post_project_cost(uuid,text)'),
    ('G43', 'Fleet cost posting', 'procedure', 'public.onexa_post_fleet_trip_cost(uuid,text)'),
    ('G58', 'Manual journals', 'procedure', 'public.onexa_post_manual_journal(uuid)'),
    ('G60', 'Accountant activation', 'procedure', 'public.onexa_activate_accountant_user(uuid)'),
    ('G62', 'Approval workflow configuration', 'table', 'public.onexa_approval_workflows'),
    ('G63', 'Approval runtime', 'table', 'public.onexa_approval_instances'),
    ('G63', 'Approval inbox', 'view', 'public.onexa_approval_task_inbox'),
    ('G64', 'Approved posting bridge', 'procedure', 'onexa_private.guard_approval_posting()'),
    ('G65', 'Inventory document posting', 'procedure', 'public.onexa_post_inventory_document(uuid,text)'),
    ('G66', 'Maintenance foundation', 'table', 'public.ops_work_orders'),
    ('G66', 'Maintenance cost posting', 'procedure', 'public.onexa_post_maintenance_work_order_cost(uuid,text)'),
    ('G15', 'Real estate properties', 'table', 'public.re_properties'),
    ('G15', 'Rent schedules', 'table', 'public.re_lease_schedules'),
    ('G67', 'Lease invoice posting', 'procedure', 'public.onexa_post_lease_invoice(uuid,text)'),
    ('G67', 'Lease receipt posting', 'procedure', 'public.onexa_post_lease_receipt(uuid,text)'),
    ('G68', 'Lease schedule reconciliation', 'procedure', 'public.onexa_lease_schedule_dashboard()'),
    ('G69', 'Lease property report', 'procedure', 'public.onexa_lease_property_financial_report(uuid,date,date)'),
    ('G70', 'Lease receivables aging', 'procedure', 'public.onexa_lease_receivables_aging(uuid,date)')
), checked as (
 select gate_code, capability, object_kind, object_signature,
   case
     when object_kind in ('table','view') then to_regclass(object_signature) is not null
     when object_kind='procedure' then to_regprocedure(object_signature) is not null
     else false end as is_present
 from required
)
select gate_code, capability, object_kind, object_signature,
  case when is_present then 'INSTALLED_OBJECT' else 'MISSING_OBJECT' end as object_status,
  'ACCEPTANCE_NOT_VERIFIED' as production_qualification
from checked
order by case when gate_code='CORE' then 0 when gate_code='G15' then 15
              else coalesce(nullif(regexp_replace(gate_code,'[^0-9]','','g'),'')::int,100) end,
         capability;
