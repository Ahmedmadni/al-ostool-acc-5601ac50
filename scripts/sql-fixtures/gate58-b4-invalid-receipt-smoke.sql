-- Deliberately corrupt B4 responses: Gate58 must never mark a manual journal
-- posted or reversed on a mismatched UUID/header. DISPOSABLE DB ONLY.
begin;
do $disposable_only$
begin
 if current_database()<>'onexa_gate_test' or
   to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_G58_B4_BAD_RECEIPT_DISPOSABLE_ONLY';
 end if;
end $disposable_only$;

-- This fake publisher creates a genuine row but with the WRONG source type.
-- It simulates an external B4 regression returning a plausible UUID.
create or replace function public.onexa_post_journal(
 _legal_entity_id uuid,_source_document_type text,_source_document_id text,
 _source_revision integer,_source_status text,_source_snapshot jsonb,
 _accounting_date date,_period_code text,_currency text,_memo text,_lines jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $fake$
declare _id uuid:=gen_random_uuid();
begin
 insert into public.onexa_journal_headers (
   id,tenant_id,legal_entity_id,state,source_document_type,
   source_document_id,source_revision,currency,total_debit,total_credit,
   accounting_date,journal_number
 ) values (
   _id,onexa_private.claim_tenant_id(),_legal_entity_id,'posted',
   'WRONG_SOURCE_TYPE',_source_document_id,_source_revision,_currency,
   125.25,125.25,_accounting_date,'FAKE-BAD-GL'
 );
 return _id;
end;
$fake$;

do $case$
declare
 _maker constant uuid:='a0000000-0000-4000-8000-000000000011';
 _reviewer constant uuid:='a0000000-0000-4000-8000-000000000012';
 _journal uuid;
begin
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);
 _journal:=public.onexa_create_manual_journal(
   'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002',
   date '2026-11-18','2026-11','SAR',
   'synthetic invalid B4 receipt','TEST-INVALID-B4',
   jsonb_build_array(
     jsonb_build_object('line_number',1,'account_code','5200','debit',125.25,'credit',0),
     jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
   )
 );
 perform public.onexa_transition_manual_journal(_journal,'submitted');
 perform set_config('test.user_id',_reviewer::text,true);
 perform public.onexa_transition_manual_journal(_journal,'approved');

 begin
   perform public.onexa_post_manual_journal(_journal);
   raise exception 'G58_INVALID_B4_POST_RECEIPT_ACCEPTED';
 exception when others then
   if sqlerrm<>'ONEXA_MANUAL_JOURNAL_B4_POST_CONTRACT_MISMATCH' then raise; end if;
 end;

 if not exists (
   select 1 from public.onexa_manual_journals
   where id=_journal and status='approved' and posted_journal_id is null
 ) or exists (
   select 1 from public.onexa_journal_headers
   where source_document_id=_journal::text
 ) then
   raise exception 'G58_INVALID_B4_POST_WAS_NOT_ATOMIC';
 end if;
 raise notice 'Bad B4 post receipt correctly rejected, no orphan GL row';
end;
$case$;
rollback;

-- Separately test malicious reversal result, preserving valid fake B4 setup.
begin;
do $disposable_only$
begin
 if current_database()<>'onexa_gate_test' or
   to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_G58_B4_BAD_REVERSE_DISPOSABLE_ONLY';
 end if;
end $disposable_only$;

create or replace function public.onexa_reverse_journal(
 _journal_id uuid,_accounting_date date,_period_code text,_reason text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $fake$
begin
 return gen_random_uuid();
end;
$fake$;

do $case$
declare
 _maker constant uuid:='a0000000-0000-4000-8000-000000000011';
 _reviewer constant uuid:='a0000000-0000-4000-8000-000000000012';
 _journal uuid;
 _ledger uuid;
begin
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);
 _journal:=public.onexa_create_manual_journal(
   'a0000000-0000-4000-8000-000000000001',
   'a0000000-0000-4000-8000-000000000002',
   date '2026-11-18','2026-11','SAR',
   'synthetic invalid B4 reversal receipt','TEST-INVALID-REV',
   jsonb_build_array(
     jsonb_build_object('line_number',1,'account_code','5200','debit',125.25,'credit',0),
     jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
   )
 );
 perform public.onexa_transition_manual_journal(_journal,'submitted');
 perform set_config('test.user_id',_reviewer::text,true);
 perform public.onexa_transition_manual_journal(_journal,'approved');
 _ledger:=public.onexa_post_manual_journal(_journal);
 begin
   perform public.onexa_reverse_manual_journal(
     _journal,date '2026-11-18','2026-11','test synthetic wrong reversal header'
   );
   raise exception 'G58_INVALID_B4_REVERSAL_RECEIPT_ACCEPTED';
 exception when others then
   if sqlerrm<>'ONEXA_MANUAL_JOURNAL_B4_REVERSAL_CONTRACT_MISMATCH' then raise; end if;
 end;
 if not exists (
   select 1 from public.onexa_manual_journals
   where id=_journal and status='posted'
     and posted_journal_id=_ledger and reversal_journal_id is null
 ) or not exists (
   select 1 from public.onexa_journal_headers
   where id=_ledger and state='posted' and reversal_journal_id is null
 ) then
   raise exception 'G58_INVALID_B4_REVERSAL_NOT_ATOMIC';
 end if;
 raise notice 'Bad B4 reversal receipt correctly rejected, no false status change';
end;
$case$;
rollback;
