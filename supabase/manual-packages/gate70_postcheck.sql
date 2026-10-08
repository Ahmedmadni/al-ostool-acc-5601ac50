-- Read-only: READY, anon false, authenticated true. Last result must be empty.
select 'lease_aging_rpc' as check_name,
 case when to_regprocedure('public.onexa_lease_receivables_aging(uuid,date)') is not null
   then 'READY' else 'MISSING' end as status;

select has_function_privilege('anon','public.onexa_lease_receivables_aging(uuid,date)','EXECUTE') as anon_can_read,
 has_function_privilege('authenticated','public.onexa_lease_receivables_aging(uuid,date)','EXECUTE') as authenticated_can_read;

select p.document_id,p.tenant_id,p.property_id,p.gross_amount,
 coalesce(sum(r.amount),0) as collected_amount
from public.onexa_lease_invoice_postings p
left join public.onexa_lease_receipt_postings r on r.invoice_id=p.document_id and r.tenant_id=p.tenant_id
group by p.document_id,p.tenant_id,p.property_id,p.gross_amount
having coalesce(sum(r.amount),0)>p.gross_amount;
