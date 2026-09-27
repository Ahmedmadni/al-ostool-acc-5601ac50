-- ONEXA Gate 36: purchase invoice -> inventory/expense/asset -> AP -> input VAT -> GL.
-- Manual review package. Keep the runtime flag disabled until the postcheck,
-- account mapping and rollback-only smoke test all pass.

begin;

do $$
begin
  if to_regprocedure(
    'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'
  ) is null then
    raise exception 'ONEXA_B4_POST_JOURNAL_SIGNATURE_REQUIRED';
  end if;
  if to_regclass('public.onexa_business_documents') is null
     or to_regclass('public.onexa_business_document_lines') is null
     or to_regclass('public.onexa_business_document_events') is null
     or to_regclass('public.onexa_legal_entities') is null then
    raise exception 'ONEXA_BUSINESS_DOCUMENT_FOUNDATION_REQUIRED';
  end if;
  if to_regclass('public.onexa_inventory_balances') is null
     or to_regclass('public.onexa_inventory_movements') is null then
    raise exception 'ONEXA_GATE35_INVENTORY_FOUNDATION_REQUIRED';
  end if;
  if to_regclass('public.onexa_account_role_mappings') is null
     or to_regclass('public.chart_of_accounts') is null then
    raise exception 'ONEXA_ACCOUNT_ROLE_MAPPINGS_REQUIRED';
  end if;
  if to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_B3_MODULE_AUTHORIZATION_REQUIRED';
  end if;
end;
$$;

create table if not exists public.onexa_purchase_posting_runs (
  document_id uuid primary key references public.onexa_business_documents(id),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision > 0),
  payable_amount numeric(20, 4) not null check (payable_amount >= 0),
  net_purchase_amount numeric(20, 4) not null check (net_purchase_amount >= 0),
  tax_amount numeric(20, 4) not null check (tax_amount >= 0),
  inventory_amount numeric(20, 4) not null check (inventory_amount >= 0),
  expense_amount numeric(20, 4) not null check (expense_amount >= 0),
  asset_amount numeric(20, 4) not null check (asset_amount >= 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  constraint onexa_purchase_posting_runs_invoice_math check (
    abs(payable_amount - (net_purchase_amount + tax_amount)) <= 0.01
    and abs(net_purchase_amount - (inventory_amount + expense_amount + asset_amount)) <= 0.01
  )
);

create index if not exists onexa_purchase_posting_runs_journal_idx
  on public.onexa_purchase_posting_runs (tenant_id, legal_entity_id, journal_id);

alter table public.onexa_purchase_posting_runs enable row level security;

drop policy if exists onexa_purchase_posting_runs_select_tenant on public.onexa_purchase_posting_runs;
create policy onexa_purchase_posting_runs_select_tenant
  on public.onexa_purchase_posting_runs for select
  to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'procurement', 'read')
  );

