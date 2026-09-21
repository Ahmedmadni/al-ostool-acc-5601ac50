-- ONEXA ERP — Gate 35 rollback-only sales posting smoke test
-- Creates a temporary stock balance and sales invoice, posts it, verifies every
-- accounting/inventory result, then rolls back the entire test transaction.
-- No business document, stock movement, journal, or audit row is retained.

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
  _customer_id uuid := gen_random_uuid();
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
    select 1
    from public.onexa_module_entitlements entitlement
    where entitlement.tenant_id = _tenant_id
      and entitlement.module_key = 'sales'
      and entitlement.is_enabled = true
  ) then
    raise exception 'ONEXA_SMOKE_SALES_MODULE_NOT_ENABLED';
  end if;

  select membership.user_id
  into _creator
  from public.onexa_workspace_memberships membership
  join auth.users auth_user on auth_user.id = membership.user_id
  where membership.tenant_id = _tenant_id
    and membership.status = 'active'
    and membership.role_key in ('accountant', 'finance_manager', 'workspace_owner')
  order by
    case membership.role_key
      when 'accountant' then 1
      when 'finance_manager' then 2
      else 3
    end,
    membership.user_id
  limit 1;

  if _creator is null then
    raise exception 'ONEXA_SMOKE_CREATOR_REQUIRED';
  end if;

  select membership.user_id
  into _poster
  from public.onexa_workspace_memberships membership
  join auth.users auth_user on auth_user.id = membership.user_id
  where membership.tenant_id = _tenant_id
    and membership.status = 'active'
    and membership.role_key in ('finance_manager', 'workspace_owner')
    and membership.user_id <> _creator
  order by
    case membership.role_key when 'finance_manager' then 1 else 2 end,
    membership.user_id
  limit 1;

  if _poster is null then
    raise exception 'ONEXA_SMOKE_DISTINCT_FINANCE_POSTER_REQUIRED';
  end if;

  select branch.id
  into _branch_id
  from public.onexa_branches branch
  where branch.tenant_id = _tenant_id
    and branch.legal_entity_id = _legal_entity_id
    and branch.is_active = true
  order by branch.id
  limit 1;

  if _branch_id is null then
    raise exception 'ONEXA_SMOKE_ACTIVE_BRANCH_REQUIRED';
  end if;

  if exists (
    select 1
    from public.onexa_sales_posting_configuration_gaps gap
    where gap.tenant_id = _tenant_id
      and gap.legal_entity_id = _legal_entity_id
  ) then
    raise exception 'ONEXA_SMOKE_ACCOUNT_MAPPING_GAPS_REMAIN';
  end if;

  insert into public.onexa_inventory_balances (
    tenant_id, legal_entity_id, branch_id, warehouse_id, item_id,
    valuation_currency, quantity_on_hand, inventory_value
  ) values (
    _tenant_id, _legal_entity_id, _branch_id, _warehouse_id, _item_id,
    'SAR', 10, 1000
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _creator::text,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant_id)
    )::text,
    true
  );

  if auth.uid() is distinct from _creator
     or onexa_private.claim_tenant_id() is distinct from _tenant_id then
    raise exception 'ONEXA_SMOKE_CREATOR_CONTEXT_FAILED';
  end if;

  select public.onexa_create_business_document(
    _legal_entity_id => _legal_entity_id,
    _branch_id => _branch_id,
    _module_key => 'sales',
    _document_type => 'sales_invoice',
    _document_date => current_date,
    _accounting_date => current_date,
    _due_date => current_date + 30,
    _currency => 'SAR',
    _party_type => 'customer',
    _party_id => _customer_id,
    _party_name_snapshot => 'عميل اختبار ترحيل ONEXA',
    _external_reference => 'ONEXA-G35-ROLLBACK-SMOKE',
    _origin => 'native',
    _import_batch_id => null,
    _subtotal => 100,
    _discount_total => 0,
    _tax_total => 15,
    _gross_total => 115,
    _dimensions => jsonb_build_object('smoke_test', true),
    _source_snapshot => jsonb_build_object(
      'test_type', 'rollback_only',
      'posting_contract_version', 'sales-v1'
    ),
    _memo => 'Gate 35 rollback-only posting smoke test',
    _lines => jsonb_build_array(
      jsonb_build_object(
        'line_number', 1,
        'description', 'صنف اختبار مؤقت',
        'quantity', 1,
        'unit_of_measure', 'EA',
        'unit_price', 100,
        'discount_amount', 0,
        'net_amount', 100,
        'tax_code', 'VAT15',
        'tax_rate', 15,
        'tax_amount', 15,
        'gross_amount', 115,
        'item_id', _item_id,
        'warehouse_id', _warehouse_id,
        'account_role', 'sales_revenue',
        'dimensions', jsonb_build_object('smoke_test', true)
      )
    )
  ) into _document_id;

  if _document_id is null then
    raise exception 'ONEXA_SMOKE_DOCUMENT_CREATION_FAILED';
  end if;

  select public.onexa_transition_business_document(
    _document_id,
    'submitted',
    'rollback smoke test submission'
  ) into _transition_result;

  if _transition_result <> 'submitted' then
    raise exception 'ONEXA_SMOKE_SUBMISSION_FAILED: %', _transition_result;
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _poster::text,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant_id)
    )::text,
    true
  );

  if auth.uid() is distinct from _poster
     or onexa_private.claim_tenant_id() is distinct from _tenant_id then
    raise exception 'ONEXA_SMOKE_POSTER_CONTEXT_FAILED';
  end if;

  select public.onexa_transition_business_document(
    _document_id,
    'approved',
    'rollback smoke test approval'
  ) into _transition_result;

  if _transition_result <> 'approved' then
    raise exception 'ONEXA_SMOKE_APPROVAL_FAILED: %', _transition_result;
  end if;

  select public.onexa_post_sales_invoice(
    _document_id,
    _period_code
  ) into _journal_id;

  if _journal_id is null then
    raise exception 'ONEXA_SMOKE_POSTING_DID_NOT_RETURN_JOURNAL';
  end if;

  select document.status, document.posted_journal_id
  into _status, _posted_journal_id
  from public.onexa_business_documents document
  where document.id = _document_id
    and document.tenant_id = _tenant_id;

  if _status <> 'posted' or _posted_journal_id is distinct from _journal_id then
    raise exception 'ONEXA_SMOKE_DOCUMENT_NOT_POSTED_CORRECTLY';
  end if;

  select balance.quantity_on_hand, balance.inventory_value
  into _quantity, _inventory_value
  from public.onexa_inventory_balances balance
  where balance.tenant_id = _tenant_id
    and balance.legal_entity_id = _legal_entity_id
    and balance.branch_id = _branch_id
    and balance.warehouse_id = _warehouse_id
    and balance.item_id = _item_id
    and balance.valuation_currency = 'SAR';

  if _quantity <> 9 or _inventory_value <> 900 then
    raise exception 'ONEXA_SMOKE_STOCK_BALANCE_MISMATCH: quantity=%, value=%',
      _quantity, _inventory_value;
  end if;

  select count(*) into _movement_count
  from public.onexa_inventory_movements movement
  where movement.tenant_id = _tenant_id
    and movement.source_document_id = _document_id
    and movement.movement_type = 'sale_issue'
    and movement.quantity_delta = -1
    and movement.unit_cost = 100
    and movement.value_delta = -100
    and movement.journal_id = _journal_id;

  if _movement_count <> 1 then
    raise exception 'ONEXA_SMOKE_EXPECTED_ONE_INVENTORY_MOVEMENT: found %', _movement_count;
  end if;

  select count(*) into _run_count
  from public.onexa_sales_posting_runs run
  where run.document_id = _document_id
    and run.tenant_id = _tenant_id
    and run.journal_id = _journal_id
    and run.receivable_amount = 115
    and run.revenue_amount = 100
    and run.tax_amount = 15
    and run.inventory_cost = 100;

  if _run_count <> 1 then
    raise exception 'ONEXA_SMOKE_SALES_POSTING_RUN_MISMATCH';
  end if;

  select reconciliation.reconciliation_status
  into _reconciliation_status
  from public.onexa_sales_inventory_reconciliation reconciliation
  where reconciliation.document_id = _document_id
    and reconciliation.tenant_id = _tenant_id;

  if _reconciliation_status <> 'reconciled' then
    raise exception 'ONEXA_SMOKE_RECONCILIATION_FAILED: %', _reconciliation_status;
  end if;
end;
$smoke_test$;

rollback;

select
  'gate35_sales_posting_smoke_test'::text as check_type,
  'passed'::text as status,
  'document, journal, inventory movement, posting run, and all test data were rolled back'::text as details;
