-- Synthetic positive data for B4 ledger-integrity CI.
-- Permanently inserted ONLY into onexa_gate_test disposable PostgreSQL.
do $synthetic$
declare
  _e uuid := 'a0000000-0000-4000-8000-000000000001';
  _id uuid;
  _r uuid;
  _lines jsonb := jsonb_build_array(
    jsonb_build_object('account_code','5200','debit',200.25,'credit',0,
      'description','synthetic project expense',
      'dimensions',jsonb_build_object('project','AUDIT-PRJ','costCenter','AUDIT-CC')),
    jsonb_build_object('account_code','2100','debit',0,'credit',200.25,
      'description','synthetic supplier accrual')
  );
  _typ text;
begin
  if current_database() <> 'onexa_gate_test'
    or to_regclass('public.fixture_module_grants') is null
    or to_regclass('public.onexa_posting_registry') is null then
    raise exception 'ONEXA_B4_INTEGRITY_SEED_DISPOSABLE_ONLY';
  end if;
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
  foreach _typ in array array['sales_invoice','purchase_invoice',
    'payroll_run','bank_transfer','customer_receipt'] loop
    _id := public.onexa_post_journal(
      _e,_typ,'INTEGRITY-SEED-'||_typ,1,'approved',
      jsonb_build_object('origin','synthetic-integrity-test','type',_typ),
      date '2026-11-18','2026-11','SAR',
      'Synthetic B4 integrity '||_typ,_lines
    );
    if _id is null then raise exception 'INTEGRITY_SEED_POST_FAILED'; end if;
    if _typ='sales_invoice' then
      _r := public.onexa_reverse_journal(
        _id,date '2026-12-03','2026-12','confirmed integrity correction'
      );
      if _r is null then raise exception 'INTEGRITY_SEED_REVERSE_FAILED'; end if;
    end if;
  end loop;
  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  _id := public.onexa_post_journal(
    'b0000000-0000-4000-8000-000000000001'::uuid,
    'sales_invoice','INTEGRITY-SEED-TENANT-B',1,'approved',
    '{"origin":"synthetic-tenant-B"}'::jsonb,
    date '2026-11-18','2026-11','SAR','Synthetic isolated tenant',
    _lines
  );
  if _id is null then raise exception 'INTEGRITY_TENANT_B_SEED_FAILED'; end if;
  raise notice 'Six synthetic source documents and one contra GL posted for integrity verification';
end $synthetic$;
