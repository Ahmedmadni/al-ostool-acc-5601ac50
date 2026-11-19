-- Gate58 replay guard against incorrect historic B4 reversal receipts.
-- Synthetic tenants/roles, proposed strict B4, actual Gate58 workflow, ROLLBACK.
begin;

create function pg_temp.expect_manual_reverse_conflict(
  _manual uuid,
  _date date,
  _period text,
  _reason text
) returns void language plpgsql as $expect$
begin
  begin
    perform public.onexa_reverse_manual_journal(_manual,_date,_period,_reason);
    raise exception 'G58_CHANGED_REVERSAL_REPLAY_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_REVERSAL_REPLAY_CONFLICT' then
      raise;
    end if;
  end;
end;
$expect$;

do $gate58$
declare
 _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
 _branch constant uuid := 'a0000000-0000-4000-8000-000000000002';
 _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
 _reviewer constant uuid := 'a0000000-0000-4000-8000-000000000012';
 _manual uuid;
 _ledger uuid;
 _reversal uuid;
begin
 if current_database() <> 'onexa_gate_test'
   or to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_G58_REVERSE_REPLAY_DISPOSABLE_ONLY';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);
 _manual:=public.onexa_create_manual_journal(
   _entity,_branch,date '2026-11-18','2026-11','SAR',
   'Synthetic manual reversal replay test','G58-REPLAY-ONLY',
   jsonb_build_array(
     jsonb_build_object('line_number',1,'account_code','5200',
       'debit',130.25,'credit',0,
       'dimensions',jsonb_build_object('project','PROJECT-TEST')),
     jsonb_build_object('line_number',2,'account_code','2100',
       'debit',0,'credit',130.25)
   )
 );
 perform public.onexa_transition_manual_journal(_manual,'submitted');
 perform set_config('test.user_id',_reviewer::text,true);
 perform public.onexa_transition_manual_journal(_manual,'approved');
 _ledger:=public.onexa_post_manual_journal(_manual);
 _reversal:=public.onexa_reverse_manual_journal(
   _manual,date '2026-12-03','2026-12','documented correction');
 if _ledger is null or _reversal is null or not exists(
   select 1 from public.onexa_manual_journals
   where id=_manual and status='reversed'
     and posted_journal_id=_ledger and reversal_journal_id=_reversal
 ) then
   raise exception 'G58_REVERSE_INITIAL_POSTING_FAILED';
 end if;

 update public.onexa_fiscal_periods set status='closed'
 where tenant_id='tenant-smoke-A' and legal_entity_id=_entity
   and period_code='2026-12';
 if public.onexa_reverse_manual_journal(
   _manual,date '2026-12-03','2026-12','  documented correction  '
 ) is distinct from _reversal then
   raise exception 'G58_IDENTICAL_REVERSE_RETRY_CLOSED_PERIOD_FAILED';
 end if;

 perform pg_temp.expect_manual_reverse_conflict(
   _manual,date '2026-12-04','2026-12','documented correction');
 perform pg_temp.expect_manual_reverse_conflict(
   _manual,date '2026-12-03','2026-12','changed reason');
 -- Period-date consistency is validated before replay receipt comparison.
 begin
  perform public.onexa_reverse_manual_journal(
    _manual,date '2026-12-03','2026-11','documented correction');
  raise exception 'G58_MISMATCHED_REPLAY_PERIOD_ACCEPTED';
 exception when others then
  if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_REVERSAL_PERIOD_INVALID' then raise; end if;
 end;

 begin
   update public.onexa_journal_headers set source_snapshot='{}'::jsonb
     where id=_reversal;
   perform pg_temp.expect_manual_reverse_conflict(
     _manual,date '2026-12-03','2026-12','documented correction');
   raise exception 'G58_TAMPERED_REVERSAL_SNAPSHOT_CONFIRMED';
 exception when others then
   if sqlerrm <> 'G58_TAMPERED_REVERSAL_SNAPSHOT_CONFIRMED' then raise; end if;
 end;
 begin
   update public.onexa_journal_lines set account_code='SYNTHETIC-CORRUPTED'
     where journal_id=_reversal and line_number=1;
   perform pg_temp.expect_manual_reverse_conflict(
     _manual,date '2026-12-03','2026-12','documented correction');
   raise exception 'G58_TAMPERED_REVERSAL_LINES_CONFIRMED';
 exception when others then
   if sqlerrm <> 'G58_TAMPERED_REVERSAL_LINES_CONFIRMED' then raise; end if;
 end;
 begin
   update public.onexa_journal_headers set reversal_of_id=null
     where id=_reversal;
   perform pg_temp.expect_manual_reverse_conflict(
     _manual,date '2026-12-03','2026-12','documented correction');
   raise exception 'G58_MISSING_REVERSE_LINK_CONFIRMED';
 exception when others then
   if sqlerrm <> 'G58_MISSING_REVERSE_LINK_CONFIRMED' then raise; end if;
 end;

 if (select count(*) from public.onexa_manual_journal_events
    where manual_journal_id=_manual and event_type='reversal_completed')<>1
   or (select count(*) from public.onexa_journal_headers
    where source_document_type='journal_reversal'
      and source_document_id=_ledger::text)<>1
   or not exists(
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id=_manual and reconciliation_status='reconciled'
   ) then
   raise exception 'G58_REVERSE_REPLAY_LEDGER_OR_AUDIT_DUPLICATED';
 end if;

 perform set_config('test.tenant_id','tenant-smoke-B',true);
 perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
 begin
   perform public.onexa_reverse_manual_journal(
    _manual,date '2026-12-03','2026-12','documented correction');
   raise exception 'G58_CROSS_TENANT_REVERSE_REPLAY_ACCEPTED';
 exception when others then
   if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_NOT_FOUND' then raise; end if;
 end;

 raise notice 'Gate58 reverse replay integrity passed with actual B4 GL receipts';
end;
$gate58$;
rollback;
