-- ONEXA Gate 64 prerequisite inventory — READ ONLY.
-- Does NOT install/update posting engines or change any production object.
-- A PRESENT signature is only evidence of installation; it is not financial/UAT approval.
with function_requirements(gate,dependency,function_signature) as (
values
 ('G35','sales invoice posting','public.onexa_post_sales_invoice(uuid,text)'),
 ('G36','purchase invoice posting','public.onexa_post_purchase_invoice(uuid,text)'),
 ('G39','customer receipt posting','public.onexa_post_customer_receipt(uuid,text)'),
 ('G40','supplier payment posting','public.onexa_post_supplier_payment(uuid,text)'),
 ('G41','bank transfer posting','public.onexa_post_bank_transfer(uuid,text)'),
 ('G42','project cost posting','public.onexa_post_project_cost(uuid,text)'),
 ('G43','fleet trip cost posting','public.onexa_post_fleet_trip_cost(uuid,text)'),
 ('G63','approval actor assignment','onexa_private.approval_actor_matches_step(uuid,uuid,uuid)'),
 ('G62','approval separation policy','public.onexa_approval_separation_required(text,text)')
), table_requirements(gate,dependency,object_signature) as (
values
 ('G63','approval instances','public.onexa_approval_instances'),
 ('G63','approval decisions','public.onexa_approval_decisions'),
 ('G62','approval workflows','public.onexa_approval_workflows'),
 ('CORE','governed source documents','public.onexa_business_documents'),
 ('CORE','accounting inbox','public.onexa_accounting_inbox')
), checks as (
select gate,dependency,'FUNCTION'::text as object_kind,
 function_signature as object_signature,
 to_regprocedure(function_signature) is not null as ready
from function_requirements
union all
select gate,dependency,'RELATION'::text,
 object_signature,to_regclass(object_signature) is not null
from table_requirements
)
select gate,dependency,object_kind,object_signature,
 case when ready then 'PRESENT' else 'MISSING' end as installed_state,
 'DATABASE_ACCEPTANCE_NOT_VERIFIED'::text as qualification
from checks order by gate,object_kind,dependency;

-- Gate 64 replaces the definitions of seven posting RPCs in-place using a
-- regex match on pg_get_functiondef. Flag them for manual SQL-definition review:
-- a PRESENT signature alone does not prove the replacement pattern is safe.
with engines(gate,function_signature) as (
values
 ('G35','public.onexa_post_sales_invoice(uuid,text)'),
 ('G36','public.onexa_post_purchase_invoice(uuid,text)'),
 ('G39','public.onexa_post_customer_receipt(uuid,text)'),
 ('G40','public.onexa_post_supplier_payment(uuid,text)'),
 ('G41','public.onexa_post_bank_transfer(uuid,text)'),
 ('G42','public.onexa_post_project_cost(uuid,text)'),
 ('G43','public.onexa_post_fleet_trip_cost(uuid,text)')
)
select gate,function_signature,
 case when to_regprocedure(function_signature) is null then 'MISSING'
      when pg_get_functiondef(to_regprocedure(function_signature)) ilike
         '%onexa_approval_separation_required%' then 'ALREADY_POLICY_AWARE'
      else 'MANUAL_DEFINITION_REVIEW_REQUIRED'
 end as patch_review_state
from engines order by gate;
