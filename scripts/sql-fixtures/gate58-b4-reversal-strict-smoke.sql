-- Real captured B4 dispatch functions + reviewed reverse core, synthetic parents.
-- All test journal entries and period changes are rolled back.
begin;

create function pg_temp.expect_reverse_conflict(
  _original uuid,
  _date date,
  _period text,
  _reason text
) returns void language plpgsql as $expect$
begin
  begin
    perform public.onexa_reverse_journal(_original,_date,_period,_reason);
    raise exception 'B4_CHANGED_REVERSAL_REPLAY_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_B4_REVERSAL_PAYLOAD_CONFLICT' then raise; end if;
  end;
end;
$expect$;

do $strict_reverse$
declare
 _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
 _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
 _original uuid;
 _reversal uuid;
 _same uuid;
begin
 if current_database()<>'onexa_gate_test'
    or to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_B4_STRICT_REVERSAL_DISPOSABLE_ONLY';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);

 _original:=public.onexa_post_journal(
   _entity,'sales_invoice','B4-STRICT-REVERSAL-001',1,'approved',
   '{"test":"phase9"}'::jsonb,date '2026-11-18','2026-11','SAR',
   'Original synthetic sale',jsonb_build_array(
     jsonb_build_object('account_code','5200','debit',93.25,'credit',0,
        'dimensions',jsonb_build_object('project','STAGING-TEST','costCenter','FAKE-CC')),
     jsonb_build_object('account_code','2100','debit',0,'credit',93.25)
   )
 );
 _reversal:=public.onexa_reverse_journal(
   _original,date '2026-12-01','2026-12','confirmed reason'
 );
 _same:=public.onexa_reverse_journal(
   _original,date '2026-12-01','2026-12','confirmed reason'
 );
 if _original is null or _reversal is null or _same is distinct from _reversal
   or not exists(
    select 1 from public.onexa_journal_headers
    where id=_original and state='reversed' and reversal_journal_id=_reversal
   )
   or not exists(
    select 1 from public.onexa_journal_headers
    where id=_reversal and state='posted' and reversal_of_id=_original
      and accounting_date=date '2026-12-01'
      and source_snapshot->>'reason'='confirmed reason'
      and total_debit=93.25 and total_credit=93.25
   ) then
   raise exception 'B4_STRICT_REVERSAL_POSTED_RECEIPT_INVALID';
 end if;

 -- A closed historical period cannot justify a duplicate GL reversal. A
 -- genuinely identical retry may still retrieve its existing receipt.
 update public.onexa_fiscal_periods
   set status='closed'
 where legal_entity_id=_entity and period_code='2026-12'
   and tenant_id='tenant-smoke-A';
 if public.onexa_reverse_journal(
   _original,date '2026-12-01','2026-12','confirmed reason'
 ) is distinct from _reversal then
   raise exception 'B4_IDENTICAL_REVERSE_RETRY_CLOSED_PERIOD_FAILED';
 end if;

 perform pg_temp.expect_reverse_conflict(
   _original,date '2026-12-01','2026-12','changed reason');
 perform pg_temp.expect_reverse_conflict(
   _original,date '2026-12-02','2026-12','confirmed reason');
 perform pg_temp.expect_reverse_conflict(
   _original,date '2026-12-01','2026-11','confirmed reason');
 perform pg_temp.expect_reverse_conflict(
   _original,date '2026-12-01','UNRELATED','confirmed reason');

 -- Corrupt the linked reversal header, source reason, contra journal lines,
 -- or original-to-reversal pointer. Every nested subtransaction rolls back.
 begin
   update public.onexa_journal_headers set memo='corrupted reversal memo'
   where id=_reversal;
   perform pg_temp.expect_reverse_conflict(
     _original,date '2026-12-01','2026-12','confirmed reason');
   raise exception 'B4_MISMATCHED_MEMO_CONFIRMED';
 exception when others then
   if sqlerrm<>'B4_MISMATCHED_MEMO_CONFIRMED' then raise; end if;
 end;
 begin
   update public.onexa_journal_headers set source_snapshot='{}'::jsonb
   where id=_reversal;
   perform pg_temp.expect_reverse_conflict(
     _original,date '2026-12-01','2026-12','confirmed reason');
   raise exception 'B4_MISMATCHED_SNAPSHOT_CONFIRMED';
 exception when others then
   if sqlerrm<>'B4_MISMATCHED_SNAPSHOT_CONFIRMED' then raise; end if;
 end;
 begin
   update public.onexa_journal_lines set account_code='9999'
   where journal_id=_reversal and line_number=1;
   perform pg_temp.expect_reverse_conflict(
     _original,date '2026-12-01','2026-12','confirmed reason');
   raise exception 'B4_MISMATCHED_CONTRA_LINES_CONFIRMED';
 exception when others then
   if sqlerrm<>'B4_MISMATCHED_CONTRA_LINES_CONFIRMED' then raise; end if;
 end;
 begin
   update public.onexa_journal_headers set reversal_of_id=null
   where id=_reversal;
   perform pg_temp.expect_reverse_conflict(
     _original,date '2026-12-01','2026-12','confirmed reason');
   raise exception 'B4_MISSING_REVERSAL_LINK_CONFIRMED';
 exception when others then
   if sqlerrm<>'B4_MISSING_REVERSAL_LINK_CONFIRMED' then raise; end if;
 end;
 begin
   update public.onexa_journal_headers set total_debit=94.25,
       total_credit=94.25
   where id=_reversal;
   perform pg_temp.expect_reverse_conflict(
     _original,date '2026-12-01','2026-12','confirmed reason');
   raise exception 'B4_MISMATCHED_REVERSAL_TOTALS_CONFIRMED';
 exception when others then
   if sqlerrm<>'B4_MISMATCHED_REVERSAL_TOTALS_CONFIRMED' then raise; end if;
 end;

 if (select count(*) from public.onexa_journal_headers
       where source_document_type='journal_reversal'
         and source_document_id=_original::text)<>1
    or (select count(*) from public.onexa_posting_registry
       where source_document_type='journal_reversal'
         and source_document_id=_original::text)<>1
    or (select count(*) from public.onexa_workspace_audit_events
       where entity_id=_original::text and action='journal_reversed')<>1 then
   raise exception 'B4_REVERSE_RETRY_CREATED_DUPLICATE_GL_OR_AUDIT';
 end if;

 perform set_config('test.tenant_id','tenant-smoke-B',true);
 perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
 begin
   perform public.onexa_reverse_journal(
     _original,date '2026-12-01','2026-12','confirmed reason');
   raise exception 'B4_CROSS_TENANT_REVERSE_RETRY_ACCEPTED';
 exception when others then
   if sqlerrm<>'ONEXA_JOURNAL_NOT_FOUND' then raise; end if;
 end;

 raise notice 'Strict real B4 reversal retry integrity passed: identical receipt, drift denial, corruption refusal, tenant isolation';
end;
$strict_reverse$;
rollback;
