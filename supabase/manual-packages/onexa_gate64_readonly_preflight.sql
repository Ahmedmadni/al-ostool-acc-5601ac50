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

-- Gate 64 dynamically rewrites seven source functions. The legacy guard
-- must occur EXACTLY once and its replacement must be structurally recognized.
-- Distinguish patchable definitions from partial/ambiguous policy markers.
with engines(gate,function_signature,record_name) as (
values
 ('G35','public.onexa_post_sales_invoice(uuid,text)','_document'),
 ('G36','public.onexa_post_purchase_invoice(uuid,text)','_document'),
 ('G39','public.onexa_post_customer_receipt(uuid,text)','_receipt'),
 ('G40','public.onexa_post_supplier_payment(uuid,text)','_payment'),
 ('G41','public.onexa_post_bank_transfer(uuid,text)','_document'),
 ('G42','public.onexa_post_project_cost(uuid,text)','_document'),
 ('G43','public.onexa_post_fleet_trip_cost(uuid,text)','_document')
), definitions as (
select gate,function_signature,record_name,
 to_regprocedure(function_signature) as routine_oid
from engines
), patterns as (
select gate,function_signature,record_name,routine_oid,
 case when routine_oid is not null
   then pg_get_functiondef(routine_oid) end as function_source,
 format(
   'if[[:space:]]+(_actor[[:space:]]*=[[:space:]]*%1$s\.created_by|%1$s\.created_by[[:space:]]*=[[:space:]]*_actor)[[:space:]]+then[[:space:]]+raise exception[[:space:]]+''ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'';[[:space:]]+end if;',
   record_name
 ) as legacy_guard_pattern,
 format(
   'if[[:space:]]+_actor[[:space:]]*=[[:space:]]*%1$s\.created_by[[:space:]]+and[[:space:]]+public\.onexa_approval_separation_required\([[:space:]]*%1$s\.document_type,[[:space:]]*''post''[[:space:]]*\)[[:space:]]+then[[:space:]]+raise exception[[:space:]]+''ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'';[[:space:]]+end if;',
   record_name
 ) as policy_guard_pattern
from definitions
), counts as (
select gate,function_signature,function_source,
 case when routine_oid is not null
   then regexp_count(function_source,legacy_guard_pattern,1,'i') end as legacy_guard_count,
 case when routine_oid is not null
   then regexp_count(function_source,policy_guard_pattern,1,'i') end as policy_guard_count
from patterns
)
select gate,function_signature,legacy_guard_count,policy_guard_count,
 case
  when function_source is null then 'MISSING'
  when legacy_guard_count=1 and policy_guard_count=0
    and position('onexa_approval_separation_required' in function_source)=0
    then 'ONE_GUARD_PATCHABLE'
  when legacy_guard_count=0 and policy_guard_count=1
    then 'ALREADY_POLICY_AWARE'
  else 'GUARD_MISMATCH_REVIEW_REQUIRED'
 end as patch_review_state
from counts order by gate;

-- PostgreSQL CREATE OR REPLACE VIEW can only append columns. Compare the
-- existing accounting inbox order/types with Gate 64's proposed definition.
with expected(ordinal_position,column_name,udt_name) as (
values
 (1,'id','uuid'),(2,'tenant_id','text'),
 (3,'legal_entity_id','uuid'),(4,'branch_id','uuid'),
 (5,'module_key','text'),(6,'document_type','text'),
 (7,'document_number','text'),(8,'document_date','date'),
 (9,'accounting_date','date'),(10,'currency','text'),
 (11,'party_type','text'),(12,'party_id','uuid'),
 (13,'party_name_snapshot','text'),(14,'gross_total','numeric'),
 (15,'dimensions','jsonb'),(16,'approved_by','uuid'),
 (17,'approved_at','timestamptz'),(18,'revision','int4'),
 (19,'approval_instance_id','uuid'),(20,'posting_step_name','text'),
 (21,'can_current_user_post','bool')
), actual as (
select ordinal_position,column_name,udt_name from information_schema.columns
where table_schema='public' and table_name='onexa_accounting_inbox'
)
select expected.ordinal_position,expected.column_name,expected.udt_name as expected_type,
 actual.column_name as actual_column,actual.udt_name as actual_type,
 case
   when actual.column_name=expected.column_name
     and actual.udt_name=expected.udt_name then 'MATCH'
   when actual.column_name is null and expected.ordinal_position>18 then 'APPENDABLE'
   else 'VIEW_PREFIX_MISMATCH'
 end as compatibility_status
from expected left join actual using (ordinal_position)
union all
select actual.ordinal_position,'<unexpected>'::text,null::text,
 actual.column_name,actual.udt_name,'VIEW_EXTRA_COLUMN_BLOCKS_REPLACE'::text
from actual where actual.ordinal_position>21
order by ordinal_position;
