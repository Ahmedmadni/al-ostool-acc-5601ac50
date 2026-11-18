-- Reproduces hosted GL defects using captured ACTUAL B4 function bodies
-- plus exact observed production CHECK constraints. Fake tenants only; ROLLBACK.
begin;
do $baseline$
declare
 _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
 _reviewer constant uuid := 'a0000000-0000-4000-8000-000000000012';
 _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
 _branch constant uuid := 'a0000000-0000-4000-8000-000000000002';
 _journal uuid;
 _ledger uuid;
 _balanced jsonb := jsonb_build_array(
   jsonb_build_object('line_number',1,'account_code','5200','debit',125.25,'credit',0),
   jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
 );
begin
 if current_database() <> 'onexa_gate_test' then
   raise exception 'ONEXA_B4_BASELINE_DISPOSABLE_ONLY';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);
 _journal := public.onexa_create_manual_journal(
   _entity,_branch,date '2026-11-18','2026-11','SAR',
   'baseline legacy type refusal','TEST-BASELINE',_balanced);
 perform public.onexa_transition_manual_journal(_journal,'submitted');
 perform set_config('test.user_id',_reviewer::text,true);
 perform public.onexa_transition_manual_journal(_journal,'approved');
 begin
   perform public.onexa_post_manual_journal(_journal);
   raise exception 'G58_B4_BASELINE_MANUAL_TYPE_UNEXPECTEDLY_ALLOWED';
 exception when check_violation then
   if position('onexa_journal_headers_source_document_type_check' in sqlerrm)=0
   then raise; end if;
 end;
 if not exists (
   select 1 from public.onexa_manual_journals
   where id=_journal and status='approved' and posted_journal_id is null
 ) or exists (
   select 1 from public.onexa_journal_headers
   where source_document_id=_journal::text
 ) then
   raise exception 'G58_B4_BASELINE_MANUAL_TYPE_DENIAL_NOT_ATOMIC';
 end if;

 -- The legacy engine+table allows an imbalanced direct sales posting
 -- because both use the 0.005 tolerance. Keep it only inside a subtransaction.
 begin
   _ledger := public.onexa_post_journal(
     _entity,'sales_invoice','TEST-IMBALANCED',1,'approved','{}'::jsonb,
     date '2026-11-18','2026-11','SAR','baseline sub-half-cent error',
     jsonb_build_array(
       jsonb_build_object('account_code','5200','debit',100.000,'credit',0),
       jsonb_build_object('account_code','2100','debit',0,'credit',100.004)
     )
   );
   if not exists (
     select 1 from public.onexa_journal_headers
     where id=_ledger and total_debit=100 and total_credit=100.004
   ) then raise exception 'G58_B4_BASELINE_IMBALANCE_NOT_OBSERVED'; end if;
   raise exception 'BASELINE_IMBALANCE_CONFIRMED';
 exception when others then
   if sqlerrm <> 'BASELINE_IMBALANCE_CONFIRMED' then raise; end if;
 end;

 -- The legacy engine silently coerces source five-decimal inputs into
 -- numeric(20,4) storage before any precision validation.
 begin
   _ledger := public.onexa_post_journal(
     _entity,'purchase_invoice','TEST-ROUNDING',1,'approved','{}'::jsonb,
     date '2026-11-18','2026-11','SAR','baseline unannounced rounding',
     jsonb_build_array(
       jsonb_build_object('account_code','5200','debit',125.25001,'credit',0),
       jsonb_build_object('account_code','2100','debit',0,'credit',125.25001)
     )
   );
   if not exists (
     select 1 from public.onexa_journal_headers
     where id=_ledger and total_debit=125.2500 and total_credit=125.2500
   ) then raise exception 'G58_B4_BASELINE_ROUNDING_NOT_OBSERVED'; end if;
   raise exception 'BASELINE_ROUNDING_CONFIRMED';
 exception when others then
   if sqlerrm <> 'BASELINE_ROUNDING_CONFIRMED' then raise; end if;
 end;

 -- Original internal posting normalizes an omitted debit to zero rather
 -- than rejecting an incomplete line payload.
 begin
   _ledger := public.onexa_post_journal(
     _entity,'payroll_run','TEST-MISSING-SIDE',1,'approved','{}'::jsonb,
     date '2026-11-18','2026-11','SAR','baseline missing money field',
     jsonb_build_array(
       jsonb_build_object('account_code','5200','debit',75,'credit',0),
       jsonb_build_object('account_code','2100','credit',75)
     )
   );
   if not exists (
     select 1 from public.onexa_journal_lines
     where journal_id=_ledger and line_number=2 and debit=0 and credit=75
   ) then raise exception 'G58_B4_BASELINE_MISSING_SIDE_NOT_OBSERVED'; end if;
   raise exception 'BASELINE_MISSING_SIDE_CONFIRMED';
 exception when others then
   if sqlerrm <> 'BASELINE_MISSING_SIDE_CONFIRMED' then raise; end if;
 end;

 if exists (select 1 from public.onexa_journal_headers)
    or exists (select 1 from public.onexa_posting_registry) then
   raise exception 'G58_B4_BASELINE_PROBES_LEFT_LEDGER_DATA';
 end if;
 raise notice 'Real hosted GL defects reproduced on disposable B4, rolled back';
end;
$baseline$;
rollback;
