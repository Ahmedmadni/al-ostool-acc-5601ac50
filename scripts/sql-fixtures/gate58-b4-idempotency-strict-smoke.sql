-- Shared B4 idempotency payload integrity acceptance.
-- Uses the proposed strict B4 publisher, the real public dispatch wrappers,
-- synthetic tenants, and ROLLBACK. NEVER test on customer financial records.
begin;

create function pg_temp.expect_b4_payload_conflict(
  _snapshot jsonb,
  _date date,
  _period text,
  _currency text,
  _memo text,
  _lines jsonb
) returns void language plpgsql as $expect$
begin
  begin
    perform public.onexa_post_journal(
      'a0000000-0000-4000-8000-000000000001'::uuid,
      'sales_invoice','STRICT-IDEMPOTENCY-01',1,'approved',
      _snapshot,_date,_period,_currency,_memo,_lines
    );
    raise exception 'B4_CHANGED_PAYLOAD_WAS_ACCEPTED';
  exception when others then
    if sqlerrm <> 'ONEXA_B4_POSTING_PAYLOAD_CONFLICT' then raise; end if;
  end;
end;
$expect$;

do $strict$
declare
 _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
 _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
 _first uuid;
 _second uuid;
 _good jsonb := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',80.25,'credit',0,
     'description','project expense','dimensions',jsonb_build_object('project','PRJ-1','costCenter','CC-1')),
   jsonb_build_object('account_code','2100','debit',0,'credit',80.25,
     'description','supplier accrual','dimensions',jsonb_build_object('project','PRJ-1'))
 );
 _snapshot jsonb := '{"approved":"v1","number":789}'::jsonb;
 _lines jsonb;
