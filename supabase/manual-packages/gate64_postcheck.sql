select check_name, status
from (values
  ('approval_post_guard', case when
    to_regprocedure('onexa_private.guard_approval_posting()') is not null
    and exists (select 1 from pg_trigger
      where tgname = 'onexa_guard_approval_posting'
        and tgrelid = 'public.onexa_business_documents'::regclass
        and tgenabled <> 'D' and not tgisinternal)
    then 'READY' else 'MISSING' end),
  ('approval_post_finalizer', case when
    to_regprocedure('onexa_private.finalize_approval_posting()') is not null
    and exists (select 1 from pg_trigger
      where tgname = 'onexa_finalize_approval_posting'
        and tgrelid = 'public.onexa_business_documents'::regclass
        and tgenabled <> 'D' and not tgisinternal)
    then 'READY' else 'MISSING' end),
  ('assignment_aware_inbox', case when
    to_regprocedure('public.onexa_can_post_business_document(uuid)') is not null
    and
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'onexa_accounting_inbox'
        and column_name = 'can_current_user_post'
    ) then 'READY' else 'MISSING' end),
  ('inbox_security_invoker', case when
    exists (select 1 from pg_class c where c.oid = to_regclass('public.onexa_accounting_inbox')
      and c.reloptions @> array['security_invoker=true'])
    then 'READY' else 'MISSING' end),
  ('all_posting_engines_governed', case when
    (select count(*)
     from (values
       ('public.onexa_post_sales_invoice(uuid,text)','_document'),
       ('public.onexa_post_purchase_invoice(uuid,text)','_document'),
       ('public.onexa_post_customer_receipt(uuid,text)','_receipt'),
       ('public.onexa_post_supplier_payment(uuid,text)','_payment'),
       ('public.onexa_post_bank_transfer(uuid,text)','_document'),
       ('public.onexa_post_project_cost(uuid,text)','_document'),
       ('public.onexa_post_fleet_trip_cost(uuid,text)','_document')
     ) engines(signature,record_name)
     where to_regprocedure(engines.signature) is not null
       and regexp_count(
         pg_get_functiondef(to_regprocedure(engines.signature)),
         format(
           'if[[:space:]]+_actor[[:space:]]*=[[:space:]]*%1$s\.created_by[[:space:]]+and[[:space:]]+public\.onexa_approval_separation_required\([[:space:]]*%1$s\.document_type,[[:space:]]*''post''[[:space:]]*\)[[:space:]]+then[[:space:]]+raise exception[[:space:]]+''ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'';[[:space:]]+end if;',
           engines.record_name
         ),1,'i') = 1
       and regexp_count(
         pg_get_functiondef(to_regprocedure(engines.signature)),
         format(
           'if[[:space:]]+(_actor[[:space:]]*=[[:space:]]*%1$s\.created_by|%1$s\.created_by[[:space:]]*=[[:space:]]*_actor)[[:space:]]+then[[:space:]]+raise exception[[:space:]]+''ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'';[[:space:]]+end if;',
           engines.record_name
         ),1,'i') = 0) = 7
    then 'READY' else 'MISSING' end)
) checks(check_name, status)
order by check_name;