create or replace view public.onexa_purchase_inventory_reconciliation
with (security_invoker = true)
as
with movement_totals as (
  select
    tenant_id,
    source_document_id,
    count(*) as movement_count,
    sum(quantity_delta) as received_quantity,
    sum(value_delta) as received_inventory_value
  from public.onexa_inventory_movements
  where movement_type = 'receipt'
  group by tenant_id, source_document_id
), expected_lines as (
  select
    tenant_id,
    document_id,
    count(*) filter (where item_id is not null) as expected_movement_count,
    coalesce(sum(net_amount) filter (where account_role = 'inventory'), 0) as classified_inventory_amount,
    coalesce(sum(net_amount) filter (where account_role = 'purchase_expense'), 0) as classified_expense_amount,
    coalesce(sum(net_amount) filter (where account_role = 'fixed_asset_cost'), 0) as classified_asset_amount
  from public.onexa_business_document_lines
  group by tenant_id, document_id
)
select
  document.id as document_id,
  document.tenant_id,
  document.legal_entity_id,
  document.branch_id,
  document.document_number,
  document.document_date,
  document.due_date,
  document.currency,
  document.status,
  document.gross_total as payable_amount,
  document.subtotal - document.discount_total as net_purchase_amount,
  document.tax_total as tax_amount,
  coalesce(run.inventory_amount, 0) as posted_inventory_amount,
  coalesce(movement.received_inventory_value, 0) as movement_inventory_amount,
  coalesce(run.expense_amount, 0) as expense_amount,
  coalesce(run.asset_amount, 0) as asset_amount,
  coalesce(expected.expected_movement_count, 0) as expected_movement_count,
  coalesce(movement.movement_count, 0) as actual_movement_count,
  document.posted_journal_id,
  case
    when document.status <> 'posted' then 'not_posted'
    when document.posted_journal_id is null or run.journal_id is null then 'journal_missing'
    when abs(document.gross_total - ((document.subtotal - document.discount_total) + document.tax_total)) > 0.01 then 'invoice_unbalanced'
    when coalesce(expected.expected_movement_count, 0) <> coalesce(movement.movement_count, 0) then 'stock_movement_missing'
    when abs(coalesce(run.inventory_amount, 0) - coalesce(movement.received_inventory_value, 0)) > 0.01 then 'inventory_value_mismatch'
    when abs(coalesce(run.inventory_amount, 0) - coalesce(expected.classified_inventory_amount, 0)) > 0.01
      or abs(coalesce(run.expense_amount, 0) - coalesce(expected.classified_expense_amount, 0)) > 0.01
      or abs(coalesce(run.asset_amount, 0) - coalesce(expected.classified_asset_amount, 0)) > 0.01 then 'classification_mismatch'
    else 'reconciled'
  end as reconciliation_status
from public.onexa_business_documents document
left join public.onexa_purchase_posting_runs run
  on run.document_id = document.id and run.tenant_id = document.tenant_id
left join movement_totals movement
  on movement.source_document_id = document.id and movement.tenant_id = document.tenant_id
left join expected_lines expected
  on expected.document_id = document.id and expected.tenant_id = document.tenant_id
where document.document_type = 'purchase_invoice';

create or replace view public.onexa_purchase_posting_configuration_gaps
with (security_invoker = true)
as
with required_roles(account_role) as (
  values
    ('accounts_payable'::text),
    ('input_vat'::text),
    ('inventory'::text),
    ('purchase_expense'::text),
    ('fixed_asset_cost'::text)
)
select
  entity.tenant_id,
  entity.id as legal_entity_id,
  entity.code as legal_entity_code,
  required.account_role
from public.onexa_legal_entities entity
cross join required_roles required
left join public.onexa_account_role_mappings mapping
  on mapping.tenant_id = entity.tenant_id
 and mapping.legal_entity_id = entity.id
 and mapping.account_role = required.account_role
 and mapping.is_active = true
where entity.is_active = true and mapping.id is null;

