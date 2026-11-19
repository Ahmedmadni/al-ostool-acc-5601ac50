-- ONEXA Gate64 exact seven RPC guard inspection (pg_proc ONLY; SELECT ONLY).
-- COPIED from authoritative onexa_gate64_readonly_preflight.sql guard query.
-- Missing/ambiguous guards MUST block any Gate64 function rewrite.
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
  md5(function_source) as installed_definition_md5,
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
