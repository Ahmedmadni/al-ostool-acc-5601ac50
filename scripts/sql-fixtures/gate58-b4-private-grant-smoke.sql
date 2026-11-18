-- Least-privilege integration test with REAL captured B4 functions.
-- DISPOSABLE DATABASE ONLY. Uses a synthetic authenticated actor and ROLLBACK.
begin;
do $safety$
begin
 if current_database()<>'onexa_gate_test'
    or to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_B4_GRANT_SMOKE_DISPOSABLE_ONLY';
 end if;
end $safety$;

-- Real production ACLs grant authenticated direct access to internal B4.
-- The proposed remediation revokes it and must not break checked public RPC.
revoke execute on function
 onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)
 from public,anon,authenticated;
revoke execute on function
 onexa_private.reverse_journal(uuid,date,text,text)
 from public,anon,authenticated;

revoke execute on function
 public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)
 from public,anon;
grant execute on function
 public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)
 to authenticated;
revoke execute on function public.onexa_reverse_journal(uuid,date,text,text)
 from public,anon;
grant execute on function public.onexa_reverse_journal(uuid,date,text,text)
 to authenticated;
revoke execute on function
 public.onexa_post_journal_unchecked(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)
 from public,anon,authenticated;
revoke execute on function public.onexa_reverse_journal_unchecked(uuid,date,text,text)
 from public,anon,authenticated;

set local role authenticated;
do $smoke$
declare
 _maker constant uuid:='a0000000-0000-4000-8000-000000000011';
 _approver constant uuid:='a0000000-0000-4000-8000-000000000012';
 _entity constant uuid:='a0000000-0000-4000-8000-000000000001';
 _branch constant uuid:='a0000000-0000-4000-8000-000000000002';
 _journal uuid;
 _ledger uuid;
 _reversal uuid;
begin
 if has_function_privilege('authenticated',
  'onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
  'EXECUTE') or
  has_function_privilege('authenticated',
  'onexa_private.reverse_journal(uuid,date,text,text)','EXECUTE') then
  raise exception 'ONEXA_B4_PRIVATE_DIRECT_EXECUTE_STILL_GRANTED';
 end if;
 if not has_function_privilege('authenticated',
  'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
  'EXECUTE') or
  not has_function_privilege('authenticated',
  'public.onexa_reverse_journal(uuid,date,text,text)','EXECUTE') then
  raise exception 'ONEXA_B4_PUBLIC_CHECKED_RPC_INACCESSIBLE';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);
 _journal:=public.onexa_create_manual_journal(
  _entity,_branch,date '2026-11-18','2026-11','SAR',
  'real B4 under restricted private grants','B4-PRIVILEGE-TEST',
  jsonb_build_array(
   jsonb_build_object('line_number',1,'account_code','5200','debit',88.25,'credit',0),
   jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',88.25)
  )
 );
 perform public.onexa_transition_manual_journal(_journal,'submitted');
 perform set_config('test.user_id',_approver::text,true);
 perform public.onexa_transition_manual_journal(_journal,'approved');
 _ledger:=public.onexa_post_manual_journal(_journal);
 _reversal:=public.onexa_reverse_manual_journal(
   _journal,date '2026-12-02','2026-12','synthetic correction');
 if _ledger is null or _reversal is null or
  not exists(select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id=_journal and reconciliation_status='reconciled')
 then
  raise exception 'ONEXA_B4_RESTRICTED_PRIVATE_GRANTS_BREAK_APPROVED_FLOW';
 end if;
 raise notice 'Restricted private B4 grants: authenticated checked post+reverse still work';
end;
$smoke$;
reset role;
rollback;
