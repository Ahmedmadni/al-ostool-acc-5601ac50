-- Gate 38 rollback-only smoke test.
-- Uses one existing configured active asset, posts the current period, verifies the
-- roll-forward and idempotent retry, then rolls the whole transaction back.

begin;

do $smoke$
declare
  _tenant_id constant text := 'tenant-001-al-ostool';
  _asset_id uuid;
  _creator uuid;
  _poster uuid;
  _period_code text := to_char(current_date, 'YYYY-MM');
  _accounting_date date := (
    date_trunc('month', current_date)
    + interval '1 month - 1 day'
  )::date;
  _journal_id uuid;
  _retry_journal_id uuid;
  _before_accumulated numeric(20,4);
  _after_accumulated numeric(20,4);
  _posted_amount numeric(20,4);
  _status text;
begin
  select
    reconciliation.asset_id,
    asset.imported_by,
    reconciliation.accumulated_depreciation
  into _asset_id, _creator, _before_accumulated
  from public.onexa_asset_accounting_reconciliation reconciliation
  join public.fixed_assets asset on asset.id = reconciliation.asset_id
  where reconciliation.tenant_id = _tenant_id
    and reconciliation.reconciliation_status = 'ready'
    and reconciliation.depreciation_start_date <= _accounting_date
    and not exists (
      select 1
      from public.onexa_asset_depreciation_postings posting
      where posting.tenant_id = reconciliation.tenant_id
        and posting.asset_id = reconciliation.asset_id
        and posting.period_code = _period_code
    )
  order by reconciliation.depreciation_start_date, reconciliation.asset_id
  limit 1;

  if _asset_id is null then
    raise exception 'ONEXA_SMOKE_READY_ASSET_REQUIRED';
  end if;

  select user_id into _poster
  from public.onexa_workspace_memberships
  where tenant_id = _tenant_id
    and status = 'active'
    and role_key in ('workspace_owner', 'finance_manager', 'accountant')
    and (_creator is null or user_id <> _creator)
  order by created_at nulls last, user_id
  limit 1;

  if _poster is null then
    raise exception 'ONEXA_SMOKE_DISTINCT_ASSET_POSTER_REQUIRED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _poster,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant_id)
    )::text,
    true
  );

  _journal_id := public.onexa_post_asset_depreciation(
    _asset_id,
    _period_code,
    _accounting_date
  );
  if _journal_id is null then
    raise exception 'ONEXA_SMOKE_ASSET_DEPRECIATION_JOURNAL_MISSING';
  end if;

  select
    posting.depreciation_amount,
    asset.accumulated_depreciation,
    reconciliation.reconciliation_status
  into _posted_amount, _after_accumulated, _status
  from public.onexa_asset_depreciation_postings posting
  join public.fixed_assets asset on asset.id = posting.asset_id
  join public.onexa_asset_accounting_reconciliation reconciliation
    on reconciliation.asset_id = posting.asset_id
  where posting.tenant_id = _tenant_id
    and posting.asset_id = _asset_id
    and posting.period_code = _period_code;

  if abs(_after_accumulated - (_before_accumulated + _posted_amount)) > 0.01 then
    raise exception 'ONEXA_SMOKE_ASSET_ROLLFORWARD_FAILED';
  end if;
  if _status not in ('ready', 'fully_depreciated') then
    raise exception 'ONEXA_SMOKE_ASSET_RECONCILIATION_FAILED:%', _status;
  end if;
  if (
    select count(*)
    from public.onexa_asset_depreciation_postings
    where tenant_id = _tenant_id
      and asset_id = _asset_id
      and period_code = _period_code
  ) <> 1 then
    raise exception 'ONEXA_SMOKE_ASSET_POSTING_COUNT_MISMATCH';
  end if;

  _retry_journal_id := public.onexa_post_asset_depreciation(
    _asset_id,
    _period_code,
    _accounting_date
  );
  if _retry_journal_id <> _journal_id then
    raise exception 'ONEXA_SMOKE_ASSET_RETRY_NOT_IDEMPOTENT';
  end if;

  raise notice 'gate38_asset_depreciation_smoke_test | passed | rollback follows';
end;
$smoke$;

rollback;
