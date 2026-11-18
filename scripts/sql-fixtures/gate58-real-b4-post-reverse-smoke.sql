-- REAL B4 captured function bodies, synthetic parent data. Disposable DB ONLY.
-- No hosted SQL/data is accessed; all changes are enclosed in ROLLBACK.
begin;
do $real_b4$
declare
  _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
  _branch constant uuid := 'a0000000-0000-4000-8000-000000000002';
  _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
  _reviewer constant uuid := 'a0000000-0000-4000-8000-000000000012';
  _journal uuid;
  _retry_journal uuid;
  _ledger uuid;
  _reversal uuid;
  _period uuid;
  _lines jsonb := jsonb_build_array(
    jsonb_build_object('line_number',1,'account_code','5200','debit',125.25,'credit',0,
      'dimensions',jsonb_build_object('project','SYNTHETIC-PRJ','costCenter','SYNTHETIC-CC')),
    jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
  );
begin
  if current_database() <> 'onexa_gate_test'
     or to_regclass('public.onexa_fiscal_periods') is null
     or to_regclass('public.onexa_posting_registry') is null then
    raise exception 'ONEXA_B4_REAL_SMOKE_DISPOSABLE_DATABASE_REQUIRED';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id',_maker::text,true);

  _journal := public.onexa_create_manual_journal(
    _entity,_branch,date '2026-11-18','2026-11','SAR',
    'actual B4 open period test','B4-SYNTHETIC',_lines
  );
  perform public.onexa_transition_manual_journal(_journal,'submitted');
  perform set_config('test.user_id',_reviewer::text,true);
  perform public.onexa_transition_manual_journal(_journal,'approved');
  _ledger := public.onexa_post_manual_journal(_journal);
  select id into _period from public.onexa_fiscal_periods
    where legal_entity_id=_entity and period_code='2026-11';
  if _ledger is null
    or (select public.onexa_post_manual_journal(_journal)) is distinct from _ledger
    or not exists (
      select 1 from public.onexa_journal_headers
      where id=_ledger and tenant_id='tenant-smoke-A'
        and legal_entity_id=_entity and fiscal_period_id=_period
        and source_document_type='manual_journal'
        and source_document_id=_journal::text and source_revision=1
        and currency='SAR' and total_debit=125.25
        and total_credit=125.25 and state='posted'
    )
    or not exists (
      select 1 from public.onexa_posting_registry
      where journal_id=_ledger and source_document_id=_journal::text
        and source_document_type='manual_journal' and source_revision=1
    )
    or (select count(*) from public.onexa_journal_lines where journal_id=_ledger) <> 2
    or not exists (
      select 1 from public.onexa_journal_lines
      where journal_id=_ledger and line_number=1 and account_code='5200'
        and debit=125.25 and credit=0
        and dimensions->>'project'='SYNTHETIC-PRJ'
        and dimensions->>'costCenter'='SYNTHETIC-CC'
        and dimensions->>'legalEntity'=_entity::text
        and dimensions->>'branch'=_branch::text
    ) then
    raise exception 'G58_REAL_B4_POSTING_CONTRACT_FAILED';
  end if;
  if (select count(*) from public.onexa_posting_registry
        where source_document_id=_journal::text) <> 1 then
    raise exception 'G58_REAL_B4_DUPLICATE_POSTING_KEY';
  end if;

  -- A second APPROVED document cannot post when its fiscal period is closed.
  perform set_config('test.user_id',_maker::text,true);
  _retry_journal := public.onexa_create_manual_journal(
    _entity,_branch,date '2026-11-19','2026-11','SAR',
    'actual B4 closed period rejection','B4-CLOSED',_lines
  );
  perform public.onexa_transition_manual_journal(_retry_journal,'submitted');
  perform set_config('test.user_id',_reviewer::text,true);
  perform public.onexa_transition_manual_journal(_retry_journal,'approved');
  update public.onexa_fiscal_periods
  set status='closed'
  where tenant_id='tenant-smoke-A' and legal_entity_id=_entity and period_code='2026-11';
  begin
    perform public.onexa_post_manual_journal(_retry_journal);
    raise exception 'G58_REAL_B4_CLOSED_PERIOD_POST_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_PERIOD_NOT_OPEN' then raise; end if;
  end;
  if not exists (
    select 1 from public.onexa_manual_journals
    where id=_retry_journal and status='approved' and posted_journal_id is null
  ) or exists (
    select 1 from public.onexa_posting_registry
    where source_document_id=_retry_journal::text
  ) then
    raise exception 'G58_REAL_B4_PERIOD_REJECTION_NOT_ATOMIC';
  end if;
  -- Gate58 post-idempotency of an already posted journal does not repost when
  -- the period closes.
  if public.onexa_post_manual_journal(_journal) is distinct from _ledger then
    raise exception 'G58_REAL_B4_POST_RETRY_AFTER_PERIOD_CLOSED_FAILED';
  end if;

  update public.onexa_fiscal_periods
  set status='open'
  where tenant_id='tenant-smoke-A' and legal_entity_id=_entity and period_code='2026-11';
  if public.onexa_post_manual_journal(_retry_journal) is null then
    raise exception 'G58_REAL_B4_REOPEN_PERIOD_POST_FAILED';
  end if;

  -- Reversal requires the NEW accounting date to be in an OPEN period.
  update public.onexa_fiscal_periods
  set status='closed'
  where tenant_id='tenant-smoke-A' and legal_entity_id=_entity and period_code='2026-12';
  begin
    perform public.onexa_reverse_manual_journal(
      _journal,date '2026-12-01','2026-12','synthetic correction'
    );
    raise exception 'G58_REAL_B4_CLOSED_PERIOD_REVERSE_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_PERIOD_NOT_OPEN' then raise; end if;
  end;
  if not exists (
    select 1 from public.onexa_manual_journals
    where id=_journal and status='posted' and reversal_journal_id is null
  ) or not exists (
    select 1 from public.onexa_journal_headers
    where id=_ledger and state='posted' and reversal_journal_id is null
  ) then
    raise exception 'G58_REAL_B4_REVERSE_DENIAL_NOT_ATOMIC';
  end if;
  update public.onexa_fiscal_periods
  set status='open'
  where tenant_id='tenant-smoke-A' and legal_entity_id=_entity and period_code='2026-12';
  _reversal := public.onexa_reverse_manual_journal(
    _journal,date '2026-12-01','2026-12','synthetic correction'
  );
  if _reversal is null or public.onexa_reverse_manual_journal(
    _journal,date '2026-12-01','2026-12','synthetic correction'
  ) is distinct from _reversal
    or not exists (
      select 1 from public.onexa_journal_headers
      where id=_reversal and tenant_id='tenant-smoke-A'
        and legal_entity_id=_entity and reversal_of_id=_ledger
        and source_document_type='journal_reversal'
        and source_document_id=_ledger::text
        and total_debit=125.25 and total_credit=125.25
    )
    or not exists (
      select 1 from public.onexa_journal_headers
      where id=_ledger and state='reversed' and reversal_journal_id=_reversal
    )
    or not exists (
      select 1 from public.onexa_manual_journal_reconciliation
      where manual_journal_id=_journal and reconciliation_status='reconciled'
    )
    or (select count(*) from public.onexa_journal_lines where journal_id=_reversal) <> 2
    or not exists (
      select 1 from public.onexa_journal_lines
      where journal_id=_reversal and line_number=1 and debit=0 and credit=125.25
    ) then
    raise exception 'G58_REAL_B4_REVERSAL_CONTRACT_FAILED';
  end if;

  -- Second tenant cannot transition a known first-tenant manual journal.
  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  begin
    perform public.onexa_post_manual_journal(_journal);
    raise exception 'G58_REAL_B4_CROSS_TENANT_POST_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_NOT_FOUND' then raise; end if;
  end;

  raise notice 'REAL captured B4 SQL + real Gate58 open/closed period smoke PASSED (ROLLBACK)';
end;
$real_b4$;
rollback;
