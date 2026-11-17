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

  _reversal := public.onexa_reverse_manual_journal(
    _journal,date '2026-11-16','2026-11','synthetic correction'
  );
  if _reversal is null
    or public.onexa_reverse_manual_journal(
      _journal,date '2026-11-16','2026-11','synthetic correction'
    ) is distinct from _reversal then
    raise exception 'G58_REVERSE_IDEMPOTENCY_FAILED';
  end if;
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
