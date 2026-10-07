-- Gate 68 read-only checks. All objects READY, access columns false/true/true,
-- and the final anomaly query empty before enabling the UI switch.
select check_name,status from (values
 ('schedule_guard',case when to_regprocedure('public.onexa_guard_posted_lease_schedule()') is not null then 'READY' else 'MISSING' end),
 ('schedule_trigger',case when exists (select 1 from pg_trigger where tgrelid='public.re_lease_schedules'::regclass and tgname='onexa_guard_posted_lease_schedule' and tgenabled='O') then 'READY' else 'MISSING' end),
 ('schedule_dashboard',case when to_regprocedure('public.onexa_lease_schedule_dashboard()') is not null then 'READY' else 'MISSING' end),
 ('portfolio_snapshot',case when to_regprocedure('public.onexa_lease_portfolio_snapshot()') is not null then 'READY' else 'MISSING' end)
) c(check_name,status) order by check_name;

select has_function_privilege('anon','public.onexa_lease_schedule_dashboard()','EXECUTE') as anon_can_read,
 has_function_privilege('authenticated','public.onexa_lease_schedule_dashboard()','EXECUTE') as authenticated_can_read,
 has_function_privilege('authenticated','public.onexa_lease_portfolio_snapshot()','EXECUTE') as authenticated_can_snapshot;

select p.schedule_id,p.document_id,p.tenant_id,p.gross_amount,
 coalesce(sum(r.amount),0) as collected_amount,s.status as legacy_status,s.invoice_id as legacy_invoice_id
from public.onexa_lease_invoice_postings p
join public.re_lease_schedules s on s.id=p.schedule_id
left join public.onexa_lease_receipt_postings r on r.invoice_id=p.document_id and r.tenant_id=p.tenant_id
group by p.schedule_id,p.document_id,p.tenant_id,p.gross_amount,s.status,s.invoice_id
having s.invoice_id is not null or s.status<>'pending' or coalesce(sum(r.amount),0)>p.gross_amount;
