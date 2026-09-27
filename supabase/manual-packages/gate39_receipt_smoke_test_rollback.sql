-- Gate 39 end-to-end customer receipt smoke test.
-- Requires:
--   * one posted ONEXA sales invoice with an outstanding balance;
--   * cash/bank and accounts-receivable role mappings;
--   * two distinct authorized sales users;
--   * an open current accounting period.
-- The test creates, submits, approves, and posts a temporary receipt.
-- No data persists because the entire test ends with ROLLBACK.

begin;

do $smoke$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _candidate uuid;
  _creator uuid;
  _operator uuid;
  _invoice public.onexa_business_documents%rowtype;
  _outstanding numeric(20,4);
  _amount numeric(20,4);
  _receipt_id uuid;
  _transition_result text;
  _journal uuid;
  _retry uuid;
  _allocated numeric(20,4);
begin
  if exists (
    select 1
    from public.onexa_customer_receipt_configuration_gaps gap
    where gap.tenant_id = _tenant
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
        'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
      )::text,
      true
    );

    if onexa_private.has_module_action(_candidate, 'sales', 'create')
       and onexa_private.has_module_action(_candidate, 'sales', 'submit') then
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
        'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
      )::text,
      true
    );

    if onexa_private.has_module_action(_candidate, 'sales', 'approve')
       and onexa_private.has_module_action(_candidate, 'sales', 'post') then
      _operator := _candidate;
      exit;
    end if;
  end loop;

  if _operator is null then
    raise exception 'ONEXA_SMOKE_DISTINCT_AUTHORIZED_RECEIPT_APPROVER_AND_POSTER_REQUIRED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _creator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
    )::text,
    true
  );

  select document.*, reconciliation.outstanding_amount
  into _invoice, _outstanding
  from public.onexa_customer_receivables_reconciliation reconciliation
  join public.onexa_business_documents document
    on document.id = reconciliation.invoice_id
   and document.tenant_id = reconciliation.tenant_id
  where reconciliation.tenant_id = _tenant
    and reconciliation.reconciliation_status = 'reconciled'
    and reconciliation.outstanding_amount > 0
    and document.status = 'posted'
    and document.posted_journal_id is not null
    and document.branch_id is not null
    and document.party_type = 'customer'
    and document.party_id is not null
  order by document.accounting_date, document.created_at, document.id
  limit 1;

  if _invoice.id is null then
    raise exception 'ONEXA_SMOKE_POSTED_SALES_INVOICE_WITH_BALANCE_REQUIRED';
  end if;

  _amount := least(_outstanding, 1.0000);

  _receipt_id := public.onexa_create_business_document(
    _legal_entity_id => _invoice.legal_entity_id,
    _branch_id => _invoice.branch_id,
    _module_key => 'sales',
    _document_type => 'customer_receipt',
    _document_date => current_date,
    _accounting_date => current_date,
    _due_date => null,
    _currency => _invoice.currency,
    _party_type => 'customer',
    _party_id => _invoice.party_id,
    _party_name_snapshot => _invoice.party_name_snapshot,
    _external_reference => 'G39-SMOKE-' || gen_random_uuid()::text,
    _origin => 'native',
    _import_batch_id => null,
    _subtotal => _amount,
    _discount_total => 0,
    _tax_total => 0,
    _gross_total => _amount,
    _dimensions => jsonb_build_object('smoke_test', true),
    _source_snapshot => jsonb_build_object(
      'invoice_allocations',
      jsonb_build_array(
        jsonb_build_object(
          'invoice_id', _invoice.id,
          'amount', _amount
        )
      ),
      'test_type', 'rollback_only',
      'posting_contract_version', 'customer-receipt-v1'
    ),
    _memo => 'Gate 39 rollback-only customer receipt smoke test',
    _lines => jsonb_build_array(
      jsonb_build_object(
        'line_number', 1,
        'description', 'Gate 39 temporary customer receipt',
        'quantity', 1,
        'unit_price', _amount,
        'discount_amount', 0,
        'net_amount', _amount,
        'tax_rate', 0,
        'tax_amount', 0,
        'gross_amount', _amount,
        'dimensions', jsonb_build_object('smoke_test', true)
      )
    )
  );

  if _receipt_id is null then
    raise exception 'ONEXA_SMOKE_RECEIPT_CREATION_FAILED';
  end if;

  _transition_result := public.onexa_transition_business_document(
    _receipt_id,
    'submitted',
    'Gate 39 rollback smoke submission'
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
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
    )::text,
    true
  );

  _transition_result := public.onexa_transition_business_document(
    _receipt_id,
    'approved',
    'Gate 39 rollback smoke approval'
  );

  if _transition_result <> 'approved' then
    raise exception 'ONEXA_SMOKE_RECEIPT_APPROVAL_FAILED';
  end if;

  _journal := public.onexa_post_customer_receipt(
    _receipt_id,
    to_char(current_date, 'YYYY-MM')
  );

  select sum(allocation.amount)
  into _allocated
  from public.onexa_customer_receipt_allocations allocation
  where allocation.receipt_id = _receipt_id
    and allocation.tenant_id = _tenant;

  if _journal is null
     or _allocated is distinct from _amount
     or not exists (
       select 1
       from public.onexa_customer_receipt_postings posting
       where posting.document_id = _receipt_id
         and posting.tenant_id = _tenant
         and posting.journal_id = _journal
         and posting.amount = _amount
     )
     or not exists (
       select 1
       from public.onexa_business_documents document
       where document.id = _receipt_id
         and document.tenant_id = _tenant
         and document.status = 'posted'
         and document.posted_journal_id = _journal
     )
     or not exists (
       select 1
       from public.onexa_customer_receivables_reconciliation reconciliation
       where reconciliation.invoice_id = _invoice.id
         and reconciliation.collected_amount >= _amount
         and reconciliation.outstanding_amount = _outstanding - _amount
         and reconciliation.reconciliation_status = 'reconciled'
     ) then
    raise exception 'ONEXA_SMOKE_RECEIPT_RECONCILIATION_FAILED';
  end if;

  _retry := public.onexa_post_customer_receipt(
    _receipt_id,
    to_char(current_date, 'YYYY-MM')
  );

  if _retry is distinct from _journal then
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
      to_char(current_date, 'YYYY-MM')
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
    'gate39_customer_receipt_smoke_test | passed | receipt=% | journal=% | rollback follows',
    _receipt_id,
    _journal;
end;
$smoke$;

rollback;

select
  'gate39_customer_receipt_smoke_test'::text as check_type,
  'passed'::text as status,
  'temporary receipt, allocation, journal, and audit data were rolled back'::text as details;
