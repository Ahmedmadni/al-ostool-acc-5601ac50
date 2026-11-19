-- Reproduce real hosted B4 silent reversal replay with changed reason/date.
-- Actual captured B4 source, synthetic legal entities, ROLLBACK. No customer data.
begin;
do $old_reverse$
declare
  _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
  _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
  _original uuid;
  _reversal uuid;
  _retry uuid;
begin
  if current_database() <> 'onexa_gate_test'
     or to_regclass('public.fixture_module_grants') is null then
    raise exception 'ONEXA_B4_REVERSE_LEGACY_DISPOSABLE_ONLY';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id',_maker::text,true);

  _original := public.onexa_post_journal(
    _entity,'sales_invoice','B4-LEGACY-REVERSAL-001',1,'approved',
    '{"invoice":"synthetic"}'::jsonb,date '2026-11-18','2026-11','SAR',
    'synthetic original sale',jsonb_build_array(
      jsonb_build_object('account_code','5200','debit',91.25,'credit',0),
      jsonb_build_object('account_code','2100','debit',0,'credit',91.25)
    )
  );
  _reversal := public.onexa_reverse_journal(
    _original,date '2026-12-01','2026-12','approved documented reason'
  );
  _retry := public.onexa_reverse_journal(
    _original,date '2026-12-02','2026-12','different unapproved reason'
  );
  if _original is null or _reversal is null or _retry is distinct from _reversal
     or not exists(
       select 1 from public.onexa_journal_headers
       where id=_reversal and accounting_date=date '2026-12-01'
         and source_snapshot->>'reason'='approved documented reason'
         and reversal_of_id=_original
     ) then
    raise exception 'B4_LEGACY_CHANGED_REVERSAL_RETRY_NOT_REPRODUCED';
  end if;
  _retry := public.onexa_reverse_journal(
    _original,date '2026-12-01','2026-11','approved documented reason'
  );
  if _retry is distinct from _reversal then
    raise exception 'B4_LEGACY_INVALID_REVERSAL_PERIOD_NOT_REPRODUCED';
  end if;
  if (select count(*) from public.onexa_journal_headers
        where source_document_id=_original::text
          and source_document_type='journal_reversal')<>1
     or (select count(*) from public.onexa_workspace_audit_events
        where entity_id=_original::text and action='journal_reversed')<>1 then
    raise exception 'B4_LEGACY_REVERSAL_RETRY_CREATED_UNEXPECTED_JOURNAL';
  end if;
  raise notice 'Legacy B4 silently accepted different reversal reason, date, and period';
end $old_reverse$;
rollback;
