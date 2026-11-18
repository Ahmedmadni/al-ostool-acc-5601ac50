-- Strict B4 shared monetary/GL source contract after guarded schema patches.
-- Captured REAL B4 wrappers and real Gate58 SQL; strict publisher proposal under
-- test. SYNTHETIC tenants & ROLLBACK exclusively.
begin;
do $strict_smoke$
declare
  _entity constant uuid := 'a0000000-0000-4000-8000-000000000001';
  _maker constant uuid := 'a0000000-0000-4000-8000-000000000011';
  _ledger uuid;
  _again uuid;
  _source text;
  _count integer := 0;
  _good jsonb := jsonb_build_array(
    jsonb_build_object('account_code','5200','debit',120.25,'credit',0,
      'dimensions',jsonb_build_object('project','SYNTHETIC-PROJECT')),
    jsonb_build_object('account_code','2100','debit',0,'credit',120.25)
  );
  _bad jsonb;
begin
 if current_database() <> 'onexa_gate_test'
    or to_regclass('public.fixture_module_grants') is null then
    raise exception 'ONEXA_B4_STRICT_SMOKE_DISPOSABLE_ONLY';
 end if;
 perform set_config('test.tenant_id','tenant-smoke-A',true);
 perform set_config('test.user_id',_maker::text,true);

 if not exists (
  select 1 from pg_constraint
  where conrelid='public.onexa_journal_headers'::regclass
    and conname='onexa_journal_headers_check'
    and pg_get_constraintdef(oid,true)='CHECK (total_debit = total_credit)'
 ) or not exists (
  select 1 from pg_constraint
  where conrelid='public.onexa_journal_headers'::regclass
    and conname='onexa_journal_headers_source_document_type_check'
    and pg_get_constraintdef(oid,true) like '%manual_journal%'
 ) then
   raise exception 'G58_B4_STRICT_HOSTED_SCHEMA_PATCHES_NOT_INSTALLED_IN_FIXTURE';
 end if;

 -- These are API/source-type CONTRACT tests, not tests of the actual
 -- sales/payroll/procurement/asset workflow RPCs or their role grants.
 foreach _source in array array[
   'sales_invoice','customer_receipt','purchase_invoice','supplier_payment',
   'payroll_run','depreciation_run','project_cost','fleet_trip_cost',
   'bank_transfer','manual_journal'
 ] loop
   _ledger := public.onexa_post_journal(
    _entity,_source,'TEST-CROSS-MODULE-'||_source,1,'approved',
    jsonb_build_object('test_type',_source),date '2026-11-18','2026-11',
    'SAR','synthetic '||_source,_good
   );
   _again := public.onexa_post_journal(
    _entity,_source,'TEST-CROSS-MODULE-'||_source,1,'approved',
    jsonb_build_object('test_type',_source),date '2026-11-18','2026-11',
    'SAR','synthetic '||_source,_good
   );
   if _ledger is null or _ledger is distinct from _again or not exists(
     select 1 from public.onexa_journal_headers
     where id=_ledger and source_document_type=_source
       and tenant_id='tenant-smoke-A' and total_debit=120.25 and total_credit=120.25
   ) or (select count(*) from public.onexa_journal_lines where journal_id=_ledger)<>2
   then
     raise exception 'G58_B4_STRICT_SOURCE_CONTRACT_FAILED:%',_source;
   end if;
   _count := _count+1;
 end loop;
 if _count<>10 then raise exception 'G58_B4_STRICT_SOURCE_COVERAGE_INCOMPLETE'; end if;

 -- 0.004 discrepancy previously passed both B4 and header CHECK.
 begin
  perform public.onexa_post_journal(_entity,'sales_invoice','NEG-IMBAL',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','negative imbalance',
   jsonb_build_array(
     jsonb_build_object('account_code','5200','debit',100,'credit',0),
     jsonb_build_object('account_code','2100','debit',0,'credit',100.004)
   ));
  raise exception 'G58_B4_STRICT_IMBALANCE_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_JOURNAL_NOT_BALANCED' then raise; end if;
 end;

 -- The storage scale is four digits; source must not get silently rounded.
 begin
  perform public.onexa_post_journal(_entity,'purchase_invoice','NEG-ROUND',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','KWD','excess storage scale',
   jsonb_build_array(
     jsonb_build_object('account_code','5200','debit',100.00001,'credit',0),
     jsonb_build_object('account_code','2100','debit',0,'credit',100.00001)
   ));
  raise exception 'G58_B4_STRICT_STORAGE_ROUNDING_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_B4_STORAGE_PRECISION_INVALID' then raise; end if;
 end;

 -- SAR needs whole halalas. Other currencies still await formal scale rules.
 begin
  perform public.onexa_post_journal(_entity,'supplier_payment','NEG-SAR',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','fractional halala',
   jsonb_build_array(
     jsonb_build_object('account_code','5200','debit',100.001,'credit',0),
     jsonb_build_object('account_code','2100','debit',0,'credit',100.001)
   ));
  raise exception 'G58_B4_STRICT_FRACTIONAL_HALALA_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_B4_SAR_HALALA_PRECISION_INVALID' then raise; end if;
 end;

 -- Source payloads must explicitly supply both numerical fields on each line.
 _bad := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',100,'credit',0),
   jsonb_build_object('account_code','2100','credit',100)
 );
 begin
  perform public.onexa_post_journal(_entity,'payroll_run','NEG-MISSING',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','missing debit',
   _bad);
  raise exception 'G58_B4_STRICT_MISSING_DEBIT_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_B4_LINE_INVALID' then raise; end if;
 end;

 _bad := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',100,'credit',0),
   jsonb_build_object('account_code','2100','debit',null,'credit',100)
 );
 begin
  perform public.onexa_post_journal(_entity,'depreciation_run','NEG-NULL',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','null debit',
   _bad);
  raise exception 'G58_B4_STRICT_NULL_AMOUNT_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_B4_LINE_INVALID' then raise; end if;
 end;

 _bad := jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',100,'credit',0),
   jsonb_build_object('account_code','2100','debit','0','credit',100)
 );
 begin
  perform public.onexa_post_journal(_entity,'project_cost','NEG-TEXT',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','text as money',
   _bad);
  raise exception 'G58_B4_STRICT_TEXT_AMOUNT_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_B4_LINE_INVALID' then raise; end if;
 end;

 begin
  perform public.onexa_post_journal(_entity,'fleet_trip_cost','NEG-SOURCE-ID',1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','missing source identity',
   _good);
  raise exception 'G58_B4_STRICT_SOURCE_ID_NEGATIVE_FIXTURE_INVALID';
 exception when others then
  -- This case uses a nonempty document ID, and is expected to reach success.
  -- Its exception proves a test fixture cannot fake source validation success.
  if sqlerrm='ONEXA_B4_SOURCE_ID_REQUIRED' then raise; end if;
  if sqlerrm<>'G58_B4_STRICT_SOURCE_ID_NEGATIVE_FIXTURE_INVALID' then raise; end if;
 end;

 begin
  perform public.onexa_post_journal(_entity,'fleet_trip_cost',null,1,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','missing source identity',
   _good);
  raise exception 'G58_B4_STRICT_MISSING_SOURCE_ID_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_B4_SOURCE_ID_REQUIRED' then raise; end if;
 end;

 begin
  perform public.onexa_post_journal(_entity,'bank_transfer','NEG-STATUS',1,
   null,'{}'::jsonb,date '2026-11-18','2026-11','SAR','missing approval state',
   _good);
  raise exception 'G58_B4_STRICT_NULL_APPROVAL_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_SOURCE_NOT_APPROVED' then raise; end if;
 end;
 begin
  perform public.onexa_post_journal(_entity,'bank_transfer','NEG-REVISION',null,
   'approved','{}'::jsonb,date '2026-11-18','2026-11','SAR','missing source revision',
   _good);
  raise exception 'G58_B4_STRICT_NULL_REVISION_ACCEPTED';
 exception when others then
  if sqlerrm<>'ONEXA_INVALID_SOURCE_REVISION' then raise; end if;
 end;

 -- KWD 3 decimals remain representable (policy beyond SAR is not approved).
 _ledger:=public.onexa_post_journal(
  _entity,'purchase_invoice','TEST-KWD-3',1,'approved','{}'::jsonb,
  date '2026-11-18','2026-11','KWD','synthetic 3 decimal currency',
  jsonb_build_array(
   jsonb_build_object('account_code','5200','debit',90.125,'credit',0),
   jsonb_build_object('account_code','2100','debit',0,'credit',90.125)
  ));
 if not exists(select 1 from public.onexa_journal_headers
   where id=_ledger and currency='KWD' and total_debit=90.125 and total_credit=90.125)
 then raise exception 'G58_B4_STRICT_KWD_3_DECIMAL_REGRESSION'; end if;

 if (select count(*) from public.onexa_journal_headers)<>11
    or (select count(*) from public.onexa_posting_registry)<>11 then
    raise exception 'G58_B4_STRICT_FAILED_ATTEMPT_PERSISTED';
 end if;

 raise notice 'Strict B4 exact monetary contract PASSED across ten synthetic source types';
end;
$strict_smoke$;
rollback;
