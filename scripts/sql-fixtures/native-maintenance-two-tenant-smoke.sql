-- Gate76 EPHEMERAL POSTGRES ONLY. All writes below are rolled back.
-- Real G71..G75 SQL was installed into this throwaway service beforehand;
-- the Gate42 and ONEXA parent tables are synthetic contract fixtures.
-- No real tenant/customer/accounting data appears here.
insert into public.onexa_company_module_scopes
  (tenant_id,legal_entity_id,legacy_company_code,module_key,is_active)
values
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000001','OM','projects',true),
 ('tenant-smoke-B','b0000000-0000-4000-8000-000000000001','OM','projects',true);

begin;
set local role authenticated;
do $native_creation$
declare
  _site_a uuid; _asset_a uuid; _work_a uuid;
  _site_b uuid; _asset_b uuid; _work_b uuid;
  _claim uuid; _scope uuid;
  _rejected boolean;
begin
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
  if not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'SMOKE_G71_A_OM_SCOPE_UNEXPECTED_DENIAL';
  end if;
  _site_a:=public.onexa_create_operations_site(
    'a0000000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000002','AAA1','A TEST SITE');
  _asset_a:=public.onexa_create_operations_asset(_site_a,'AA01','A TEST ASSET','equipment');
  _work_a:=public.onexa_create_operations_work_order(
    _site_a,_asset_a,'a0000000-0000-4000-8000-000000000003',
    'a0000000-0000-4000-8000-000000000004',
    'A work order','Testing tenant A');
  perform set_config('smoke.work_a',_work_a::text,true);
  perform set_config('smoke.site_a',_site_a::text,true);

  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000012',true);
  perform public.onexa_transition_operations_work_order(
    _work_a,'approved',null,'Finance approves the service');
  perform public.onexa_transition_operations_work_order(
    _work_a,'assigned','a0000000-0000-4000-8000-000000000013','Assign technician');

  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000013',true);
  perform public.onexa_transition_operations_work_order(
    _work_a,'in_progress',null,'Started work');
  perform public.onexa_transition_operations_work_order(
    _work_a,'completed',null,'Work completed and documented');

  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000014',true);
  perform public.onexa_transition_operations_work_order(
    _work_a,'accepted',null,'Accepted by independent person');

  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
  _scope:=public.onexa_save_native_maintenance_cost_scope(
    _work_a,'a0000000-0000-4000-8000-000000000005');
  _claim:=public.onexa_register_native_unpaid_maintenance_source(
    _work_a,'unbilled_subcontract','SMOKE-SUBCONTRACT-A',125.0000,'SYNTHETIC-EVIDENCE-001');
  perform set_config('smoke.claim_a',_claim::text,true);
  perform set_config('smoke.scope_a',_scope::text,true);

  -- Claim creation itself MUST NOT permit direct self-approval.
  _rejected:=false;
  begin
    perform public.onexa_review_native_unpaid_maintenance_source(_claim,true,'SELF REVIEW MUST FAIL');
  exception when others then
    if sqlerrm<>'ONEXA_GATE75_INDEPENDENT_FINANCE_REVIEW_REQUIRED' then raise; end if;
    _rejected:=true;
  end;
  if not _rejected then raise exception 'SMOKE_CREATOR_SELF_REVIEW_ALLOWED'; end if;

  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000012',true);
  perform public.onexa_review_native_unpaid_maintenance_source(
    _claim,true,'Third party evidence reviewed in synthetic fixture');

  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  if not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'SMOKE_G71_B_OM_SCOPE_UNEXPECTED_DENIAL';
  end if;
  _site_b:=public.onexa_create_operations_site(
    'b0000000-0000-4000-8000-000000000001',
    'b0000000-0000-4000-8000-000000000002','BBB1','B TEST SITE');
  _asset_b:=public.onexa_create_operations_asset(_site_b,'BB01','B TEST ASSET','equipment');
  _work_b:=public.onexa_create_operations_work_order(
    _site_b,_asset_b,'b0000000-0000-4000-8000-000000000003',
    'b0000000-0000-4000-8000-000000000004','B work order',null);
  perform set_config('smoke.work_b',_work_b::text,true);

  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
  if (select count(*) from public.onexa_operations_work_orders)<>1 then
    raise exception 'SMOKE_CROSS_TENANT_RLS_WORK_ORDER_VISIBLE';
  end if;
  if (select count(*) from public.onexa_native_maintenance_unpaid_sources)<>1 then
    raise exception 'SMOKE_CROSS_TENANT_SOURCE_UNEXPECTED_COUNT';
  end if;
  -- Gate 88: a foreign UUID must not reveal a tenant B site, asset or work order.
  -- Test direct ID probes under tenant A authenticated context (not only counts).
  if exists (select 1 from public.onexa_operations_sites where id=_site_b) then
    raise exception 'SMOKE_GATE88_FOREIGN_SITE_VISIBLE_BY_ID';
  end if;
  if exists (select 1 from public.onexa_operations_assets where id=_asset_b) then
    raise exception 'SMOKE_GATE88_FOREIGN_ASSET_VISIBLE_BY_ID';
  end if;
  if exists (select 1 from public.onexa_operations_work_orders where id=_work_b) then
    raise exception 'SMOKE_GATE88_FOREIGN_WORK_ORDER_VISIBLE_BY_ID';
  end if;

  _rejected:=false;
  begin
    perform public.onexa_create_operations_work_order(_site_b,_asset_b,
      'b0000000-0000-4000-8000-000000000003',
      'b0000000-0000-4000-8000-000000000004','ILLEGAL CROSS TENANT',null);
  exception when others then
    if sqlerrm<>'ONEXA_WORK_ORDER_SITE_NOT_ACCESSIBLE' then raise; end if;
    _rejected:=true;
  end;
  if not _rejected then raise exception 'SMOKE_CROSS_TENANT_WORK_ORDER_CREATED'; end if;

  _rejected:=false;
  begin
    perform public.onexa_register_native_unpaid_maintenance_source(
      _work_b,'unbilled_subcontract','B-FOREIGN-REF',50,'FOREIGN-EVIDENCE');
  exception when others then
    if sqlerrm<>'ONEXA_GATE75_ACCEPTED_WORK_ORDER_AND_COST_CENTER_REQUIRED' then raise; end if;
    _rejected:=true;
  end;
  if not _rejected then raise exception 'SMOKE_CROSS_TENANT_CLAIM_REGISTERED'; end if;

  -- Gate 89: verify isolation in the reverse direction (tenant B -> tenant A).
  perform set_config('test.tenant_id','tenant-smoke-B',true);
  perform set_config('test.user_id','b0000000-0000-4000-8000-000000000011',true);
  if exists (select 1 from public.onexa_operations_sites where id=_site_a) then
    raise exception 'SMOKE_GATE89_FOREIGN_SITE_A_VISIBLE_TO_B';
  end if;
  if exists (select 1 from public.onexa_operations_assets where id=_asset_a) then
    raise exception 'SMOKE_GATE89_FOREIGN_ASSET_A_VISIBLE_TO_B';
  end if;
  if exists (select 1 from public.onexa_operations_work_orders where id=_work_a) then
    raise exception 'SMOKE_GATE89_FOREIGN_WORK_ORDER_A_VISIBLE_TO_B';
  end if;
  if exists (select 1 from public.onexa_native_maintenance_unpaid_sources where id=_claim) then
    raise exception 'SMOKE_GATE89_FOREIGN_UNPAID_SOURCE_A_VISIBLE_TO_B';
  end if;
  -- Restore tenant A for the remaining existing negative scenarios.
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);

  -- Direct UPDATE/DELETE access must not be granted to authenticated.
  if has_table_privilege('authenticated',
        'public.onexa_native_maintenance_unpaid_sources','INSERT')
     or has_table_privilege('authenticated',
        'public.onexa_native_maintenance_unpaid_sources','UPDATE')
     or has_table_privilege('authenticated',
        'public.onexa_native_maintenance_unpaid_sources','DELETE') then
    raise exception 'SMOKE_SOURCE_DIRECT_CLIENT_WRITES_ALLOWED';
  end if;
