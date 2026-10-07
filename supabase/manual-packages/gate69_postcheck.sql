-- Gate 69 read-only checks: READY, anon false, authenticated true; anomalies empty.
select 'property_report_rpc' as check_name,
 case when to_regprocedure('public.onexa_lease_property_financial_report(uuid,date,date)') is not null
   then 'READY' else 'MISSING' end as status;

select has_function_privilege('anon','public.onexa_lease_property_financial_report(uuid,date,date)','EXECUTE') as anon_can_report,
 has_function_privilege('authenticated','public.onexa_lease_property_financial_report(uuid,date,date)','EXECUTE') as authenticated_can_report;

select p.document_id,p.tenant_id,p.property_id,'INVOICE_SOURCE_MISMATCH' as anomaly
from public.onexa_lease_invoice_postings p
left join public.onexa_lease_accounting_scopes s on s.id=p.scope_id
left join public.onexa_business_documents d on d.id=p.document_id
where s.id is null or s.tenant_id is distinct from p.tenant_id
  or s.property_id is distinct from p.property_id
  or s.legal_entity_id is distinct from p.legal_entity_id
  or d.tenant_id is distinct from p.tenant_id
  or d.legal_entity_id is distinct from p.legal_entity_id
  or d.status is distinct from 'posted'
  or d.posted_journal_id is distinct from p.journal_id;

select r.document_id,r.tenant_id,r.property_id,'RECEIPT_SOURCE_MISMATCH' as anomaly
from public.onexa_lease_receipt_postings r
left join public.onexa_lease_invoice_postings p on p.document_id=r.invoice_id
left join public.onexa_business_documents d on d.id=r.document_id
where p.document_id is null or p.tenant_id is distinct from r.tenant_id
  or p.property_id is distinct from r.property_id
  or p.legal_entity_id is distinct from r.legal_entity_id
  or d.tenant_id is distinct from r.tenant_id
  or d.legal_entity_id is distinct from r.legal_entity_id
  or d.status is distinct from 'posted'
  or d.posted_journal_id is distinct from r.journal_id;
