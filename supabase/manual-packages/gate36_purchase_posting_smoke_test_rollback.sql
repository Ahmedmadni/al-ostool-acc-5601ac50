-- ONEXA Gate 36 rollback-only procurement posting smoke test.
-- Creates a temporary mixed purchase invoice (inventory + expense + asset),
-- posts and reconciles it, then rolls back every test row.

begin;

do $smoke_test$
declare
  _tenant_id constant text := 'tenant-001-al-ostool';
  _legal_entity_id constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _creator uuid;
  _poster uuid;
  _branch_id uuid;
  _warehouse_id uuid := gen_random_uuid();
  _item_id uuid := gen_random_uuid();
  _vendor_id uuid := gen_random_uuid();
  _document_id uuid;
  _journal_id uuid;
  _transition_result text;
  _period_code text := to_char(current_date, 'YYYY-MM');
  _quantity numeric;
  _inventory_value numeric;
  _status text;
  _posted_journal_id uuid;
  _movement_count integer;
  _run_count integer;
  _reconciliation_status text;
begin
  if not exists (
    select 1 from public.onexa_module_entitlements
    where tenant_id = _tenant_id and module_key = 'procurement' and is_enabled = true
  ) then raise exception 'ONEXA_SMOKE_PROCUREMENT_MODULE_NOT_ENABLED'; end if;

  select membership.user_id into _creator
  from public.onexa_workspace_memberships membership
  join auth.users auth_user on auth_user.id = membership.user_id
  where membership.tenant_id = _tenant_id and membership.status = 'active'
    and membership.role_key in ('accountant', 'finance_manager', 'workspace_owner')
  order by case membership.role_key when 'accountant' then 1 when 'finance_manager' then 2 else 3 end,
    membership.user_id
  limit 1;
  if _creator is null then raise exception 'ONEXA_SMOKE_CREATOR_REQUIRED'; end if;

  select membership.user_id into _poster
  from public.onexa_workspace_memberships membership
  join auth.users auth_user on auth_user.id = membership.user_id
  where membership.tenant_id = _tenant_id and membership.status = 'active'
    and membership.role_key in ('finance_manager', 'workspace_owner')
    and membership.user_id <> _creator
  order by case membership.role_key when 'finance_manager' then 1 else 2 end,
    membership.user_id
  limit 1;
  if _poster is null then raise exception 'ONEXA_SMOKE_DISTINCT_FINANCE_POSTER_REQUIRED'; end if;

  select id into _branch_id
  from public.onexa_branches
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id and is_active = true
  order by id limit 1;
  if _branch_id is null then raise exception 'ONEXA_SMOKE_ACTIVE_BRANCH_REQUIRED'; end if;

  if exists (
    select 1 from public.onexa_purchase_posting_configuration_gaps
    where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id
  ) then raise exception 'ONEXA_SMOKE_PURCHASE_ACCOUNT_MAPPING_GAPS_REMAIN'; end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _creator::text,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant_id)
    )::text,
    true
  );

  select public.onexa_create_business_document(
    _legal_entity_id => _legal_entity_id,
    _branch_id => _branch_id,
    _module_key => 'procurement',
    _document_type => 'purchase_invoice',
    _document_date => current_date,
    _accounting_date => current_date,
    _due_date => current_date + 30,
    _currency => 'SAR',
    _party_type => 'vendor',
    _party_id => _vendor_id,
    _party_name_snapshot => 'مورد اختبار ترحيل ONEXA',
    _external_reference => 'ONEXA-G36-ROLLBACK-SMOKE',
    _origin => 'native',
    _import_batch_id => null,
    _subtotal => 300,
    _discount_total => 0,
    _tax_total => 45,
    _gross_total => 345,
    _dimensions => jsonb_build_object('smoke_test', true),
    _source_snapshot => jsonb_build_object('test_type', 'rollback_only', 'posting_contract_version', 'procurement-v1'),
    _memo => 'Gate 36 rollback-only procurement posting smoke test',
    _lines => jsonb_build_array(
      jsonb_build_object(
        'line_number', 1, 'description', 'صنف مخزني مؤقت',
        'quantity', 2, 'unit_of_measure', 'EA', 'unit_price', 50,
        'discount_amount', 0, 'net_amount', 100,
        'tax_code', 'VAT15', 'tax_rate', 15, 'tax_amount', 15, 'gross_amount', 115,
        'item_id', _item_id, 'warehouse_id', _warehouse_id,
        'account_role', 'inventory', 'dimensions', jsonb_build_object('smoke_test', true)
      ),
      jsonb_build_object(
        'line_number', 2, 'description', 'مصروف مشتريات مؤقت',
        'quantity', 1, 'unit_of_measure', 'EA', 'unit_price', 100,
        'discount_amount', 0, 'net_amount', 100,
        'tax_code', 'VAT15', 'tax_rate', 15, 'tax_amount', 15, 'gross_amount', 115,
        'account_role', 'purchase_expense', 'dimensions', jsonb_build_object('smoke_test', true)
      ),
      jsonb_build_object(
        'line_number', 3, 'description', 'أصل ثابت مؤقت',
        'quantity', 1, 'unit_of_measure', 'EA', 'unit_price', 100,
        'discount_amount', 0, 'net_amount', 100,
        'tax_code', 'VAT15', 'tax_rate', 15, 'tax_amount', 15, 'gross_amount', 115,
        'account_role', 'fixed_asset_cost', 'dimensions', jsonb_build_object('smoke_test', true)
      )
    )
  ) into _document_id;

  if _document_id is null then raise exception 'ONEXA_SMOKE_DOCUMENT_CREATION_FAILED'; end if;

  select public.onexa_transition_business_document(
    _document_id, 'submitted', 'rollback smoke test submission'
  ) into _transition_result;
  if _transition_result <> 'submitted' then raise exception 'ONEXA_SMOKE_SUBMISSION_FAILED:%', _transition_result; end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _poster::text,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant_id)
    )::text,
    true
  );

  select public.onexa_transition_business_document(
    _document_id, 'approved', 'rollback smoke test approval'
  ) into _transition_result;
  if _transition_result <> 'approved' then raise exception 'ONEXA_SMOKE_APPROVAL_FAILED:%', _transition_result; end if;

  select public.onexa_post_purchase_invoice(_document_id, _period_code) into _journal_id;
  if _journal_id is null then raise exception 'ONEXA_SMOKE_POSTING_DID_NOT_RETURN_JOURNAL'; end if;

  select status, posted_journal_id into _status, _posted_journal_id
  from public.onexa_business_documents
  where id = _document_id and tenant_id = _tenant_id;
  if _status <> 'posted' or _posted_journal_id is distinct from _journal_id then
    raise exception 'ONEXA_SMOKE_DOCUMENT_NOT_POSTED_CORRECTLY';
  end if;

  select quantity_on_hand, inventory_value into _quantity, _inventory_value
  from public.onexa_inventory_balances
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id
    and branch_id = _branch_id and warehouse_id = _warehouse_id
    and item_id = _item_id and valuation_currency = 'SAR';
  if _quantity <> 2 or _inventory_value <> 100 then
    raise exception 'ONEXA_SMOKE_STOCK_BALANCE_MISMATCH:quantity=%,value=%', _quantity, _inventory_value;
  end if;

  select count(*) into _movement_count
  from public.onexa_inventory_movements
  where tenant_id = _tenant_id and source_document_id = _document_id
    and movement_type = 'receipt' and quantity_delta = 2
    and unit_cost = 50 and value_delta = 100 and journal_id = _journal_id;
  if _movement_count <> 1 then
    raise exception 'ONEXA_SMOKE_EXPECTED_ONE_PURCHASE_RECEIPT:found %', _movement_count;
  end if;

  select count(*) into _run_count
  from public.onexa_purchase_posting_runs
  where document_id = _document_id and tenant_id = _tenant_id and journal_id = _journal_id
    and payable_amount = 345 and net_purchase_amount = 300 and tax_amount = 45
    and inventory_amount = 100 and expense_amount = 100 and asset_amount = 100;
  if _run_count <> 1 then raise exception 'ONEXA_SMOKE_PURCHASE_POSTING_RUN_MISMATCH'; end if;

  select reconciliation_status into _reconciliation_status
  from public.onexa_purchase_inventory_reconciliation
  where document_id = _document_id and tenant_id = _tenant_id;
  if _reconciliation_status <> 'reconciled' then
    raise exception 'ONEXA_SMOKE_PURCHASE_RECONCILIATION_FAILED:%', _reconciliation_status;
  end if;
end;
$smoke_test$;

rollback;

select
  'gate36_purchase_posting_smoke_test'::text as check_type,
  'passed'::text as status,
  'document, journal, stock receipt, posting run and all test data were rolled back'::text as details;
