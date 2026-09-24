-- Requires one approved, unposted manual journal and a distinct authorized poster.
-- No data persists.
begin;
do $smoke$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _manual public.onexa_manual_journals%rowtype;
  _poster uuid;
  _ledger_journal uuid;
  _retry uuid;
begin
  select * into _manual
  from public.onexa_manual_journals
  where tenant_id = _tenant and status = 'approved' and posted_journal_id is null
  order by created_at, id
  limit 1;
  if not found then raise exception 'ONEXA_SMOKE_APPROVED_MANUAL_JOURNAL_REQUIRED'; end if;

  select user_id into _poster
  from public.onexa_workspace_memberships
  where tenant_id = _tenant and status = 'active'
    and role_key in ('workspace_owner','finance_manager','accountant')
    and user_id <> _manual.created_by
  order by created_at nulls last, user_id
  limit 1;
  if _poster is null then raise exception 'ONEXA_SMOKE_DISTINCT_MANUAL_JOURNAL_POSTER_REQUIRED'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster,
    'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
  )::text, true);

  _ledger_journal := public.onexa_post_manual_journal(_manual.id);
  if _ledger_journal is null
     or not exists (
       select 1 from public.onexa_manual_journals
       where id = _manual.id and status = 'posted' and posted_journal_id = _ledger_journal
     )
     or not exists (
       select 1 from public.onexa_manual_journal_reconciliation
       where manual_journal_id = _manual.id and reconciliation_status = 'reconciled'
     ) then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_RECONCILIATION_FAILED';
  end if;

  _retry := public.onexa_post_manual_journal(_manual.id);
  if _retry is distinct from _ledger_journal then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_RETRY_FAILED';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster,
    'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', 'tenant-smoke-other')
  )::text, true);
  begin
    perform public.onexa_post_manual_journal(_manual.id);
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_CROSS_TENANT_ALLOWED';
  exception when others then
    if sqlerrm not in ('ONEXA_MANUAL_JOURNAL_POST_NOT_AUTHORIZED','ONEXA_MANUAL_JOURNAL_NOT_FOUND') then
      raise;
    end if;
  end;

  raise notice 'gate58_manual_journal_smoke_test | passed | rollback follows';
end;
$smoke$;
rollback;
