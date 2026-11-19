-- Actual source-controlled Gate37 function running against ACTUAL captured B4
-- engine + strict B4 candidate, with fake (not verified) HR Gate7/8 parents.
-- Synthetic financial data ONLY. All posting, tampering and tests ROLLBACK.
begin;
do $gate37$
declare
  e constant uuid := 'a0000000-0000-4000-8000-000000000001';
  b constant uuid := 'a0000000-0000-4000-8000-000000000002';
  run_id constant uuid := 'a0000000-0000-4000-8000-000000009037';
  l_id constant uuid := 'a0000000-0000-4000-8000-000000009040';
  cost_id constant uuid := 'a0000000-0000-4000-8000-000000009041';
  employee_id constant uuid := 'a0000000-0000-4000-8000-000000009038';
  project_id constant uuid := 'a0000000-0000-4000-8000-000000009039';
  ledger uuid;
  replay uuid;
  before_journals bigint;
begin
  if current_database() <> 'onexa_gate_test'
    or to_regclass('public.fixture_module_grants') is null
    or to_regclass('public.onexa_payroll_posting_runs') is null then
    raise exception 'G37_REAL_B4_E2E_DISPOSABLE_ONLY';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);

  -- Cross-tenant payroll run must be invisible even to a B-tenant poster.
  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  begin
    perform public.onexa_post_payroll_run(
      run_id,'b0000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000002','2026-11');
    raise exception 'G37_CROSS_TENANT_PAYROLL_RUN_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_RUN_NOT_FOUND' then raise; end if;
  end;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);

  -- Tenant-isolated source, employee, project and cost-ledger checks.
  begin
    update public.hr_payroll_lines set tenant_id='tenant-smoke-B' where id=l_id;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_FOREIGN_TENANT_SOURCE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_SOURCE_TENANT_MISMATCH' then raise; end if;
  end;

  begin
    update public.hr_employees set tenant_id='tenant-smoke-B' where id=employee_id;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_FOREIGN_TENANT_EMPLOYEE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_EMPLOYEE_TENANT_MISMATCH' then raise; end if;
  end;

  begin
    update public.projects set tenant_id='tenant-smoke-B' where id=project_id;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_FOREIGN_TENANT_PROJECT_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_PROJECT_TENANT_MISMATCH' then raise; end if;
  end;

  begin
    update public.cost_entries set tenant_id='tenant-smoke-B' where id=cost_id;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_FOREIGN_TENANT_COST_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_COST_SYNC_REQUIRED' then raise; end if;
  end;

  begin
    update public.cost_entries set amount=1000.01 where id=cost_id;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_ONE_HALALA_COST_DRIFT_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_COST_LEDGER_MISMATCH' then raise; end if;
  end;
  begin
    update public.hr_payroll_lines set net_salary=999.99 where id=l_id;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_ONE_HALALA_ACCOUNTING_DRIFT_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_PAYROLL_ACCOUNTING_EQUATION_MISMATCH' then raise; end if;
  end;

  select count(*) into before_journals from public.onexa_journal_headers;
  -- The payroll operational status is PAID, but its accounting source status
  -- must be normalized to APPROVED for real shared B4 (no fake B4 publisher).
  ledger:=public.onexa_post_payroll_run(run_id,e,b,'2026-11');
  if ledger is null or not exists (
    select 1 from public.onexa_journal_headers h
    where h.id=ledger and h.tenant_id='tenant-smoke-A'
      and h.source_document_type='payroll_run'
      and h.source_document_id=run_id::text
      and h.state='posted' and h.total_debit=1000 and h.total_credit=1000
      and h.source_snapshot->>'posting_contract_version'='payroll-v1'
  ) then raise exception 'G37_PAID_RUN_CANONICAL_B4_JOURNAL_NOT_POSTED'; end if;

  replay:=public.onexa_post_payroll_run(run_id,e,b,'2026-11');
  if replay is distinct from ledger then
    raise exception 'G37_IDENTICAL_REPLAY_NOT_IDEMPOTENT';
  end if;

  begin
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-12');
    raise exception 'G37_CONFLICTING_PERIOD_REPLAY_ACCEPTED';
  exception when others then
    if sqlerrm<>'ONEXA_PAYROLL_POSTING_RETRY_CONFLICT' then raise; end if;
  end;

  begin
    update public.onexa_journal_lines set account_code='9999'
    where journal_id=ledger and line_number=1;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_MUTATED_ORIGINAL_GL_LINE_ACCEPTED';
  exception when others then
    if sqlerrm<>'ONEXA_PAYROLL_POSTING_RETRY_CONFLICT' then raise; end if;
  end;

  begin
    update public.onexa_journal_headers set source_snapshot='{}'::jsonb
    where id=ledger;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_MUTATED_SOURCE_SNAPSHOT_ACCEPTED';
  exception when others then
    if sqlerrm<>'ONEXA_PAYROLL_POSTING_RETRY_CONFLICT' then raise; end if;
  end;

  begin
    update public.onexa_journal_headers set state='reversed'
    where id=ledger;
    perform public.onexa_post_payroll_run(run_id,e,b,'2026-11');
    raise exception 'G37_REVERSED_JOURNAL_REPLAY_ACCEPTED_AS_POSTED';
  exception when others then
    if sqlerrm<>'ONEXA_PAYROLL_POSTING_RETRY_CONFLICT' then raise; end if;
  end;

  if (select count(*) from public.onexa_journal_headers) <> before_journals+1
    or (select count(*) from public.onexa_payroll_posting_runs
        where payroll_run_id=run_id)<>1
    or (select count(*) from public.onexa_posting_registry
        where source_document_type='payroll_run'
          and source_document_id=run_id::text)<>1 then
    raise exception 'G37_REPLAY_CREATED_DUPLICATE_PAYROLL_LEDGER_OR_REGISTRY';
  end if;

  raise notice 'Real Gate37 + real strict B4 smoke passed: paid, exact halalas, tenant isolation, unchanged retry, drift/period rejection';
end;
$gate37$;
rollback;
