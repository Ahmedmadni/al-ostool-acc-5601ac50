-- ONEXA lease deployment inventory for Gates 67-70.
-- Read only: safe to execute in the correct customer project's SQL Editor.
-- MISSING/BLOCKED means STOP; no schema or data is modified by this query.
-- An installed object does NOT prove operational acceptance or reconciled data.

with objects(gate_no, check_name, ready) as (
 values
 ('67','gate64_approval_guard',to_regprocedure('onexa_private.guard_approval_posting()') is not null),
 ('67','accounting_scopes_table',to_regclass('public.onexa_lease_accounting_scopes') is not null),
 ('67','invoice_postings_table',to_regclass('public.onexa_lease_invoice_postings') is not null),
 ('67','receipt_postings_table',to_regclass('public.onexa_lease_receipt_postings') is not null),
 ('67','save_scope_rpc',to_regprocedure('public.onexa_save_lease_accounting_scope(uuid,uuid)') is not null),
 ('67','post_invoice_rpc',to_regprocedure('public.onexa_post_lease_invoice(uuid,text)') is not null),
 ('67','post_receipt_rpc',to_regprocedure('public.onexa_post_lease_receipt(uuid,text)') is not null),
 ('68','posted_schedule_guard',to_regprocedure('public.onexa_guard_posted_lease_schedule()') is not null),
 ('68','posted_schedule_trigger',exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid=to_regclass('public.re_lease_schedules')
      and t.tgname='onexa_guard_posted_lease_schedule'
      and t.tgenabled in ('O','A') and not t.tgisinternal
 )),
 ('68','schedule_dashboard_rpc',to_regprocedure('public.onexa_lease_schedule_dashboard()') is not null),
 ('68','portfolio_snapshot_rpc',to_regprocedure('public.onexa_lease_portfolio_snapshot()') is not null),
 ('69','property_financial_rpc',to_regprocedure('public.onexa_lease_property_financial_report(uuid,date,date)') is not null),
 ('70','lease_aging_rpc',to_regprocedure('public.onexa_lease_receivables_aging(uuid,date)') is not null)
), table_security as (
 select '67'::text as gate_no,
   'rls_' || expected.table_name as check_name,
   coalesce(c.relrowsecurity,false) as ready
 from (values
   ('onexa_lease_accounting_scopes'),
   ('onexa_lease_invoice_postings'),
   ('onexa_lease_receipt_postings')
 ) expected(table_name)
 left join pg_catalog.pg_class c
   on c.oid=to_regclass('public.' || expected.table_name)
), rpc_security as (
 select rpc.gate_no,
   'anon_denied_' || rpc.label as check_name,
   coalesce(not pg_catalog.has_function_privilege(
      'anon',to_regprocedure(rpc.signature)::oid,'EXECUTE'),false) as ready
 from (values
   ('67','post_invoice','public.onexa_post_lease_invoice(uuid,text)'),
   ('67','post_receipt','public.onexa_post_lease_receipt(uuid,text)'),
   ('68','schedule_dashboard','public.onexa_lease_schedule_dashboard()'),
   ('68','portfolio_snapshot','public.onexa_lease_portfolio_snapshot()'),
   ('69','property_financial','public.onexa_lease_property_financial_report(uuid,date,date)'),
   ('70','lease_aging','public.onexa_lease_receivables_aging(uuid,date)')
 ) rpc(gate_no,label,signature)
 union all
 select rpc.gate_no,
   'authenticated_allowed_' || rpc.label as check_name,
   coalesce(pg_catalog.has_function_privilege(
      'authenticated',to_regprocedure(rpc.signature)::oid,'EXECUTE'),false) as ready
 from (values
   ('67','post_invoice','public.onexa_post_lease_invoice(uuid,text)'),
   ('67','post_receipt','public.onexa_post_lease_receipt(uuid,text)'),
   ('68','schedule_dashboard','public.onexa_lease_schedule_dashboard()'),
   ('68','portfolio_snapshot','public.onexa_lease_portfolio_snapshot()'),
   ('69','property_financial','public.onexa_lease_property_financial_report(uuid,date,date)'),
   ('70','lease_aging','public.onexa_lease_receivables_aging(uuid,date)')
 ) rpc(gate_no,label,signature)
), checks as (
 select * from objects
 union all select * from table_security
 union all select * from rpc_security
)
select gate_no,check_name,
  case when ready then 'READY' else 'BLOCKED' end as status
from checks
order by gate_no,check_name;
