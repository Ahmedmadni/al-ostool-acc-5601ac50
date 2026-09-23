-- Run as a permitted authenticated poster distinct from the document creator.
-- Replace the UUID with a submitted then approved Gate 43 document.
begin;
do $smoke$
declare
  _document_id uuid := '00000000-0000-0000-0000-000000000000';
  _period text;
  _journal uuid;
  _retry uuid;
begin
  if _document_id='00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'ONEXA_GATE43_SMOKE_DOCUMENT_REQUIRED'; end if;
  select to_char(accounting_date,'YYYY-MM') into _period
  from public.onexa_business_documents where id=_document_id and status='approved';
  if _period is null then raise exception 'ONEXA_GATE43_APPROVED_DOCUMENT_REQUIRED'; end if;
  _journal:=public.onexa_post_fleet_trip_cost(_document_id,_period);
  _retry:=public.onexa_post_fleet_trip_cost(_document_id,_period);
  if _journal is distinct from _retry
    or (select count(*) from public.onexa_fleet_trip_cost_postings where document_id=_document_id)<>1
    or not exists (select 1 from public.onexa_fleet_trip_cost_reconciliation
      where document_id=_document_id and reconciliation_status='reconciled') then
    raise exception 'ONEXA_GATE43_SMOKE_FAILED'; end if;
  raise notice 'gate43_fleet_trip_smoke_test | passed';
end;
$smoke$;
rollback;
