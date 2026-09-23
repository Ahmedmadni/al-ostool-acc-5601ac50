-- Run as an authenticated finance poster on a freshly approved Gate 42
-- document created by another user. Replace the UUID below, then ROLLBACK.
begin;
do $smoke$
declare
  _document_id uuid := '00000000-0000-0000-0000-000000000000';
  _period text;
  _journal uuid;
  _again uuid;
begin
  if _document_id='00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'ONEXA_GATE42_SMOKE_DOCUMENT_ID_REQUIRED'; end if;
  select to_char(accounting_date,'YYYY-MM') into _period
  from public.onexa_business_documents where id=_document_id and status='approved';
  if _period is null then raise exception 'ONEXA_GATE42_APPROVED_DOCUMENT_REQUIRED'; end if;
  _journal := public.onexa_post_project_cost(_document_id,_period);
  _again := public.onexa_post_project_cost(_document_id,_period);
  if _journal is distinct from _again or
    (select count(*) from public.onexa_project_cost_postings where document_id=_document_id)<>1 or
    not exists (select 1 from public.onexa_project_cost_reconciliation
      where document_id=_document_id and reconciliation_status='reconciled') then
    raise exception 'ONEXA_GATE42_SMOKE_FAILED'; end if;
  raise notice 'gate42_project_cost_smoke_test | passed';
end;
$smoke$;
rollback;
