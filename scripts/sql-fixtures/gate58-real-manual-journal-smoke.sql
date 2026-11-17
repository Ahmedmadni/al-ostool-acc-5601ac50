-- SYNTHETIC ONLY: real Gate58 RPCs, fake B4 publisher, 2 isolated tenants.
-- CI disposable Postgres onexa_gate_test only; entire test is rolled back.
begin;

do $case$
declare
  _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
  _branch constant uuid := 'a0000000-0000-4000-8000-000000000002';
  _creator constant uuid := 'a0000000-0000-4000-8000-000000000011';
  _poster constant uuid := 'a0000000-0000-4000-8000-000000000012';
  _journal uuid;
  _rejection_journal uuid;
  _cancel_journal uuid;
  _ledger uuid;
  _reversal uuid;
  _status text;
  _lines jsonb := jsonb_build_array(
    jsonb_build_object('line_number',1,'account_code','5200','debit',125.25,'credit',0),
    jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
  );
begin
  if current_database() <> 'onexa_gate_test' then
    raise exception 'ONEXA_G58_DISPOSABLE_DB_REQUIRED';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id',_creator::text,true);

  -- Explicitly omitted side must fail: SQL three-valued boolean can otherwise
  -- allow missing values that were interpreted as 0 by old browser logic.
  begin
    perform public.onexa_create_manual_journal(
      _entity,_branch,date '2026-11-16','2026-11','SAR','missing credit','G58-NEGATIVE',
      jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',125.25),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
      )
    );
    raise exception 'G58_NULL_SIDE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_LINE_INVALID' then raise; end if;
  end;

  -- A valid-looking period belonging to a different month must be rejected.
  begin
    perform public.onexa_create_manual_journal(
      _entity,_branch,date '2026-11-16','2026-10','SAR','bad period','G58-NEGATIVE',_lines
    );
    raise exception 'G58_PERIOD_MISMATCH_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_PERIOD_INVALID' then raise; end if;
  end;

  -- Under the former 0.005 tolerance, a KWD imbalance of 0.004 passed.
  -- A ledger journal must balance exactly, even below the storage precision.
  begin
    perform public.onexa_create_manual_journal(
      _entity,_branch,date '2026-11-16','2026-11','KWD',
      'sub-cent imbalance','G58-NEGATIVE',
      jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',125.2500,'credit',0),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.2540)
      )
    );
    raise exception 'G58_SUB_TOLERANCE_IMBALANCE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_NOT_BALANCED' then raise; end if;
  end;

  -- Source values must never be silently rounded into numeric(20,4).
  begin
    perform public.onexa_create_manual_journal(
      _entity,_branch,date '2026-11-16','2026-11','KWD',
      'excess four decimal precision','G58-NEGATIVE',
      jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',125.25001,'credit',0),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25001)
      )
    );
    raise exception 'G58_EXCESS_STORAGE_PRECISION_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_AMOUNT_PRECISION_INVALID' then raise; end if;
  end;

  -- SAR must be stored in halalas, not fractional halalas.
  begin
    perform public.onexa_create_manual_journal(
      _entity,_branch,date '2026-11-16','2026-11','SAR',
      'fractional halala','G58-NEGATIVE',
      jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',125.251,'credit',0),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.251)
      )
    );
    raise exception 'G58_FRACTIONAL_HALALA_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_SAR_PRECISION_INVALID' then raise; end if;
  end;

  -- Cross-tenant legal entity lookup must fail before creating any journal.
  begin
    perform public.onexa_create_manual_journal(
      'b0000000-0000-4000-8000-000000000001'::uuid,
      'b0000000-0000-4000-8000-000000000002'::uuid,
      date '2026-11-16','2026-11','SAR','foreign entity','G58-NEGATIVE',_lines
    );
    raise exception 'G58_FOREIGN_ENTITY_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_LEGAL_ENTITY_NOT_AVAILABLE' then raise; end if;
  end;

  _journal := public.onexa_create_manual_journal(
    _entity,_branch,date '2026-11-16','2026-11','SAR',
    'synthetic approved manual journal','G58-SYNTHETIC',_lines
  );
  if _journal is null or (select count(*) from public.onexa_manual_journals
    where tenant_id='tenant-smoke-A') <> 1 then
    raise exception 'G58_CREATE_FAILED';
  end if;
  _status := public.onexa_transition_manual_journal(_journal,'submitted');
  if _status <> 'submitted' then raise exception 'G58_SUBMIT_FAILED'; end if;

  -- The creator must not reject their own submitted journal.
  begin
    perform public.onexa_transition_manual_journal(_journal,'rejected','creator tries to reject');
    raise exception 'G58_CREATOR_REJECTION_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_REJECT' then raise; end if;
  end;

  -- Cancelling a submitted journal without a documented reason is denied.
  begin
    perform public.onexa_transition_manual_journal(_journal,'cancelled');
    raise exception 'G58_SUBMITTED_CANCEL_NO_REASON_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_CANCELLATION_REASON_REQUIRED' then raise; end if;
  end;

  -- A different finance creator who lacks approve may not reject another journal.
  delete from public.fixture_module_grants
   where tenant_id='tenant-smoke-A'
     and user_id='a0000000-0000-4000-8000-000000000013'::uuid
     and module_key='finance' and action='approve';
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000013',true);
  begin
    perform public.onexa_transition_manual_journal(_journal,'rejected','unauthorized rejection');
    raise exception 'G58_UNAUTHORIZED_REVIEWER_REJECTION_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_TRANSITION_NOT_AUTHORIZED:approve' then raise; end if;
  end;
  begin
    perform public.onexa_transition_manual_journal(_journal,'cancelled','not my journal');
    raise exception 'G58_OTHER_CREATOR_CANCELLATION_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_CANCEL' then raise; end if;
  end;
  perform set_config('test.user_id',_creator::text,true);

  begin
    perform public.onexa_transition_manual_journal(_journal,'approved');
    raise exception 'G58_CREATOR_SELF_APPROVAL_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_APPROVE' then raise; end if;
  end;

  perform set_config('test.user_id',_poster::text,true);
  _status := public.onexa_transition_manual_journal(_journal,'approved');
  if _status <> 'approved' then raise exception 'G58_APPROVAL_FAILED'; end if;

  _ledger := public.onexa_post_manual_journal(_journal);
  if _ledger is null or public.onexa_post_manual_journal(_journal) is distinct from _ledger then
    raise exception 'G58_POST_IDEMPOTENCY_FAILED';
  end if;
  if (select count(*) from public.onexa_journal_headers
      where source_document_type='manual_journal'
        and tenant_id='tenant-smoke-A' and source_document_id=_journal::text) <> 1
    or not exists (
      select 1 from public.onexa_manual_journal_reconciliation
      where manual_journal_id=_journal and reconciliation_status='reconciled'
    ) then
    raise exception 'G58_LEDGER_RECONCILIATION_FAILED';
  end if;

  -- A tiny 0.004 ledger/source variance must be marked as a mismatch,
  -- not silently accepted by the former 0.005 reconciliation tolerance.
  update public.onexa_journal_headers
  set total_debit = total_debit + 0.004
  where id = _ledger and tenant_id = 'tenant-smoke-A';
  if not exists (
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id = _journal and reconciliation_status = 'amount_mismatch'
  ) then
    raise exception 'G58_SUB_TOLERANCE_RECONCILIATION_ACCEPTED';
  end if;
  update public.onexa_journal_headers
  set total_debit = total_debit - 0.004
  where id = _ledger and tenant_id = 'tenant-smoke-A';
  if not exists (
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id = _journal and reconciliation_status = 'reconciled'
  ) then
    raise exception 'G58_RECONCILIATION_NOT_RESTORED';
  end if;

  _reversal := public.onexa_reverse_manual_journal(
    _journal,date '2026-11-16','2026-11','synthetic correction'
  );
  if _reversal is null
    or public.onexa_reverse_manual_journal(
      _journal,date '2026-11-16','2026-11','synthetic correction'
    ) is distinct from _reversal then
    raise exception 'G58_REVERSE_IDEMPOTENCY_FAILED';
  end if;
  -- The old reconciliation view treated ANY non-null reversal UUID as
  -- reconciled even when no reversal ledger header existed.
  update public.onexa_manual_journals
  set reversal_journal_id = gen_random_uuid()
  where id = _journal;
  if not exists (
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id = _journal and reconciliation_status = 'reversal_missing'
  ) then
    raise exception 'G58_NONEXISTENT_REVERSAL_RECONCILED';
  end if;
  update public.onexa_manual_journals
  set reversal_journal_id = _reversal
  where id = _journal;

  -- A header without a valid link to the source original is not a reversal.
  update public.onexa_journal_headers
  set reversal_of_id = null
  where id = _reversal;
  if not exists (
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id = _journal and reconciliation_status = 'reversal_mismatch'
  ) then
    raise exception 'G58_WRONG_REVERSAL_LINK_RECONCILED';
  end if;
  update public.onexa_journal_headers
  set reversal_of_id = _ledger
  where id = _reversal;

  -- A reversal must offset the original posted debit/credit exactly.
  update public.onexa_journal_headers
  set total_credit = total_credit + 0.004
  where id = _reversal;
  if not exists (
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id = _journal and reconciliation_status = 'reversal_mismatch'
  ) then
    raise exception 'G58_REVERSAL_AMOUNT_VARIANCE_RECONCILED';
  end if;
  update public.onexa_journal_headers
  set total_credit = total_credit - 0.004
  where id = _reversal;

  if (select count(*) from public.onexa_manual_journal_events
      where manual_journal_id=_journal) <> 5
    or not exists (
      select 1 from public.onexa_journal_headers
      where id=_ledger and state='reversed' and reversal_journal_id=_reversal
        and total_debit=125.25 and total_credit=125.25
    )
    or not exists (
      select 1 from public.onexa_manual_journal_reconciliation
      where manual_journal_id=_journal and status='reversed'
        and reconciliation_status='reconciled'
    ) then
    raise exception 'G58_AUDIT_HISTORY_NOT_PRESERVED';
  end if;

  -- The review decision is a reviewer-only action. A successful rejection
  -- has a reason, and the original creator can reopen then re-submit.
  perform set_config('test.user_id',_creator::text,true);
  _rejection_journal := public.onexa_create_manual_journal(
    _entity,_branch,date '2026-11-16','2026-11','SAR',
    'synthetic rejection authorization','G58-REVIEW',_lines
  );
  perform public.onexa_transition_manual_journal(_rejection_journal,'submitted');
  perform set_config('test.user_id',_poster::text,true);
  begin
    perform public.onexa_transition_manual_journal(_rejection_journal,'rejected');
    raise exception 'G58_REJECTION_WITHOUT_REASON_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_REJECTION_REASON_REQUIRED' then raise; end if;
  end;
  _status := public.onexa_transition_manual_journal(
    _rejection_journal,'rejected','requires review of original attachment'
  );
  if _status <> 'rejected' or not exists (
    select 1 from public.onexa_manual_journal_events e
    where e.manual_journal_id=_rejection_journal
      and e.event_type='status_changed' and e.to_status='rejected'
      and e.actor_id=_poster and e.reason is not null
  ) then
    raise exception 'G58_REVIEW_REJECTION_AUDIT_FAILED';
  end if;
  perform set_config('test.user_id',_creator::text,true);
  _status := public.onexa_transition_manual_journal(_rejection_journal,'draft');
  if _status <> 'draft' then raise exception 'G58_REJECTED_REOPEN_FAILED'; end if;
  perform public.onexa_transition_manual_journal(_rejection_journal,'submitted');

  -- A creator may cancel their own submitted journal with an audit reason.
  _cancel_journal := public.onexa_create_manual_journal(
    _entity,_branch,date '2026-11-16','2026-11','SAR',
    'synthetic cancellation authorization','G58-CANCEL',_lines
  );
  perform public.onexa_transition_manual_journal(_cancel_journal,'submitted');
  _status := public.onexa_transition_manual_journal(
    _cancel_journal,'cancelled','creator cancelled before approval'
  );
  if _status <> 'cancelled' then raise exception 'G58_CREATOR_CANCEL_WITH_REASON_FAILED'; end if;

  -- Gate58 itself must reject invalid reversal date-month pairs before B4.
  perform set_config('test.user_id',_poster::text,true);
  begin
    perform public.onexa_reverse_manual_journal(
      _journal,date '2026-11-16','2026-10','bad fiscal month'
    );
    raise exception 'G58_REVERSAL_PERIOD_MISMATCH_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_REVERSAL_PERIOD_INVALID' then raise; end if;
  end;
  begin
    perform public.onexa_reverse_manual_journal(
      _journal,null,'2026-11','missing reversal date'
    );
    raise exception 'G58_NULL_REVERSAL_DATE_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_REVERSAL_PERIOD_INVALID' then raise; end if;
  end;

  -- Switching to tenant B with a known tenant A UUID must not permit posting.
  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  begin
    perform public.onexa_post_manual_journal(_journal);
    raise exception 'G58_CROSS_TENANT_RPC_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_NOT_FOUND' then raise; end if;
  end;

  raise notice 'Gate 58 REAL RPC synthetic smoke PASSED; no data will persist';
end;
$case$;

-- Role-scoped, SELECT-only cross-tenant read is denied by real Gate58 RLS.
select set_config('test.tenant_id','tenant-smoke-B',true);
select set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
set local role authenticated;
do $rls$
begin
  if (select count(*) from public.onexa_manual_journals) <> 0
   or (select count(*) from public.onexa_manual_journal_reconciliation) <> 0 then
    raise exception 'G58_CROSS_TENANT_RLS_LEAK';
  end if;
end;
$rls$;
reset role;
rollback;