create or replace function public.onexa_post_purchase_invoice(
  _document_id uuid,
  _period_code text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
  _line public.onexa_business_document_lines%rowtype;
  _accounts_payable text;
  _input_vat text;
  _inventory text;
  _purchase_expense text;
  _fixed_asset_cost text;
  _line_account text;
  _net_purchase_amount numeric(20, 4);
  _inventory_amount numeric(20, 4) := 0;
  _expense_amount numeric(20, 4) := 0;
  _asset_amount numeric(20, 4) := 0;
  _journal_lines jsonb := '[]'::jsonb;
  _dimensions jsonb;
  _line_dimensions jsonb;
  _journal_id uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'procurement', 'post') then
    raise exception 'ONEXA_PROCUREMENT_POST_NOT_AUTHORIZED';
  end if;
  if coalesce(btrim(_period_code), '')
       !~ '^[0-9]{4}-(0[1-9]|1[0-2])

  perform pg_advisory_xact_lock(hashtextextended(_tenant_id || ':procurement:' || _document_id::text, 0));

  select * into _document
  from public.onexa_business_documents
  where id = _document_id and tenant_id = _tenant_id
  for update;

  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _document.status = 'posted' and _document.posted_journal_id is not null then
    select run.journal_id
    into _journal_id
    from public.onexa_purchase_posting_runs as run
    where run.document_id = _document.id
      and run.tenant_id = _tenant_id;

    if _journal_id is distinct from _document.posted_journal_id then
      raise exception 'ONEXA_PURCHASE_RETRY_JOURNAL_MISMATCH';
    end if;

    return _journal_id;
  end if;
  if _document.document_type <> 'purchase_invoice' or _document.module_key <> 'procurement' then
    raise exception 'ONEXA_PURCHASE_INVOICE_REQUIRED';
  end if;
  if _document.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.branch_id is null then raise exception 'ONEXA_BRANCH_REQUIRED'; end if;
  if _document.party_type <> 'vendor' or _document.party_id is null then raise exception 'ONEXA_VENDOR_REQUIRED'; end if;
  if _actor = _document.created_by then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;

  perform 1 from public.onexa_business_document_lines where document_id = _document.id;
  if not found then raise exception 'ONEXA_DOCUMENT_LINES_REQUIRED'; end if;

  perform 1
  from public.onexa_business_document_lines
  where document_id = _document.id
    and (
      account_role not in ('inventory', 'purchase_expense', 'fixed_asset_cost')
      or (item_id is not null and (warehouse_id is null or account_role <> 'inventory'))
      or (item_id is null and warehouse_id is not null)
      or (item_id is null and account_role = 'inventory')
      or (account_role = 'inventory' and quantity <= 0)
    );
  if found then raise exception 'ONEXA_PURCHASE_LINE_CLASSIFICATION_INVALID'; end if;

  perform 1
  from (
    select
      coalesce(sum(net_amount), 0) as line_net,
      coalesce(sum(tax_amount), 0) as line_tax,
      coalesce(sum(gross_amount), 0) as line_gross
    from public.onexa_business_document_lines
    where document_id = _document.id
  ) totals
  where abs(totals.line_net - (_document.subtotal - _document.discount_total)) <= 0.01
    and abs(totals.line_tax - _document.tax_total) <= 0.01
    and abs(totals.line_gross - _document.gross_total) <= 0.01;
  if not found then raise exception 'ONEXA_PURCHASE_INVOICE_LINE_TOTALS_MISMATCH'; end if;

  select account_code into _accounts_payable
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'accounts_payable' and is_active = true;
  select account_code into _input_vat
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'input_vat' and is_active = true;
  select account_code into _inventory
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'inventory' and is_active = true;
  select account_code into _purchase_expense
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'purchase_expense' and is_active = true;
  select account_code into _fixed_asset_cost
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'fixed_asset_cost' and is_active = true;

  if _accounts_payable is null then raise exception 'ONEXA_ACCOUNTS_PAYABLE_MAPPING_REQUIRED'; end if;
  if _document.tax_total > 0 and _input_vat is null then raise exception 'ONEXA_INPUT_VAT_MAPPING_REQUIRED'; end if;

  _net_purchase_amount := _document.subtotal - _document.discount_total;
  _dimensions := coalesce(_document.dimensions, '{}'::jsonb) || jsonb_build_object(
    'legalEntity', _document.legal_entity_id,
    'branch', _document.branch_id,
    'vendor', _document.party_id
  );

  for _line in
    select *
    from public.onexa_business_document_lines
    where document_id = _document.id
    order by warehouse_id nulls last, item_id nulls last, line_number
  loop
    _line_account := case _line.account_role
      when 'inventory' then _inventory
      when 'purchase_expense' then _purchase_expense
      when 'fixed_asset_cost' then _fixed_asset_cost
      else null
    end;
    if _line_account is null then
      raise exception 'ONEXA_PURCHASE_ACCOUNT_MAPPING_REQUIRED:%', _line.account_role;
    end if;

    _line_dimensions := _dimensions || coalesce(_line.dimensions, '{}'::jsonb);

    if _line.account_role = 'inventory' then
      insert into public.onexa_inventory_balances (
        tenant_id, legal_entity_id, branch_id, warehouse_id, item_id,
        valuation_currency, quantity_on_hand, inventory_value
      ) values (
        _tenant_id, _document.legal_entity_id, _document.branch_id,
        _line.warehouse_id, _line.item_id, _document.currency, 0, 0
      ) on conflict do nothing;

      perform 1
      from public.onexa_inventory_balances
      where tenant_id = _tenant_id
        and legal_entity_id = _document.legal_entity_id
        and branch_id = _document.branch_id
        and warehouse_id = _line.warehouse_id
        and item_id = _line.item_id
        and valuation_currency = _document.currency
      for update;

      update public.onexa_inventory_balances
      set quantity_on_hand = quantity_on_hand + _line.quantity,
          inventory_value = inventory_value + _line.net_amount,
          updated_at = now()
      where tenant_id = _tenant_id
        and legal_entity_id = _document.legal_entity_id
        and branch_id = _document.branch_id
        and warehouse_id = _line.warehouse_id
        and item_id = _line.item_id
        and valuation_currency = _document.currency;

      insert into public.onexa_inventory_movements (
        tenant_id, legal_entity_id, branch_id, warehouse_id, item_id,
        valuation_currency, movement_type, quantity_delta, unit_cost, value_delta,
        source_document_id, source_document_line_id, source_revision, created_by
      ) values (
        _tenant_id, _document.legal_entity_id, _document.branch_id,
        _line.warehouse_id, _line.item_id, _document.currency, 'receipt',
        _line.quantity, round(_line.net_amount / _line.quantity, 6), _line.net_amount,
        _document.id, _line.id, _document.revision, _actor
      );

      _inventory_amount := _inventory_amount + _line.net_amount;
      _line_dimensions := _line_dimensions || jsonb_build_object('warehouse', _line.warehouse_id, 'item', _line.item_id);
    elsif _line.account_role = 'purchase_expense' then
      _expense_amount := _expense_amount + _line.net_amount;
    else
      _asset_amount := _asset_amount + _line.net_amount;
    end if;

    _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
      'account_code', _line_account,
      'debit', _line.net_amount,
      'credit', 0,
      'description', 'Purchase ' || _line.account_role || ' - ' || _document.document_number || ' - line ' || _line.line_number,
      'dimensions', _line_dimensions
    ));
  end loop;

  if _document.tax_total > 0 then
    _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
      'account_code', _input_vat,
      'debit', _document.tax_total,
      'credit', 0,
      'description', 'Input VAT - ' || _document.document_number,
      'dimensions', _dimensions
    ));
  end if;

  _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
    'account_code', _accounts_payable,
    'debit', 0,
    'credit', _document.gross_total,
    'description', 'Accounts payable - ' || _document.document_number,
    'dimensions', _dimensions
  ));

  select public.onexa_post_journal(
    _legal_entity_id => _document.legal_entity_id,
    _source_document_type => _document.document_type,
    _source_document_id => _document.id::text,
    _source_revision => _document.revision,
    _source_status => 'approved',
    _source_snapshot => coalesce(_document.source_snapshot, '{}'::jsonb) || jsonb_build_object(
      'document_number', _document.document_number,
      'inventory_amount', _inventory_amount,
      'expense_amount', _expense_amount,
      'asset_amount', _asset_amount,
      'posting_contract_version', 'procurement-v1'
    ),
    _accounting_date => _document.accounting_date,
    _period_code => btrim(_period_code),
    _currency => _document.currency,
    _memo => coalesce(_document.memo, 'Purchase invoice ' || _document.document_number),
    _lines => _journal_lines
  )::uuid into _journal_id;

  if _journal_id is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  update public.onexa_inventory_movements
  set journal_id = _journal_id
  where tenant_id = _tenant_id and source_document_id = _document.id
    and source_revision = _document.revision and movement_type = 'receipt';

  insert into public.onexa_purchase_posting_runs (
    document_id, tenant_id, legal_entity_id, journal_id, source_revision,
    payable_amount, net_purchase_amount, tax_amount, inventory_amount,
    expense_amount, asset_amount, posted_by
  ) values (
    _document.id, _tenant_id, _document.legal_entity_id, _journal_id, _document.revision,
    _document.gross_total, _net_purchase_amount, _document.tax_total, _inventory_amount,
    _expense_amount, _asset_amount, _actor
  );

  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', 'posted_from_purchase_invoice', true);

  update public.onexa_business_documents
  set status = 'posted', posted_by = _actor, posted_at = now(),
      posted_journal_id = _journal_id, posting_error = null
  where id = _document.id and tenant_id = _tenant_id and status = 'approved';

  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;

  insert into public.onexa_business_document_events (
    tenant_id, document_id, event_type, from_status, to_status,
    actor_id, event_data
  ) values (
    _tenant_id, _document.id, 'posting_completed', 'approved', 'posted',
    _actor, jsonb_build_object(
      'journal_id', _journal_id,
      'inventory_amount', _inventory_amount,
      'expense_amount', _expense_amount,
      'asset_amount', _asset_amount,
      'posting_contract_version', 'procurement-v1'
    )
  );

  return _journal_id;
