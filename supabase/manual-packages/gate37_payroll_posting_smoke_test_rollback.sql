-- Gate 37 rollback-only smoke test against an existing approved, cost-synced,
-- unposted payroll run. This script never commits or creates durable test data.

begin;

do $smoke$
declare
  _tenant_id constant text := 'tenant-001-al-ostool';
  _legal_entity_id constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _run_id uuid;
  _branch_id uuid;
  _creator uuid;
  _poster uuid;
  _journal_id uuid;
  _period_code text;
  _status text;
begin
  select run.payroll_run_id, payroll.created_by,
    format('%s-%s', payroll.period_year, lpad(payroll.period_month::text, 2, '0'))
  into _run_id, _creator, _period_code
  from public.onexa_payroll_accounting_reconciliation run
  join public.hr_payroll_runs payroll on payroll.id = run.payroll_run_id
  where run.payroll_status in ('approved', 'paid')
    and run.reconciliation_status = 'not_posted'
    and run.cost_line_count = run.expected_cost_line_count
    and abs(run.cost_ledger_amount - run.employer_cost) <= 0.01
  order by run.period_year desc, run.period_month desc
  limit 1;
  if _run_id is null then
    raise exception 'ONEXA_SMOKE_APPROVED_COST_SYNCED_PAYROLL_REQUIRED';
  end if;

  select id into _branch_id from public.onexa_branches
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id and is_active = true
  order by created_at nulls last, id limit 1;
  if _branch_id is null then raise exception 'ONEXA_SMOKE_ACTIVE_BRANCH_REQUIRED'; end if;

  select user_id into _poster
  from public.onexa_workspace_memberships
  where tenant_id = _tenant_id and status = 'active'
    and role_key in ('workspace_owner', 'finance_manager', 'accountant')
    and user_id <> _creator
  order by created_at nulls last, user_id limit 1;
  if _poster is null then raise exception 'ONEXA_SMOKE_DISTINCT_FINANCE_POSTER_REQUIRED'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', _poster, 'role', 'authenticated',
    'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant_id)
  )::text, true);

  _journal_id := public.onexa_post_payroll_run(_run_id, _legal_entity_id, _branch_id, _period_code);
  if _journal_id is null then raise exception 'ONEXA_SMOKE_PAYROLL_JOURNAL_MISSING'; end if;

  select reconciliation_status into _status
  from public.onexa_payroll_accounting_reconciliation
  where payroll_run_id = _run_id;
  if _status <> 'reconciled' then
    raise exception 'ONEXA_SMOKE_PAYROLL_RECONCILIATION_FAILED:%', _status;
  end if;
  if (select count(*) from public.onexa_payroll_posting_runs where payroll_run_id = _run_id) <> 1 then
    raise exception 'ONEXA_SMOKE_PAYROLL_POSTING_RUN_MISMATCH';
  end if;
  if public.onexa_post_payroll_run(_run_id, _legal_entity_id, _branch_id, _period_code) <> _journal_id then
    raise exception 'ONEXA_SMOKE_PAYROLL_RETRY_NOT_IDEMPOTENT';
  end if;

  raise notice 'gate37_payroll_posting_smoke_test | passed | rollback follows';
end;
$smoke$;

rollback;
