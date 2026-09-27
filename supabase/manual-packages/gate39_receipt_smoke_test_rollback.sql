-- Gate 39 full-pipeline rollback smoke test.
-- Creates and posts a temporary ONEXA sales invoice, then creates, approves,
-- and posts its temporary customer receipt. No production invoice is required.
-- Requires Gate 35 and Gate 39 account mappings, two distinct authorized sales
-- users, an active branch, and an open current accounting period.
-- All temporary data is removed by the final ROLLBACK.

begin;

do $smoke$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _legal_entity constant uuid := '3ba2a953-db1d-4c1f-a192-c7343a93ab36';
  _candidate uuid;
  _creator uuid;
  _operator uuid;
  _branch uuid;
  _warehouse uuid := gen_random_uuid();
  _item uuid := gen_random_uuid();
  _customer uuid := gen_random_uuid();
  _invoice_id uuid;
  _invoice_journal uuid;
  _receipt_id uuid;
  _receipt_journal uuid;
  _retry uuid;
  _transition_result text;
  _allocated numeric(20,4);
  _outstanding numeric(20,4);
  _period_code text := to_char(current_date, 'YYYY-MM');
begin
  if not exists (
    select 1
    from public.onexa_module_entitlements entitlement
    where entitlement.tenant_id = _tenant
      and entitlement.module_key = 'sales'
      and entitlement.is_enabled is true
  ) then
    raise exception 'ONEXA_SMOKE_SALES_MODULE_NOT_ENABLED';
  end if;

  select branch.id
  into _branch
  from public.onexa_branches branch
  where branch.tenant_id = _tenant
    and branch.legal_entity_id = _legal_entity
    and branch.is_active is true
  order by branch.id
  limit 1;

  if _branch is null then
    raise exception 'ONEXA_SMOKE_ACTIVE_BRANCH_REQUIRED';
  end if;

  if exists (
    select 1
    from public.onexa_sales_posting_configuration_gaps gap
    where gap.tenant_id = _tenant
      and gap.legal_entity_id = _legal_entity
  ) then
    raise exception 'ONEXA_SMOKE_SALES_ACCOUNT_MAPPING_GAPS_REMAIN';
  end if;

  if exists (
    select 1
    from public.onexa_customer_receipt_configuration_gaps gap
    where gap.tenant_id = _tenant
      and gap.legal_entity_id = _legal_entity
  ) then
    raise exception 'ONEXA_SMOKE_RECEIPT_ACCOUNT_MAPPING_GAPS_REMAIN';
  end if;

  for _candidate in
    select membership.user_id
    from public.onexa_workspace_memberships membership
    join auth.users auth_user
      on auth_user.id = membership.user_id
    where membership.tenant_id = _tenant
      and membership.status = 'active'
      and membership.role_key in (
        'workspace_owner',
        'finance_manager',
        'accountant'
      )
    group by membership.user_id
    order by
      min(
        case membership.role_key
          when 'accountant' then 1
          when 'finance_manager' then 2
          else 3
        end
      ),
      membership.user_id
  loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', _candidate,
        'role', 'authenticated',
        'app_metadata', jsonb_build_object(
          'onexa_tenant_id',
          _tenant
        )
      )::text,
      true
    );

    if onexa_private.has_module_action(
         _candidate,
         'sales',
         'create'
       )
       and onexa_private.has_module_action(
         _candidate,
         'sales',
         'submit'
       ) then
      _creator := _candidate;
      exit;
    end if;
  end loop;

  if _creator is null then
    raise exception 'ONEXA_SMOKE_AUTHORIZED_RECEIPT_CREATOR_REQUIRED';
  end if;

  for _candidate in
    select membership.user_id
    from public.onexa_workspace_memberships membership
    join auth.users auth_user
      on auth_user.id = membership.user_id
    where membership.tenant_id = _tenant
      and membership.status = 'active'
      and membership.role_key in (
        'workspace_owner',
        'finance_manager',
        'accountant'
      )
      and membership.user_id <> _creator
    group by membership.user_id
    order by
      min(
        case membership.role_key
          when 'finance_manager' then 1
          when 'workspace_owner' then 2
          else 3
        end
      ),
      membership.user_id
  loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', _candidate,
        'role', 'authenticated',
        'app_metadata', jsonb_build_object(
          'onexa_tenant_id',
          _tenant
        )
      )::text,
      true
    );

    if onexa_private.has_module_action(
         _candidate,
         'sales',
         'approve'
       )
       and onexa_private.has_module_action(
         _candidate,
         'sales',
         'post'
       ) then
      _operator := _candidate;
      exit;
    end if;
  end loop;

  if _operator is null then
    raise exception
      'ONEXA_SMOKE_DISTINCT_AUTHORIZED_RECEIPT_APPROVER_AND_POSTER_REQUIRED';
  end if;

  insert into public.onexa_inventory_balances (
    tenant_id,
    legal_entity_id,
    branch_id,
    warehouse_id,
    item_id,
    valuation_currency,
    quantity_on_hand,
    inventory_value
  )
  values (
    _tenant,
    _legal_entity,
    _branch,
    _warehouse,
    _item,
    'SAR',
    10,
    1000
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _creator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object(
        'onexa_tenant_id',
        _tenant
      )
    )::text,
    true
  );

  _invoice_id := public.onexa_create_business_document(
    _legal_entity_id => _legal_entity,
    _branch_id => _branch,
    _module_key => 'sales',
    _document_type => 'sales_invoice',
    _document_date => current_date,
    _accounting_date => current_date,
    _due_date => current_date + 30,
    _currency => 'SAR',
    _party_type => 'customer',
    _party_id => _customer,
    _party_name_snapshot => 'Gate 39 rollback customer',
    _external_reference =>
      'G39-INVOICE-SMOKE-' || gen_random_uuid()::text,
    _origin => 'native',
    _import_batch_id => null,
    _subtotal => 100,
    _discount_total => 0,
    _tax_total => 15,
    _gross_total => 115,
    _dimensions => jsonb_build_object(
      'smoke_test',
      true
    ),
    _source_snapshot => jsonb_build_object(
      'test_type',
      'rollback_only',
      'posting_contract_version',
      'sales-v1'
    ),
    _memo => 'Gate 39 temporary sales invoice',
    _lines => jsonb_build_array(
      jsonb_build_object(
        'line_number',
        1,
        'description',
        'Gate 39 temporary inventory item',
        'quantity',
        1,
        'unit_of_measure',
        'EA',
        'unit_price',
        100,
        'discount_amount',
        0,
        'net_amount',
        100,
        'tax_code',
        'VAT15',
        'tax_rate',
        0.15,
        'tax_amount',
        15,
        'gross_amount',
        115,
        'item_id',
        _item,
        'warehouse_id',
        _warehouse,
        'account_role',
        'sales_revenue',
        'dimensions',
        jsonb_build_object(
          'smoke_test',
          true
        )
      )
    )
  );

  if _invoice_id is null then
    raise exception 'ONEXA_SMOKE_SALES_INVOICE_CREATION_FAILED';
  end if;

  _transition_result :=
    public.onexa_transition_business_document(
      _invoice_id,
      'submitted',
      'Gate 39 temporary sales invoice submission'
    );

  if _transition_result <> 'submitted' then
    raise exception 'ONEXA_SMOKE_SALES_INVOICE_SUBMISSION_FAILED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _operator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object(
        'onexa_tenant_id',
        _tenant
      )
    )::text,
    true
  );

  _transition_result :=
    public.onexa_transition_business_document(
      _invoice_id,
      'approved',
      'Gate 39 temporary sales invoice approval'
    );

  if _transition_result <> 'approved' then
    raise exception 'ONEXA_SMOKE_SALES_INVOICE_APPROVAL_FAILED';
  end if;

  _invoice_journal := public.onexa_post_sales_invoice(
    _invoice_id,
    _period_code
  );

  if _invoice_journal is null
     or not exists (
       select 1
       from public.onexa_sales_posting_runs posting
       where posting.document_id = _invoice_id
         and posting.tenant_id = _tenant
         and posting.journal_id = _invoice_journal
     )
     or not exists (
       select 1
       from public.onexa_business_documents document
       where document.id = _invoice_id
         and document.tenant_id = _tenant
         and document.status = 'posted'
         and document.posted_journal_id = _invoice_journal
     ) then
    raise exception 'ONEXA_SMOKE_SALES_INVOICE_POSTING_FAILED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _creator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object(
        'onexa_tenant_id',
        _tenant
      )
    )::text,
    true
  );

  select reconciliation.outstanding_amount
  into _outstanding
  from public.onexa_customer_receivables_reconciliation reconciliation
  where reconciliation.tenant_id = _tenant
    and reconciliation.invoice_id = _invoice_id
    and reconciliation.reconciliation_status = 'reconciled';

  if _outstanding is distinct from 115.0000 then
    raise exception 'ONEXA_SMOKE_SALES_RECEIVABLE_NOT_READY';
  end if;

  _receipt_id := public.onexa_create_business_document(
    _legal_entity_id => _legal_entity,
    _branch_id => _branch,
    _module_key => 'sales',
    _document_type => 'customer_receipt',
    _document_date => current_date,
    _accounting_date => current_date,
    _due_date => null,
    _currency => 'SAR',
    _party_type => 'customer',
    _party_id => _customer,
    _party_name_snapshot => 'Gate 39 rollback customer',
    _external_reference =>
      'G39-RECEIPT-SMOKE-' || gen_random_uuid()::text,
    _origin => 'native',
    _import_batch_id => null,
    _subtotal => 115,
    _discount_total => 0,
    _tax_total => 0,
    _gross_total => 115,
    _dimensions => jsonb_build_object(
      'smoke_test',
      true
    ),
    _source_snapshot => jsonb_build_object(
      'invoice_allocations',
      jsonb_build_array(
        jsonb_build_object(
          'invoice_id',
          _invoice_id,
          'amount',
          115
        )
      ),
      'test_type',
      'rollback_only',
      'posting_contract_version',
      'customer-receipt-v1'
    ),
    _memo => 'Gate 39 rollback-only customer receipt',
    _lines => jsonb_build_array(
      jsonb_build_object(
        'line_number',
        1,
        'description',
        'Gate 39 temporary customer receipt',
        'quantity',
        1,
        'unit_price',
        115,
        'discount_amount',
        0,
        'net_amount',
        115,
        'tax_rate',
        0,
        'tax_amount',
        0,
        'gross_amount',
        115,
        'dimensions',
        jsonb_build_object(
          'smoke_test',
          true
        )
      )
    )
  );

  if _receipt_id is null then
    raise exception 'ONEXA_SMOKE_RECEIPT_CREATION_FAILED';
  end if;

  _transition_result :=
    public.onexa_transition_business_document(
      _receipt_id,
      'submitted',
      'Gate 39 rollback receipt submission'
    );

  if _transition_result <> 'submitted' then
    raise exception 'ONEXA_SMOKE_RECEIPT_SUBMISSION_FAILED';
  end if;

  begin
    perform public.onexa_transition_business_document(
      _receipt_id,
      'approved',
      'Gate 39 creator approval must fail'
    );

    raise exception 'ONEXA_SMOKE_RECEIPT_CREATOR_APPROVAL_ALLOWED';
  exception
    when others then
      if sqlerrm <> 'ONEXA_SEGREGATION_OF_DUTIES_REQUIRED' then
        raise;
      end if;
  end;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _operator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object(
        'onexa_tenant_id',
        _tenant
      )
    )::text,
    true
  );

  _transition_result :=
    public.onexa_transition_business_document(
      _receipt_id,
      'approved',
      'Gate 39 rollback receipt approval'
    );

  if _transition_result <> 'approved' then
    raise exception 'ONEXA_SMOKE_RECEIPT_APPROVAL_FAILED';
  end if;

  _receipt_journal := public.onexa_post_customer_receipt(
    _receipt_id,
    _period_code
  );

  select sum(allocation.amount)
  into _allocated
  from public.onexa_customer_receipt_allocations allocation
  where allocation.receipt_id = _receipt_id
    and allocation.tenant_id = _tenant;

  if _receipt_journal is null
     or _allocated is distinct from 115.0000
     or not exists (
       select 1
       from public.onexa_customer_receipt_postings posting
       where posting.document_id = _receipt_id
         and posting.tenant_id = _tenant
         and posting.journal_id = _receipt_journal
         and posting.amount = 115.0000
     )
     or not exists (
       select 1
       from public.onexa_business_documents document
       where document.id = _receipt_id
         and document.tenant_id = _tenant
         and document.status = 'posted'
         and document.posted_journal_id = _receipt_journal
     )
     or not exists (
       select 1
       from public.onexa_customer_receivables_reconciliation reconciliation
       where reconciliation.invoice_id = _invoice_id
         and reconciliation.collected_amount = 115.0000
         and reconciliation.outstanding_amount = 0
         and reconciliation.reconciliation_status = 'reconciled'
     ) then
    raise exception 'ONEXA_SMOKE_RECEIPT_RECONCILIATION_FAILED';
  end if;

  _retry := public.onexa_post_customer_receipt(
    _receipt_id,
    _period_code
  );

  if _retry is distinct from _receipt_journal then
    raise exception 'ONEXA_SMOKE_RECEIPT_RETRY_FAILED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _operator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object(
        'onexa_tenant_id',
        'tenant-smoke-other'
      )
    )::text,
    true
  );

  begin
    perform public.onexa_post_customer_receipt(
      _receipt_id,
      _period_code
    );

    raise exception 'ONEXA_SMOKE_CROSS_TENANT_ALLOWED';
  exception
    when others then
      if sqlerrm not in (
        'ONEXA_RECEIPT_POST_NOT_AUTHORIZED',
        'ONEXA_DOCUMENT_NOT_FOUND'
      ) then
        raise;
      end if;
  end;

  raise notice
    'gate39_customer_receipt_smoke_test | passed | invoice=% | invoice_journal=% | receipt=% | receipt_journal=% | rollback follows',
    _invoice_id,
    _invoice_journal,
    _receipt_id,
    _receipt_journal;
end;
$smoke$;

rollback;

select
  'gate39_customer_receipt_smoke_test'::text as check_type,
  'passed'::text as status,
  'temporary invoice, inventory, receipt, journals, allocations, and audit data were rolled back'::text as details;