end;
$$;

revoke all on table public.onexa_purchase_posting_runs from anon, authenticated;
grant select on table public.onexa_purchase_posting_runs to authenticated;
grant select on table public.onexa_purchase_inventory_reconciliation to authenticated;
grant select on table public.onexa_purchase_posting_configuration_gaps to authenticated;

revoke all on function public.onexa_post_purchase_invoice(uuid, text) from public, anon;
grant execute on function public.onexa_post_purchase_invoice(uuid, text) to authenticated;

commit;
 then
    raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(_tenant_id || ':procurement:' || _document_id::text, 0));

  select * into _document
  from public.onexa_business_documents
  where id = _document_id and tenant_id = _tenant_id
  for update;

  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _document.status = 'posted' and _document.posted_journal_id is not null then
    return _document.posted_journal_id;
  end if;
  if _document.document_type <> 'purchase_invoice' or _document.module_key <> 'procurement' then
    raise exception 'ONEXA_PURCHASE_INVOICE_REQUIRED';
  end if;
  if _document.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.branch_id is null then raise exception 'ONEXA_BRANCH_REQUIRED'; end if;
  if _document.party_type <> 'vendor' or _document.party_id is null then raise exception 'ONEXA_VENDOR_REQUIRED'; end if;
  if _actor = _document.created_by then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;

  perform 1 from public.onexa_business_document_lines where document_id = _document.id;
  if not found then raise exception 'ONEXA_DOCUMENT_LINES_REQUIRED'; end if;

  perform 1
  from public.onexa_business_document_lines
  where document_id = _document.id
    and (
      account_role not in ('inventory', 'purchase_expense', 'fixed_asset_cost')
      or (item_id is not null and (warehouse_id is null or account_role <> 'inventory'))
      or (item_id is null and warehouse_id is not null)
      or (item_id is null and account_role = 'inventory')
    );
  if found then raise exception 'ONEXA_PURCHASE_LINE_CLASSIFICATION_INVALID'; end if;

  perform 1
  from (
    select
      coalesce(sum(net_amount), 0) as line_net,
      coalesce(sum(tax_amount), 0) as line_tax,
      coalesce(sum(gross_amount), 0) as line_gross
    from public.onexa_business_document_lines
    where document_id = _document.id
  ) totals
  where abs(totals.line_net - (_document.subtotal - _document.discount_total)) <= 0.01
    and abs(totals.line_tax - _document.tax_total) <= 0.01
    and abs(totals.line_gross - _document.gross_total) <= 0.01;
  if not found then raise exception 'ONEXA_PURCHASE_INVOICE_LINE_TOTALS_MISMATCH'; end if;

  select account_code into _accounts_payable
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'accounts_payable' and is_active = true;
  select account_code into _input_vat
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'input_vat' and is_active = true;
  select account_code into _inventory
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'inventory' and is_active = true;
  select account_code into _purchase_expense
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'purchase_expense' and is_active = true;
  select account_code into _fixed_asset_cost
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'fixed_asset_cost' and is_active = true;

  if _accounts_payable is null then raise exception 'ONEXA_ACCOUNTS_PAYABLE_MAPPING_REQUIRED'; end if;
  if _document.tax_total > 0 and _input_vat is null then raise exception 'ONEXA_INPUT_VAT_MAPPING_REQUIRED'; end if;

  _net_purchase_amount := _document.subtotal - _document.discount_total;
  _dimensions := coalesce(_document.dimensions, '{}'::jsonb) || jsonb_build_object(
    'legalEntity', _document.legal_entity_id,
    'branch', _document.branch_id,
    'vendor', _document.party_id
  );

  for _line in
    select *
    from public.onexa_business_document_lines
    where document_id = _document.id
    order by warehouse_id nulls last, item_id nulls last, line_number
  loop
    _line_account := case _line.account_role
      when 'inventory' then _inventory
      when 'purchase_expense' then _purchase_expense
      when 'fixed_asset_cost' then _fixed_asset_cost
      else null
    end;
    if _line_account is null then
      raise exception 'ONEXA_PURCHASE_ACCOUNT_MAPPING_REQUIRED:%', _line.account_role;
    end if;

    _line_dimensions := _dimensions || coalesce(_line.dimensions, '{}'::jsonb);

    if _line.account_role = 'inventory' then
      insert into public.onexa_inventory_balances (
        tenant_id, legal_entity_id, branch_id, warehouse_id, item_id,
        valuation_currency, quantity_on_hand, inventory_value
      ) values (
        _tenant_id, _document.legal_entity_id, _document.branch_id,
        _line.warehouse_id, _line.item_id, _document.currency, 0, 0
      ) on conflict do nothing;

      perform 1
      from public.onexa_inventory_balances
      where tenant_id = _tenant_id
        and legal_entity_id = _document.legal_entity_id
        and branch_id = _document.branch_id
        and warehouse_id = _line.warehouse_id
        and item_id = _line.item_id
        and valuation_currency = _document.currency
      for update;

      update public.onexa_inventory_balances
      set quantity_on_hand = quantity_on_hand + _line.quantity,
          inventory_value = inventory_value + _line.net_amount,
          updated_at = now()
      where tenant_id = _tenant_id
        and legal_entity_id = _document.legal_entity_id
        and branch_id = _document.branch_id
        and warehouse_id = _line.warehouse_id
        and item_id = _line.item_id
        and valuation_currency = _document.currency;

      insert into public.onexa_inventory_movements (
        tenant_id, legal_entity_id, branch_id, warehouse_id, item_id,
        valuation_currency, movement_type, quantity_delta, unit_cost, value_delta,
        source_document_id, source_document_line_id, source_revision, created_by
      ) values (
        _tenant_id, _document.legal_entity_id, _document.branch_id,
        _line.warehouse_id, _line.item_id, _document.currency, 'receipt',
        _line.quantity, round(_line.net_amount / _line.quantity, 6), _line.net_amount,
        _document.id, _line.id, _document.revision, _actor
      );

      _inventory_amount := _inventory_amount + _line.net_amount;
      _line_dimensions := _line_dimensions || jsonb_build_object('warehouse', _line.warehouse_id, 'item', _line.item_id);
    elsif _line.account_role = 'purchase_expense' then
      _expense_amount := _expense_amount + _line.net_amount;
    else
      _asset_amount := _asset_amount + _line.net_amount;
    end if;

    _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
      'account_code', _line_account,
      'debit', _line.net_amount,
      'credit', 0,
      'description', 'Purchase ' || _line.account_role || ' - ' || _document.document_number || ' - line ' || _line.line_number,
      'dimensions', _line_dimensions
    ));
  end loop;

  if _document.tax_total > 0 then
    _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
      'account_code', _input_vat,
      'debit', _document.tax_total,
      'credit', 0,
      'description', 'Input VAT - ' || _document.document_number,
      'dimensions', _dimensions
    ));
  end if;

  _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
    'account_code', _accounts_payable,
    'debit', 0,
    'credit', _document.gross_total,
    'description', 'Accounts payable - ' || _document.document_number,
    'dimensions', _dimensions
  ));

  select public.onexa_post_journal(
    _legal_entity_id => _document.legal_entity_id,
    _source_document_type => _document.document_type,
    _source_document_id => _document.id::text,
    _source_revision => _document.revision,
    _source_status => 'approved',
    _source_snapshot => coalesce(_document.source_snapshot, '{}'::jsonb) || jsonb_build_object(
      'document_number', _document.document_number,
      'inventory_amount', _inventory_amount,
      'expense_amount', _expense_amount,
      'asset_amount', _asset_amount,
      'posting_contract_version', 'procurement-v1'
    ),
    _accounting_date => _document.accounting_date,
    _period_code => btrim(_period_code),
    _currency => _document.currency,
    _memo => coalesce(_document.memo, 'Purchase invoice ' || _document.document_number),
    _lines => _journal_lines
  )::uuid into _journal_id;

  if _journal_id is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  update public.onexa_inventory_movements
  set journal_id = _journal_id
  where tenant_id = _tenant_id and source_document_id = _document.id
    and source_revision = _document.revision and movement_type = 'receipt';

  insert into public.onexa_purchase_posting_runs (
    document_id, tenant_id, legal_entity_id, journal_id, source_revision,
    payable_amount, net_purchase_amount, tax_amount, inventory_amount,
    expense_amount, asset_amount, posted_by
  ) values (
    _document.id, _tenant_id, _document.legal_entity_id, _journal_id, _document.revision,
    _document.gross_total, _net_purchase_amount, _document.tax_total, _inventory_amount,
    _expense_amount, _asset_amount, _actor
  );

  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', 'posted_from_purchase_invoice', true);

  update public.onexa_business_documents
  set status = 'posted', posted_by = _actor, posted_at = now(),
      posted_journal_id = _journal_id, posting_error = null
  where id = _document.id and tenant_id = _tenant_id and status = 'approved';

  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;

  insert into public.onexa_business_document_events (
    tenant_id, document_id, event_type, from_status, to_status,
    actor_id, event_data
  ) values (
    _tenant_id, _document.id, 'posting_completed', 'approved', 'posted',
    _actor, jsonb_build_object(
      'journal_id', _journal_id,
      'inventory_amount', _inventory_amount,
      'expense_amount', _expense_amount,
      'asset_amount', _asset_amount,
      'posting_contract_version', 'procurement-v1'
    )
  );

  return _journal_id;
end;
$$;

revoke all on table public.onexa_purchase_posting_runs from anon, authenticated;
grant select on table public.onexa_purchase_posting_runs to authenticated;
grant select on table public.onexa_purchase_inventory_reconciliation to authenticated;
grant select on table public.onexa_purchase_posting_configuration_gaps to authenticated;

revoke all on function public.onexa_post_purchase_invoice(uuid, text) from public, anon;
grant execute on function public.onexa_post_purchase_invoice(uuid, text) to authenticated;

commit;
