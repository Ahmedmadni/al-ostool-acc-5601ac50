-- Requires an approved ONEXA supplier payment, two distinct staff users,
-- valid mappings and an open accounting period. No data persists.
begin;
do $smoke$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _document public.onexa_business_documents%rowtype;
  _poster uuid;
  _journal uuid;
  _retry uuid;
  _allocated numeric(20,4);
begin
  select * into _document from public.onexa_business_documents
  where tenant_id = _tenant and document_type = 'supplier_payment'
    and status = 'approved' and posted_journal_id is null
  order by created_at, id limit 1;
  if not found then raise exception 'ONEXA_SMOKE_APPROVED_PAYMENT_REQUIRED'; end if;

  select user_id into _poster from public.onexa_workspace_memberships
  where tenant_id = _tenant and status = 'active'
    and role_key in ('workspace_owner', 'finance_manager', 'accountant')
    and user_id <> _document.created_by
  order by created_at nulls last, user_id limit 1;
  if _poster is null then raise exception 'ONEXA_SMOKE_DISTINCT_PAYMENT_POSTER_REQUIRED'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant))::text, true);

  _journal := public.onexa_post_supplier_payment(_document.id,
    to_char(_document.accounting_date, 'YYYY-MM'));
  select sum(amount) into _allocated from public.onexa_supplier_payment_allocations
    where payment_id = _document.id and tenant_id = _tenant;
  if _journal is null or _allocated is distinct from _document.gross_total
    or not exists (select 1 from public.onexa_supplier_payment_postings
      where document_id = _document.id and journal_id = _journal)
    or not exists (select 1 from public.onexa_business_documents
      where id = _document.id and status = 'posted' and posted_journal_id = _journal) then
    raise exception 'ONEXA_SMOKE_PAYMENT_RECONCILIATION_FAILED';
  end if;
  _retry := public.onexa_post_supplier_payment(_document.id,
    to_char(_document.accounting_date, 'YYYY-MM'));
  if _retry is distinct from _journal then raise exception 'ONEXA_SMOKE_PAYMENT_RETRY_FAILED'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', 'tenant-smoke-other'))::text, true);
  begin
    perform public.onexa_post_supplier_payment(_document.id,
      to_char(_document.accounting_date, 'YYYY-MM'));
    raise exception 'ONEXA_SMOKE_CROSS_TENANT_ALLOWED';
  exception when others then
    if sqlerrm not in ('ONEXA_PAYMENT_POST_NOT_AUTHORIZED', 'ONEXA_DOCUMENT_NOT_FOUND') then
      raise;
    end if;
  end;
  raise notice 'gate40_supplier_payment_smoke_test | passed | rollback follows';
end;
$smoke$;
rollback;
