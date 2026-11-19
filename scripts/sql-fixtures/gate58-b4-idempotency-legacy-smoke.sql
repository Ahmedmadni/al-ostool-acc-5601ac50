-- Reproduce a real hosted B4 idempotency design flaw using original captured
-- function definitions, synthetic tenants, and ROLLBACK. No production data.
begin;
do $legacy$
declare
 _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
 _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
 _first uuid;
 _second uuid;
 _original jsonb := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',80.25,'credit',0,'description','test cost'),
   jsonb_build_object('account_code','2100','debit',0,'credit',80.25)
 );
 _changed jsonb := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',90.50,'credit',0,'description','tampered cost'),
   jsonb_build_object('account_code','2100','debit',0,'credit',90.50)
 );
begin
 if current_database()<>'onexa_gate_test'
   or to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_B4_LEGACY_IDEMPOTENCY_DISPOSABLE_ONLY';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);
 _first := public.onexa_post_journal(
   _entity,'sales_invoice','LEGACY-IDEMPOTENCY-01',1,'approved',
   '{"original":true}'::jsonb,date '2026-11-18','2026-11','SAR',
   'original financial document',_original);
 _second := public.onexa_post_journal(
   _entity,'sales_invoice','LEGACY-IDEMPOTENCY-01',1,'approved',
   '{"original":false}'::jsonb,date '2026-11-18','2026-11','SAR',
   'changed financial document',_changed);
 if _first is null or _first is distinct from _second
   or not exists (
     select 1 from public.onexa_journal_headers where id=_first
       and total_debit=80.25 and total_credit=80.25
       and memo='original financial document'
       and source_snapshot='{"original":true}'::jsonb
   ) or (select count(*) from public.onexa_posting_registry
         where source_document_id='LEGACY-IDEMPOTENCY-01')<>1 then
   raise exception 'B4_LEGACY_IDEMPOTENCY_BUG_NOT_REPRODUCED';
 end if;
 raise notice 'Legacy B4 silently returned existing GL ID for DIFFERENT approved source payload';
end;
$legacy$;
rollback;
