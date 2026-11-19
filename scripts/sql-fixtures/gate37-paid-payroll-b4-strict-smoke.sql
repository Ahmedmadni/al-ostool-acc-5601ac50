-- Phase14: ACTUAL shared strict B4 SQL, synthetic test tenant and payroll source.
-- Contract-only test: this is NOT executable Gate37 payroll workflow UAT.
-- Must run after B4 strict patch in disposable onexa_gate_test; ROLLBACK.
begin;
do $payroll_status$
declare
  e constant uuid:='a0000000-0000-4000-8000-000000000001';
  ledger uuid;
  original_count integer;
  expected_exception boolean;
  l_good jsonb:=jsonb_build_array(
    jsonb_build_object('account_code','5200','debit',701.25,'credit',0,
      'dimensions',jsonb_build_object('legalEntity',e)),
    jsonb_build_object('account_code','2100','debit',0,'credit',701.25,
      'dimensions',jsonb_build_object('legalEntity',e)));
begin
  if current_database()<>'onexa_gate_test'
     or to_regclass('public.fixture_module_grants') is null
     or to_regclass('public.onexa_posting_registry') is null then
    raise exception 'ONEXA_G37_B4_PAID_STATUS_DISPOSABLE_ONLY';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
  select count(*) into original_count from public.onexa_journal_headers;

  expected_exception:=false;
  begin
    perform public.onexa_post_journal(
      e,'payroll_run','PHASE14-PAID-STATUS',1,'paid',
      '{"run_no":"synthetic-paid"}'::jsonb,date '2026-11-18','2026-11','SAR',
      'Paid synthetic payroll',l_good);
  exception when others then
    if sqlerrm <> 'ONEXA_SOURCE_NOT_APPROVED' then raise; end if;
    expected_exception:=true;
  end;
  if not expected_exception then
    raise exception 'G37_PAID_SOURCE_STATUS_WAS_ACCEPTED_BY_B4';
  end if;
  if (select count(*) from public.onexa_journal_headers) <> original_count then
    raise exception 'G37_FAILED_PAID_SOURCE_LEFT_LEDGER_DATA';
  end if;

  -- Normalizing an eligible paid payroll to the **approved B4 source
  -- instruction**, without changing payroll status/history, is required.
  ledger:=public.onexa_post_journal(
    e,'payroll_run','PHASE14-PAID-STATUS',1,'approved',
    '{"run_no":"synthetic-paid"}'::jsonb,date '2026-11-18','2026-11','SAR',
    'Paid synthetic payroll',l_good);
  if ledger is null or not exists(
    select 1 from public.onexa_journal_headers
    where id=ledger and source_document_type='payroll_run'
      and state='posted' and total_debit=701.25 and total_credit=701.25
  ) then raise exception 'G37_APPROVED_CANONICAL_B4_PAYROLL_POST_FAILED'; end if;

  expected_exception:=false;
  begin
    perform public.onexa_post_journal(
      e,'payroll_run','PHASE14-IMBALANCED',1,'approved',
      '{"run_no":"synthetic-imbalanced"}'::jsonb,date '2026-11-18','2026-11','SAR',
      'Imbalanced synthetic payroll',
      jsonb_build_array(
        jsonb_build_object('account_code','5200','debit',701.25,'credit',0),
        jsonb_build_object('account_code','2100','debit',0,'credit',701.24)));
  exception when others then
    if sqlerrm <> 'ONEXA_JOURNAL_NOT_BALANCED' then raise; end if;
    expected_exception:=true;
  end;
  if not expected_exception then
    raise exception 'G37_ONE_HALALA_IMBALANCED_B4_PAYROLL_ACCEPTED';
  end if;
  if (select count(*) from public.onexa_journal_headers) <> original_count+1 then
    raise exception 'G37_B4_PAYROLL_CONTRACT_ADDED_UNEXPECTED_JOURNALS';
  end if;

  raise notice 'Gate37 canonical paid payroll to strict B4 approval and 0.01 mismatch rejection passed';
end;
$payroll_status$;
rollback;
