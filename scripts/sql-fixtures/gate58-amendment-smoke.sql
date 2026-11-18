-- Gate 58 amendment acceptance: REAL Gate58 functions, FAKE B4,
-- disposable PostgreSQL only. This entire test is rolled back.
begin;
do $amend_smoke$
declare
  _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
  _branch constant uuid := 'a0000000-0000-4000-8000-000000000002';
  _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
  _reviewer constant uuid := 'a0000000-0000-4000-8000-000000000012';
  _journal uuid;
  _ledger uuid;
  _rev integer;
  _original jsonb := jsonb_build_array(
    jsonb_build_object('line_number',1,'account_code','5200','debit',125.25,'credit',0),
    jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',125.25)
  );
  _corrected jsonb := jsonb_build_array(
    jsonb_build_object('line_number',1,'account_code','5200','debit',240.75,'credit',0,'description','corrected'),
    jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',240.75)
  );
  _final jsonb := jsonb_build_array(
    jsonb_build_object('line_number',1,'account_code','5200','debit',260.25,'credit',0),
    jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',260.25)
  );
begin
  if current_database() <> 'onexa_gate_test' then
    raise exception 'G58_AMEND_DISPOSABLE_POSTGRES_ONLY';
  end if;
  if to_regprocedure('public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)') is null
    or has_function_privilege('anon',
      'public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)', 'EXECUTE') then
    raise exception 'G58_AMEND_RPC_MISSING_OR_ANON_ACCESS_ALLOWED';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id',_maker::text,true);

  _journal := public.onexa_create_manual_journal(_entity,_branch,
    date '2026-11-18','2026-11','SAR','original memo','ORIGINAL',_original);
  if (select revision from public.onexa_manual_journals where id=_journal) <> 1 then
    raise exception 'G58_AMEND_ORIGINAL_REVISION_WRONG';
  end if;

  -- Existing creator's draft must be amendable, with both snapshots preserved.
  _rev := public.onexa_amend_manual_journal(
    _journal,1,'corrected memo','CORRECTED',_corrected);
  if _rev <> 2 or not exists (
    select 1 from public.onexa_manual_journals
    where id=_journal and revision=2 and status='draft'
      and total_debit=240.75 and total_credit=240.75
      and memo='corrected memo' and external_reference='CORRECTED'
  ) or (select count(*) from public.onexa_manual_journal_lines
    where manual_journal_id=_journal) <> 2 then
    raise exception 'G58_AMEND_DRAFT_UPDATE_FAILED';
  end if;
  if not exists (
    select 1 from public.onexa_manual_journal_events
    where manual_journal_id=_journal and event_type='amended'
      and actor_id=_maker
      and (event_data->>'previous_revision')::int=1
      and (event_data->>'new_revision')::int=2
      and (event_data #>> '{before,total_debit}')::numeric=125.25
      and (event_data #>> '{after,total_debit}')::numeric=240.75
      and jsonb_array_length(event_data #> '{before,lines}')=2
      and jsonb_array_length(event_data #> '{after,lines}')=2
  ) then
    raise exception 'G58_AMEND_AUDIT_SNAPSHOTS_MISSING';
  end if;

  -- A stale browser tab must not overwrite a newer revision.
  begin
    perform public.onexa_amend_manual_journal(
      _journal,1,'stale overwrite',null,_original);
    raise exception 'G58_STALE_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_REVISION_CONFLICT' then raise; end if;
  end;
  -- Unequal amounts cannot reach the stored lines or header.
  begin
    perform public.onexa_amend_manual_journal(
      _journal,2,'wrong balance',null,jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',200,'credit',0),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',199)
      ));
    raise exception 'G58_UNBALANCED_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_NOT_BALANCED' then raise; end if;
  end;
  begin
    perform public.onexa_amend_manual_journal(
      _journal,2,'fractional halala',null,jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',100.001,'credit',0),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',100.001)
      ));
    raise exception 'G58_FRACTIONAL_HALALA_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_SAR_PRECISION_INVALID' then raise; end if;
  end;
  begin
    perform public.onexa_amend_manual_journal(
      _journal,2,'missing credit',null,jsonb_build_array(
        jsonb_build_object('line_number',1,'account_code','5200','debit',240.75),
        jsonb_build_object('line_number',2,'account_code','2100','debit',0,'credit',240.75)
      ));
    raise exception 'G58_NULL_SIDE_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_LINE_INVALID' then raise; end if;
  end;

  -- An authorized finance colleague still cannot amend another creator's draft.
  perform set_config('test.user_id',_reviewer::text,true);
  begin
    perform public.onexa_amend_manual_journal(
      _journal,2,'not creator',null,_original);
    raise exception 'G58_DIFFERENT_MAKER_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_AMEND' then raise; end if;
  end;

  -- A known UUID from another tenant is not a resource to amend.
  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  begin
    perform public.onexa_amend_manual_journal(
      _journal,2,'foreign tenant',null,_original);
    raise exception 'G58_CROSS_TENANT_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_NOT_FOUND' then raise; end if;
  end;

  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id',_maker::text,true);
  perform public.onexa_transition_manual_journal(_journal,'submitted');
  begin
    perform public.onexa_amend_manual_journal(
      _journal,2,'edit after submission',null,_original);
    raise exception 'G58_SUBMITTED_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_AMEND_STATUS_INVALID' then raise; end if;
  end;
  perform set_config('test.user_id',_reviewer::text,true);
  perform public.onexa_transition_manual_journal(
    _journal,'rejected','incorrect amount for November');

  -- The maker edits the rejected journal WITHOUT erasing the rejection event.
  perform set_config('test.user_id',_maker::text,true);
  _rev := public.onexa_amend_manual_journal(
    _journal,2,'rejected journal corrected','CORRECTED-2',_final);
  if _rev <> 3 or not exists (
    select 1 from public.onexa_manual_journals
    where id=_journal and status='draft' and revision=3
      and rejected_by is null and rejected_at is null
      and total_debit=260.25
  ) or (select count(*) from public.onexa_manual_journal_events
    where manual_journal_id=_journal and to_status='rejected') <> 1
    or (select count(*) from public.onexa_manual_journal_events
    where manual_journal_id=_journal and event_type='amended') <> 2 then
    raise exception 'G58_REJECTED_AMEND_REVISION_OR_HISTORY_FAILED';
  end if;
  perform public.onexa_transition_manual_journal(_journal,'submitted');
  perform set_config('test.user_id',_reviewer::text,true);
  perform public.onexa_transition_manual_journal(_journal,'approved');
  _ledger := public.onexa_post_manual_journal(_journal);
  if _ledger is null or not exists(
    select 1 from public.onexa_journal_headers
    where id=_ledger and source_document_type='manual_journal'
      and source_document_id=_journal::text and source_revision=3
      and total_debit=260.25
  ) or not exists (
    select 1 from public.onexa_manual_journal_reconciliation
    where manual_journal_id=_journal and reconciliation_status='reconciled'
  ) then
    raise exception 'G58_AMENDED_REPOST_LEDGER_REVISION_FAILED';
  end if;
  perform set_config('test.user_id',_maker::text,true);
  begin
    perform public.onexa_amend_manual_journal(
      _journal,3,'edit posted journal',null,_original);
    raise exception 'G58_POSTED_AMEND_ALLOWED';
  exception when others then
    if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_AMEND_STATUS_INVALID' then raise; end if;
  end;
  raise notice 'Gate58 amendment SQL smoke PASSED (all synthetic operations rollback)';
end;
$amend_smoke$;
rollback;
