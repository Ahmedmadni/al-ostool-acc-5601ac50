-- Run as an authenticated inventory poster. Replace UUID with one approved Gate 65 document.
-- The transaction always rolls back, including stock movements and the journal.
begin;
do $smoke$
declare
  _document_id uuid := '00000000-0000-0000-0000-000000000000';
  _period text;
  _journal uuid;
  _retry uuid;
begin
  if _document_id='00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'ONEXA_GATE65_SMOKE_DOCUMENT_REQUIRED'; end if;
  select to_char(accounting_date,'YYYY-MM') into _period
  from public.onexa_business_documents
  where id=_document_id and module_key='inventory'
    and document_type in ('inventory_receipt','inventory_issue') and status='approved';
  if _period is null then raise exception 'ONEXA_GATE65_APPROVED_DOCUMENT_REQUIRED'; end if;
  _journal:=public.onexa_post_inventory_document(_document_id,_period);
  _retry:=public.onexa_post_inventory_document(_document_id,_period);
  if _journal is distinct from _retry
     or (select count(*) from public.onexa_inventory_posting_runs where document_id=_document_id)<>1
     or not exists (select 1 from public.onexa_inventory_document_reconciliation
       where document_id=_document_id and reconciliation_status='reconciled') then
    raise exception 'ONEXA_GATE65_SMOKE_FAILED'; end if;
  raise notice 'gate65_inventory_smoke_test | passed | journal=%',_journal;
end;
$smoke$;
rollback;
