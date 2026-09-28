select check_name, status
from (values
  ('approval_post_guard', case when
    to_regprocedure('onexa_private.guard_approval_posting()') is not null
    and exists (select 1 from pg_trigger where tgname = 'onexa_guard_approval_posting' and not tgisinternal)
    then 'READY' else 'MISSING' end),
  ('approval_post_finalizer', case when
    to_regprocedure('onexa_private.finalize_approval_posting()') is not null
    and exists (select 1 from pg_trigger where tgname = 'onexa_finalize_approval_posting' and not tgisinternal)
    then 'READY' else 'MISSING' end),
  ('assignment_aware_inbox', case when
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'onexa_accounting_inbox'
        and column_name = 'can_current_user_post'
    ) then 'READY' else 'MISSING' end),
  ('all_posting_engines_governed', case when
    (select count(*)
     from unnest(array[
       'public.onexa_post_sales_invoice(uuid,text)',
       'public.onexa_post_purchase_invoice(uuid,text)',
       'public.onexa_post_customer_receipt(uuid,text)',
       'public.onexa_post_supplier_payment(uuid,text)',
       'public.onexa_post_bank_transfer(uuid,text)',
       'public.onexa_post_project_cost(uuid,text)',
       'public.onexa_post_fleet_trip_cost(uuid,text)'
     ]) signature
     where to_regprocedure(signature) is not null
       and position(
         'onexa_approval_separation_required'
         in pg_get_functiondef(to_regprocedure(signature)::oid)
       ) > 0) = 7
    then 'READY' else 'MISSING' end)
) checks(check_name, status)
order by check_name;