end;
$native_creation$;

-- A reserved maintenance source must not be bookable via a normal G42
-- document that omits the reviewed Gate75 claim. Test as privileged insert to
-- demonstrate that the SERVER trigger, not only UI/RLS, enforces this.
reset role;
do $reserved_reference$
declare
  _blocked boolean:=false;
begin
  begin
    insert into public.onexa_business_documents
      (id,tenant_id,legal_entity_id,branch_id,document_type,module_key,
       status,origin,currency,source_snapshot,gross_total,subtotal,
       external_reference,document_number)
    values (
      'a0000000-0000-4000-8000-000000000022','tenant-smoke-A',
      'a0000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000002',
      'project_cost','projects','draft','native','SAR','{}'::jsonb,125,125,
      'SMOKE-SUBCONTRACT-A','BYPASS-DOC'
    );
  exception when others then
    if sqlerrm<>'ONEXA_GATE75_RESERVED_SOURCE_REFERENCE_REQUIRES_APPROVED_CLAIM'
      then raise; end if;
    _blocked:=true;
  end;
  if not _blocked then raise exception 'SMOKE_UNTAGGED_G42_REFERENCE_BYPASS_ALLOWED'; end if;
end;
$reserved_reference$;

-- Use the fixture's superuser to simulate an already posted Gate42 document;
-- the actual Gate42 approval, accounting and posting engine is NOT under test
-- here. This row MUST pass the G75 original document guard.
reset role;
insert into public.onexa_journal_headers
  (id,tenant_id,legal_entity_id,state,source_document_type,
   source_document_id,source_revision,currency,total_debit,total_credit)
