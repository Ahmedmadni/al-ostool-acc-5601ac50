-- Run as an authenticated facilities poster. Replace both UUIDs with approved
-- Gate 67 documents. The receipt must target an already-posted lease invoice.
-- No production write persists: the complete test ends with ROLLBACK.
begin;
do $smoke$
declare
  _invoice_id uuid:='00000000-0000-0000-0000-000000000000';
  _receipt_id uuid:='00000000-0000-0000-0000-000000000000';
  _invoice_period text; _receipt_period text;
  _invoice_journal uuid; _receipt_journal uuid;
  _retry uuid;
begin
  if _invoice_id='00000000-0000-0000-0000-000000000000'::uuid
    or _receipt_id='00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'ONEXA_GATE67_SMOKE_DOCUMENT_IDS_REQUIRED'; end if;
  select to_char(accounting_date,'YYYY-MM') into _invoice_period
  from public.onexa_business_documents where id=_invoice_id
    and document_type='lease_invoice' and status='approved';
  select to_char(accounting_date,'YYYY-MM') into _receipt_period
  from public.onexa_business_documents where id=_receipt_id
    and document_type='lease_receipt' and status='approved';
  if _invoice_period is null or _receipt_period is null then
    raise exception 'ONEXA_GATE67_APPROVED_DOCUMENTS_REQUIRED'; end if;
  _invoice_journal:=public.onexa_post_lease_invoice(_invoice_id,_invoice_period);
  _retry:=public.onexa_post_lease_invoice(_invoice_id,_invoice_period);
  if _invoice_journal is distinct from _retry
    or (select count(*) from public.onexa_lease_invoice_postings where document_id=_invoice_id)<>1 then
    raise exception 'ONEXA_GATE67_INVOICE_SMOKE_FAILED'; end if;
  _receipt_journal:=public.onexa_post_lease_receipt(_receipt_id,_receipt_period);
  _retry:=public.onexa_post_lease_receipt(_receipt_id,_receipt_period);
  if _receipt_journal is distinct from _retry
    or (select count(*) from public.onexa_lease_receipt_postings where document_id=_receipt_id)<>1
    or exists (select 1 from public.onexa_lease_accounting_reconciliation
      where document_id in (_invoice_id,_receipt_id) and reconciliation_status<>'reconciled') then
    raise exception 'ONEXA_GATE67_RECEIPT_SMOKE_FAILED'; end if;
  raise notice 'gate67_lease_accounting_smoke_test | passed | invoice_journal=% | receipt_journal=%',
    _invoice_journal,_receipt_journal;
end;
$smoke$;
rollback;
