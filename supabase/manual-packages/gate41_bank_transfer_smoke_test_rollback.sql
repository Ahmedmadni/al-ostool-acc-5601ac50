-- Needs an approved transfer between two configured accounts and a distinct
-- finance poster. Entire operation rolls back, including journal and events.
begin;
do $smoke$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _document public.onexa_business_documents%rowtype;
  _poster uuid;
  _journal uuid;
  _retry uuid;
begin
  select * into _document from public.onexa_business_documents
  where tenant_id = _tenant and document_type = 'bank_transfer'
    and status = 'approved' and posted_journal_id is null
  order by created_at, id limit 1;
  if not found then raise exception 'ONEXA_SMOKE_APPROVED_BANK_TRANSFER_REQUIRED'; end if;
  select user_id into _poster from public.onexa_workspace_memberships
  where tenant_id = _tenant and status = 'active'
    and role_key in ('workspace_owner', 'finance_manager', 'accountant')
    and user_id <> _document.created_by
  order by created_at nulls last, user_id limit 1;
  if _poster is null then raise exception 'ONEXA_SMOKE_DISTINCT_BANK_POSTER_REQUIRED'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant))::text, true);
  _journal := public.onexa_post_bank_transfer(_document.id,
    to_char(_document.accounting_date, 'YYYY-MM'));
  if _journal is null or not exists (
    select 1 from public.onexa_bank_transfer_postings
    where document_id = _document.id and tenant_id = _tenant
      and journal_id = _journal and amount = _document.gross_total
  ) or not exists (
    select 1 from public.onexa_bank_transfer_reconciliation
    where document_id = _document.id and reconciliation_status = 'reconciled'
  ) then raise exception 'ONEXA_SMOKE_BANK_TRANSFER_RECONCILIATION_FAILED'; end if;
  _retry := public.onexa_post_bank_transfer(_document.id,
    to_char(_document.accounting_date, 'YYYY-MM'));
  if _retry is distinct from _journal then raise exception 'ONEXA_SMOKE_BANK_RETRY_FAILED'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', 'tenant-smoke-other'))::text, true);
  begin
    perform public.onexa_post_bank_transfer(_document.id,
      to_char(_document.accounting_date, 'YYYY-MM'));
    raise exception 'ONEXA_SMOKE_CROSS_TENANT_BANK_TRANSFER_ALLOWED';
  exception when others then
    if sqlerrm not in ('ONEXA_BANK_TRANSFER_POST_NOT_AUTHORIZED', 'ONEXA_DOCUMENT_NOT_FOUND') then raise; end if;
  end;
  raise notice 'gate41_bank_transfer_smoke_test | passed | rollback follows';
end;
$smoke$;
rollback;