begin
 if current_database()<>'onexa_gate_test'
   or to_regclass('public.fixture_module_grants') is null
   or to_regclass('public.onexa_posting_registry') is null then
   raise exception 'ONEXA_B4_IDEMPOTENCY_DISPOSABLE_ONLY';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);

 _first := public.onexa_post_journal(
   _entity,'sales_invoice','STRICT-IDEMPOTENCY-01',1,'approved',
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_good);
 _second := public.onexa_post_journal(
   _entity,'sales_invoice','STRICT-IDEMPOTENCY-01',1,'approved',
   '{"number":789,"approved":"v1"}'::jsonb,
   date '2026-11-18','2026-11','SAR','approved sales invoice',_good);
 if _first is null or _second is distinct from _first then
   raise exception 'B4_IDENTICAL_RETRY_MUST_RETURN_SAME_LEDGER_ID';
 end if;
 -- Monetary 80.2500 and 80.25 are semantically equal, not source drift.
 _lines := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',80.2500,'credit',0,
     'description','project expense','dimensions',jsonb_build_object('costCenter','CC-1','project','PRJ-1')),
   jsonb_build_object('account_code','2100','debit',0,'credit',80.2500,
     'description','supplier accrual','dimensions',jsonb_build_object('project','PRJ-1'))
 );
 _second := public.onexa_post_journal(
   _entity,'sales_invoice','STRICT-IDEMPOTENCY-01',1,'approved',
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);
 if _second is distinct from _first then
   raise exception 'B4_SEMANTICALLY_IDENTICAL_NUMERIC_RETRY_REJECTED';
 end if;

 -- Reuse of identical source key must NOT hide changed source snapshots,
 -- memo, dates, fiscal period, currency, amounts, accounts, line order,
 -- free-text descriptions, or accounting dimensions.
 perform pg_temp.expect_b4_payload_conflict(
   '{"approved":"v2","number":789}'::jsonb,
   date '2026-11-18','2026-11','SAR','approved sales invoice',_good);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','changed memo',_good);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-19','2026-11','SAR','approved sales invoice',_good);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-12-02','2026-12','SAR','approved sales invoice',_good);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','KWD','approved sales invoice',_good);

 _lines := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',100.25,'credit',0,
      'description','project expense','dimensions',jsonb_build_object('project','PRJ-1','costCenter','CC-1')),
   jsonb_build_object('account_code','2100','debit',0,'credit',100.25,
      'description','supplier accrual','dimensions',jsonb_build_object('project','PRJ-1'))
 );
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);

 _lines := jsonb_build_array(
   jsonb_build_object('account_code','2100','debit',80.25,'credit',0,
      'description','project expense','dimensions',jsonb_build_object('project','PRJ-1','costCenter','CC-1')),
   jsonb_build_object('account_code','5200','debit',0,'credit',80.25,
      'description','supplier accrual','dimensions',jsonb_build_object('project','PRJ-1'))
 );
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);

 _lines := jsonb_build_array(
   _good->1,_good->0
 );
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);

 _lines := jsonb_set(_good,'{0,description}','"changed line description"'::jsonb);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);

 _lines := jsonb_set(_good,'{0,dimensions,project}','"PRJ-2"'::jsonb);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);

 _lines := jsonb_set(_good,'{0,dimensions}', '{}'::jsonb);
 perform pg_temp.expect_b4_payload_conflict(
   _snapshot,date '2026-11-18','2026-11','SAR','approved sales invoice',_lines);

 -- Even if a GL receipt is accidentally corrupted, an identical request must
 -- not return an invalid UUID as successful. The subtransaction rolls back.
 begin
   update public.onexa_journal_headers
     set memo='corrupted stored memo' where id=_first;
   perform public.onexa_post_journal(_entity,'sales_invoice','STRICT-IDEMPOTENCY-01',
     1,'approved',_snapshot,date '2026-11-18','2026-11','SAR',
     'approved sales invoice',_good);
   raise exception 'B4_CORRUPTED_GL_RECEIPT_ACCEPTED';
 exception when others then
   if sqlerrm <> 'ONEXA_B4_POSTING_PAYLOAD_CONFLICT' then raise; end if;
 end;
 begin
   update public.onexa_journal_lines
     set account_code='2100' where journal_id=_first and line_number=1;
   perform public.onexa_post_journal(_entity,'sales_invoice','STRICT-IDEMPOTENCY-01',
     1,'approved',_snapshot,date '2026-11-18','2026-11','SAR',
     'approved sales invoice',_good);
   raise exception 'B4_CORRUPTED_LEDGER_LINE_ACCEPTED';
 exception when others then
   if sqlerrm <> 'ONEXA_B4_POSTING_PAYLOAD_CONFLICT' then raise; end if;
 end;

 -- An existing reversed header is still a historical receipt for the
 -- identical posting key; this retry must NEVER create a second GL entry.
 begin
   update public.onexa_journal_headers set state='reversed' where id=_first;
   if public.onexa_post_journal(
      _entity,'sales_invoice','STRICT-IDEMPOTENCY-01',1,'approved',
      _snapshot,date '2026-11-18','2026-11','SAR',
      'approved sales invoice',_good) is distinct from _first then
     raise exception 'B4_REVERSED_ORIGINAL_RETRY_DUPLICATED';
   end if;
   raise exception 'B4_REVERSED_RETRY_CONFIRMED';
 exception when others then
   if sqlerrm <> 'B4_REVERSED_RETRY_CONFIRMED' then raise; end if;
 end;

 if (select count(*) from public.onexa_posting_registry
       where source_document_id='STRICT-IDEMPOTENCY-01') <> 1
    or (select count(*) from public.onexa_journal_headers
       where source_document_id='STRICT-IDEMPOTENCY-01') <> 1
    or (select count(*) from public.onexa_journal_lines
       where journal_id=_first) <> 2
    or (select count(*) from public.onexa_workspace_audit_events
       where action='journal_posted' and entity_id=_first::text) <> 1 then
   raise exception 'B4_IDEMPOTENCY_CONFLICT_CREATED_DUPLICATE_GL_OR_AUDIT';
 end if;
 raise notice 'Strict B4 duplicate key payload comparison passed (unchanged replay + changed input denials)';
end;
$strict$;
rollback;