values
 ('a0000000-0000-4000-8000-000000000020','tenant-smoke-A',
  'a0000000-0000-4000-8000-000000000001','posted','project_cost',
  'a0000000-0000-4000-8000-000000000021',1,'SAR',125,125);
insert into public.onexa_business_documents
  (id,tenant_id,legal_entity_id,branch_id,document_type,module_key,
   status,origin,posted_journal_id,currency,source_snapshot,gross_total,
   tax_total,discount_total,subtotal,revision,external_reference,document_number)
values (
 'a0000000-0000-4000-8000-000000000021','tenant-smoke-A',
 'a0000000-0000-4000-8000-000000000001',
 'a0000000-0000-4000-8000-000000000002','project_cost','projects',
 'posted','native','a0000000-0000-4000-8000-000000000020','SAR',
 jsonb_build_object(
   'source_kind','unpaid_direct_cost',
   'project_cost_center_id','a0000000-0000-4000-8000-000000000005',
   'maintenance_source_claim_id',current_setting('smoke.claim_a',true)
 ),125,0,0,125,1,'SMOKE-SUBCONTRACT-A','TESTDOC-A'
);
insert into public.onexa_project_cost_postings
  (document_id,tenant_id,legal_entity_id,project_cost_center_id,
   amount,source_revision,journal_id,posted_by)
values
 ('a0000000-0000-4000-8000-000000000021','tenant-smoke-A',
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000005',125,1,
  'a0000000-0000-4000-8000-000000000020',
  'a0000000-0000-4000-8000-000000000015');

set local role authenticated;
do $finance_attribution$
declare
  _work uuid:=current_setting('smoke.work_a',true)::uuid;
  _claim uuid:=current_setting('smoke.claim_a',true)::uuid;
  _attr uuid;
begin
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000014',true);
  _attr:=public.onexa_attribute_posted_project_cost(
    _work,'a0000000-0000-4000-8000-000000000021');
  if _attr is null then raise exception 'SMOKE_GATE74_NOT_ATTRIBUTED'; end if;
  perform public.onexa_link_native_unpaid_maintenance_source(
    _claim,'a0000000-0000-4000-8000-000000000021');
  if not exists (
    select 1 from public.onexa_native_maintenance_source_reconciliation
    where id=_claim and status='linked'
      and current_reconciliation_status='reconciled'
  ) then raise exception 'SMOKE_GATE75_LINK_RECONCILIATION_FAILED'; end if;

  -- Retry should be idempotent, with no duplicate GL transaction created.
  perform public.onexa_link_native_unpaid_maintenance_source(
    _claim,'a0000000-0000-4000-8000-000000000021');
  if (select count(*) from public.onexa_native_maintenance_cost_attributions
      where work_order_id=_work)<>1 then
    raise exception 'SMOKE_DUPLICATED_ATTRIBUTION';
  end if;
end;
$finance_attribution$;

reset role;
-- Accounting reversals must change current reconciliation without
-- editing/deleting historic source claims or introducing a second journal.
update public.onexa_journal_headers set state='reversed'
where id='a0000000-0000-4000-8000-000000000020';
set local role authenticated;
do $test_reversal$
declare
  _claim uuid:=current_setting('smoke.claim_a',true)::uuid;
begin
  perform set_config('test.tenant_id','tenant-smoke-A',true);
  perform set_config('test.user_id','a0000000-0000-4000-8000-000000000014',true);
  if not exists (
    select 1 from public.onexa_native_maintenance_source_reconciliation
    where id=_claim
      and current_reconciliation_status='original_journal_reversed_or_missing'
  ) then raise exception 'SMOKE_REVERSED_GL_STILL_RECONCILED'; end if;
  if exists (
    select 1 from public.onexa_native_maintenance_cost_reconciliation
    where document_id='a0000000-0000-4000-8000-000000000021'
      and reconciliation_status='reconciled'
  ) then raise exception 'SMOKE_REVERSED_GL_STILL_IN_COST_TOTAL'; end if;
end;
$test_reversal$;

rollback;
select 'GATE76_EPHEMERAL_POSTGRES_NATIVE_71_75_SMOKE_PASSED' as result;
