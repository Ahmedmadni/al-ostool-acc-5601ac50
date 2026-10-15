-- Read-only: READY, anon false, authenticated true. Last result must be empty.
select 'lease_aging_rpc' as check_name,
 case when to_regprocedure('public.onexa_lease_receivables_aging(uuid,date)') is not null
   then 'READY' else 'MISSING' end as status;

select has_function_privilege('anon','public.onexa_lease_receivables_aging(uuid,date)','EXECUTE') as anon_can_read,
 has_function_privilege('authenticated','public.onexa_lease_receivables_aging(uuid,date)','EXECUTE') as authenticated_can_read;

select p.document_id,p.tenant_id,p.property_id,p.gross_amount,
 coalesce(sum(case when receipt_doc.id is not null and receipt_journal.id is not null then r.amount else 0 end),0) as collected_amount
from public.onexa_lease_invoice_postings p
left join public.onexa_lease_receipt_postings r on r.invoice_id=p.document_id and r.tenant_id=p.tenant_id
left join public.onexa_business_documents receipt_doc
  on receipt_doc.id=r.document_id and receipt_doc.tenant_id=p.tenant_id
  and receipt_doc.legal_entity_id=p.legal_entity_id
  and receipt_doc.document_type='lease_receipt' and receipt_doc.status='posted'
  and receipt_doc.posted_journal_id=r.journal_id
left join public.onexa_journal_headers receipt_journal
  on receipt_journal.id=r.journal_id and receipt_journal.tenant_id=r.tenant_id
  and receipt_journal.legal_entity_id=r.legal_entity_id
  and receipt_journal.state='posted'
  and receipt_journal.reversal_journal_id is null
group by p.document_id,p.tenant_id,p.property_id,p.gross_amount
having coalesce(sum(case when receipt_doc.id is not null and receipt_journal.id is not null then r.amount else 0 end),0)>p.gross_amount;
