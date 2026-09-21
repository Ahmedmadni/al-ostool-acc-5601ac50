-- ONEXA Gate 35: sales invoice -> inventory -> accounts receivable -> journal.
-- Inventory issues use moving weighted average cost from the locked stock balance.
--
-- Manual review package. Do not run in production until B2/B3 are complete,
-- the B4 function preflight passes, account-role mappings are configured, and
-- the package has passed on a disposable Supabase branch.

begin;

do $$
begin
  if to_regprocedure(
    'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'
  ) is null then
    raise exception 'ONEXA_B4_POST_JOURNAL_SIGNATURE_REQUIRED';
  end if;
  if to_regclass('public.onexa_account_role_mappings') is null then
    raise exception 'ONEXA_ACCOUNT_ROLE_MAPPINGS_REQUIRED';
  end if;
  if to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_B3_MODULE_AUTHORIZATION_REQUIRED';
  end if;
end;
$$;

create table if not exists public.onexa_inventory_balances (
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  warehouse_id uuid not null,
  item_id uuid not null,
  valuation_currency text not null check (valuation_currency ~ '^[A-Z]{3}$'),
  quantity_on_hand numeric(20, 6) not null default 0 check (quantity_on_hand >= 0),
  inventory_value numeric(20, 4) not null default 0 check (inventory_value >= 0),
  average_unit_cost numeric(20, 6) generated always as (
    case when quantity_on_hand = 0 then 0
         else round(inventory_value / quantity_on_hand, 6)
    end
  ) stored,
  updated_at timestamptz not null default now(),
  primary key (
    tenant_id, legal_entity_id, branch_id, warehouse_id, item_id, valuation_currency
  ),
  constraint onexa_inventory_balances_zero_pair check (
    quantity_on_hand > 0 or inventory_value = 0
  )
);

create table if not exists public.onexa_inventory_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  warehouse_id uuid not null,
  item_id uuid not null,
  valuation_currency text not null check (valuation_currency ~ '^[A-Z]{3}$'),
  movement_type text not null check (movement_type in (
    'opening', 'receipt', 'sale_issue', 'transfer_in', 'transfer_out',
    'adjustment_in', 'adjustment_out', 'reversal'
  )),
  quantity_delta numeric(20, 6) not null check (quantity_delta <> 0),
  unit_cost numeric(20, 6) not null check (unit_cost >= 0),
  value_delta numeric(20, 4) not null,
  source_document_id uuid not null references public.onexa_business_documents(id),
  source_document_line_id uuid not null references public.onexa_business_document_lines(id),
  source_revision integer not null check (source_revision > 0),
  journal_id uuid,
  occurred_at timestamptz not null default now(),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  constraint onexa_inventory_movements_direction check (
    (quantity_delta > 0 and value_delta >= 0) or
    (quantity_delta < 0 and value_delta <= 0)
  ),
  unique (tenant_id, source_document_id, source_document_line_id, source_revision, movement_type)
);

create table if not exists public.onexa_sales_posting_runs (
  document_id uuid primary key references public.onexa_business_documents(id),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision > 0),
  receivable_amount numeric(20, 4) not null check (receivable_amount >= 0),
  revenue_amount numeric(20, 4) not null check (revenue_amount >= 0),
  tax_amount numeric(20, 4) not null check (tax_amount >= 0),
  inventory_cost numeric(20, 4) not null check (inventory_cost >= 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  constraint onexa_sales_posting_runs_invoice_math check (
    abs(receivable_amount - (revenue_amount + tax_amount)) <= 0.01
  )
);

create index if not exists onexa_inventory_movements_stock_history_idx
  on public.onexa_inventory_movements (
    tenant_id, legal_entity_id, branch_id, warehouse_id, item_id, occurred_at desc
  );
create index if not exists onexa_inventory_movements_document_idx
  on public.onexa_inventory_movements (tenant_id, source_document_id, source_document_line_id);
create index if not exists onexa_sales_posting_runs_journal_idx
  on public.onexa_sales_posting_runs (tenant_id, legal_entity_id, journal_id);

alter table public.onexa_inventory_balances enable row level security;
alter table public.onexa_inventory_movements enable row level security;
alter table public.onexa_sales_posting_runs enable row level security;

drop policy if exists onexa_inventory_balances_select_tenant on public.onexa_inventory_balances;
create policy onexa_inventory_balances_select_tenant
  on public.onexa_inventory_balances for select
  to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'inventory', 'read')
  );

drop policy if exists onexa_inventory_movements_select_tenant on public.onexa_inventory_movements;
create policy onexa_inventory_movements_select_tenant
  on public.onexa_inventory_movements for select
  to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'inventory', 'read')
  );

drop policy if exists onexa_sales_posting_runs_select_tenant on public.onexa_sales_posting_runs;
create policy onexa_sales_posting_runs_select_tenant
  on public.onexa_sales_posting_runs for select
  to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'sales', 'read')
  );

create or replace view public.onexa_inventory_stock_valuation
with (security_invoker = true)
as
select
  tenant_id,
  legal_entity_id,
  branch_id,
  warehouse_id,
  item_id,
  valuation_currency,
  quantity_on_hand,
  average_unit_cost,
  inventory_value,
  updated_at
from public.onexa_inventory_balances;

create or replace view public.onexa_sales_inventory_reconciliation
with (security_invoker = true)
as
with movement_totals as (
  select
    tenant_id,
    source_document_id,
    count(*) as movement_count,
    sum(-quantity_delta) as issued_quantity,
    sum(-value_delta) as issued_inventory_value
  from public.onexa_inventory_movements
  where movement_type = 'sale_issue'
  group by tenant_id, source_document_id
), expected_lines as (
  select
    tenant_id,
    document_id,
    count(*) filter (where item_id is not null) as expected_movement_count
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
  document.currency,
  document.status,
  document.gross_total as receivable_amount,
  document.subtotal - document.discount_total as revenue_amount,
  document.tax_total as tax_amount,
  coalesce(run.inventory_cost, 0) as posted_inventory_cost,
  coalesce(movement.issued_inventory_value, 0) as movement_inventory_cost,
  coalesce(expected.expected_movement_count, 0) as expected_movement_count,
  coalesce(movement.movement_count, 0) as actual_movement_count,
  document.posted_journal_id,
  case
    when document.status <> 'posted' then 'not_posted'
    when document.posted_journal_id is null or run.journal_id is null then 'journal_missing'
    when abs(document.gross_total - ((document.subtotal - document.discount_total) + document.tax_total)) > 0.01 then 'invoice_unbalanced'
    when coalesce(expected.expected_movement_count, 0) <> coalesce(movement.movement_count, 0) then 'stock_movement_missing'
    when abs(coalesce(run.inventory_cost, 0) - coalesce(movement.issued_inventory_value, 0)) > 0.01 then 'inventory_value_mismatch'
    else 'reconciled'
  end as reconciliation_status
from public.onexa_business_documents document
left join public.onexa_sales_posting_runs run
  on run.document_id = document.id and run.tenant_id = document.tenant_id
left join movement_totals movement
  on movement.source_document_id = document.id and movement.tenant_id = document.tenant_id
left join expected_lines expected
  on expected.document_id = document.id and expected.tenant_id = document.tenant_id
where document.document_type = 'sales_invoice';

create or replace view public.onexa_sales_posting_configuration_gaps
with (security_invoker = true)
as
with required_roles(account_role) as (
  values
    ('accounts_receivable'::text),
    ('sales_revenue'::text),
    ('output_vat'::text),
    ('cost_of_goods_sold'::text),
    ('inventory'::text)
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

create or replace function public.onexa_post_sales_invoice(
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
  _balance public.onexa_inventory_balances%rowtype;
  _accounts_receivable text;
  _sales_revenue text;
  _output_vat text;
  _cost_of_goods_sold text;
  _inventory text;
  _revenue_amount numeric(20, 4);
  _line_cost numeric(20, 4);
  _inventory_cost numeric(20, 4) := 0;
  _journal_lines jsonb := '[]'::jsonb;
  _dimensions jsonb;
  _journal_id uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'sales', 'post') then
    raise exception 'ONEXA_SALES_POST_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_period_code), '') is null then
    raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(_tenant_id || ':sales:' || _document_id::text, 0));

  select * into _document
  from public.onexa_business_documents
  where id = _document_id and tenant_id = _tenant_id
  for update;

  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _document.status = 'posted' and _document.posted_journal_id is not null then
    return _document.posted_journal_id;
  end if;
  if _document.document_type <> 'sales_invoice' or _document.module_key <> 'sales' then
    raise exception 'ONEXA_SALES_INVOICE_REQUIRED';
  end if;
  if _document.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.branch_id is null then raise exception 'ONEXA_BRANCH_REQUIRED'; end if;
  if _document.party_type <> 'customer' or _document.party_id is null then raise exception 'ONEXA_CUSTOMER_REQUIRED'; end if;
  if _actor = _document.created_by then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;

  perform 1
  from public.onexa_business_document_lines
  where document_id = _document.id;
  if not found then raise exception 'ONEXA_DOCUMENT_LINES_REQUIRED'; end if;

  perform 1
  from public.onexa_business_document_lines
  where document_id = _document.id and item_id is not null and warehouse_id is null;
  if found then raise exception 'ONEXA_STOCKED_LINE_REQUIRES_WAREHOUSE'; end if;

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
  if not found then raise exception 'ONEXA_SALES_INVOICE_LINE_TOTALS_MISMATCH'; end if;

  select account_code into _accounts_receivable
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'accounts_receivable' and is_active = true;
  select account_code into _sales_revenue
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'sales_revenue' and is_active = true;
  select account_code into _output_vat
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'output_vat' and is_active = true;
  select account_code into _cost_of_goods_sold
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'cost_of_goods_sold' and is_active = true;
  select account_code into _inventory
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _document.legal_entity_id
    and account_role = 'inventory' and is_active = true;

  if _accounts_receivable is null or _sales_revenue is null then
    raise exception 'ONEXA_SALES_ACCOUNT_MAPPING_REQUIRED';
  end if;
  if _document.tax_total > 0 and _output_vat is null then
    raise exception 'ONEXA_OUTPUT_VAT_ACCOUNT_MAPPING_REQUIRED';
  end if;

  _revenue_amount := _document.subtotal - _document.discount_total;
  _dimensions := coalesce(_document.dimensions, '{}'::jsonb) || jsonb_build_object(
    'legalEntity', _document.legal_entity_id,
    'branch', _document.branch_id,
    'customer', _document.party_id
  );

  _journal_lines := jsonb_build_array(
    jsonb_build_object(
      'account_code', _accounts_receivable,
      'debit', _document.gross_total,
      'credit', 0,
      'description', 'Accounts receivable - ' || _document.document_number,
      'dimensions', _dimensions
    ),
    jsonb_build_object(
      'account_code', _sales_revenue,
      'debit', 0,
      'credit', _revenue_amount,
      'description', 'Sales revenue - ' || _document.document_number,
      'dimensions', _dimensions
    )
  );

  if _document.tax_total > 0 then
    _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
      'account_code', _output_vat,
      'debit', 0,
      'credit', _document.tax_total,
      'description', 'Output VAT - ' || _document.document_number,
      'dimensions', _dimensions
    ));
  end if;

  for _line in
    select *
    from public.onexa_business_document_lines
    where document_id = _document.id and item_id is not null
    order by warehouse_id, item_id, line_number
  loop
    select * into _balance
    from public.onexa_inventory_balances
    where tenant_id = _tenant_id
      and legal_entity_id = _document.legal_entity_id
      and branch_id = _document.branch_id
      and warehouse_id = _line.warehouse_id
      and item_id = _line.item_id
      and valuation_currency = _document.currency
    for update;

    if not found then raise exception 'ONEXA_INVENTORY_BALANCE_NOT_FOUND:%:%', _line.warehouse_id, _line.item_id; end if;
    if _balance.quantity_on_hand < _line.quantity then
      raise exception 'ONEXA_INSUFFICIENT_STOCK:%:%', _line.item_id, _balance.quantity_on_hand;
    end if;
    _line_cost := case
      when _balance.quantity_on_hand = _line.quantity then _balance.inventory_value
      else round((_balance.inventory_value / _balance.quantity_on_hand) * _line.quantity, 4)
    end;

    update public.onexa_inventory_balances
    set quantity_on_hand = quantity_on_hand - _line.quantity,
        inventory_value = case
          when quantity_on_hand - _line.quantity = 0 then 0
          else inventory_value - _line_cost
        end,
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
      _line.warehouse_id, _line.item_id, _document.currency, 'sale_issue',
      -_line.quantity, round(_line_cost / _line.quantity, 6), -_line_cost,
      _document.id, _line.id, _document.revision, _actor
    );

    _inventory_cost := _inventory_cost + _line_cost;
    if _line_cost > 0 then
      if _cost_of_goods_sold is null or _inventory is null then
        raise exception 'ONEXA_INVENTORY_ACCOUNT_MAPPING_REQUIRED';
      end if;
      _journal_lines := _journal_lines || jsonb_build_array(
        jsonb_build_object(
          'account_code', _cost_of_goods_sold,
          'debit', _line_cost,
          'credit', 0,
          'description', 'COGS - ' || _document.document_number || ' - line ' || _line.line_number,
          'dimensions', _dimensions || jsonb_build_object('warehouse', _line.warehouse_id, 'item', _line.item_id)
        ),
        jsonb_build_object(
          'account_code', _inventory,
          'debit', 0,
          'credit', _line_cost,
          'description', 'Inventory issue - ' || _document.document_number || ' - line ' || _line.line_number,
          'dimensions', _dimensions || jsonb_build_object('warehouse', _line.warehouse_id, 'item', _line.item_id)
        )
      );
    end if;
  end loop;

  select public.onexa_post_journal(
    _legal_entity_id => _document.legal_entity_id,
    _source_document_type => _document.document_type,
    _source_document_id => _document.id::text,
    _source_revision => _document.revision,
    _source_status => 'approved',
    _source_snapshot => coalesce(_document.source_snapshot, '{}'::jsonb) || jsonb_build_object(
      'document_number', _document.document_number,
      'inventory_cost', _inventory_cost,
      'posting_contract_version', 'sales-v1'
    ),
    _accounting_date => _document.accounting_date,
    _period_code => btrim(_period_code),
    _currency => _document.currency,
    _memo => coalesce(_document.memo, 'Sales invoice ' || _document.document_number),
    _lines => _journal_lines
  )::uuid into _journal_id;

  if _journal_id is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  update public.onexa_inventory_movements
  set journal_id = _journal_id
  where tenant_id = _tenant_id and source_document_id = _document.id
    and source_revision = _document.revision and movement_type = 'sale_issue';

  insert into public.onexa_sales_posting_runs (
    document_id, tenant_id, legal_entity_id, journal_id, source_revision,
    receivable_amount, revenue_amount, tax_amount, inventory_cost, posted_by
  ) values (
    _document.id, _tenant_id, _document.legal_entity_id, _journal_id, _document.revision,
    _document.gross_total, _revenue_amount, _document.tax_total, _inventory_cost, _actor
  );

  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', 'posted_from_sales_invoice', true);

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
      'inventory_cost', _inventory_cost,
      'posting_contract_version', 'sales-v1'
    )
  );

  return _journal_id;
exception
  when others then
    raise;
end;
$$;

revoke all on table public.onexa_inventory_balances from anon, authenticated;
revoke all on table public.onexa_inventory_movements from anon, authenticated;
revoke all on table public.onexa_sales_posting_runs from anon, authenticated;
grant select on table public.onexa_inventory_balances to authenticated;
grant select on table public.onexa_inventory_movements to authenticated;
grant select on table public.onexa_sales_posting_runs to authenticated;
grant select on table public.onexa_inventory_stock_valuation to authenticated;
grant select on table public.onexa_sales_inventory_reconciliation to authenticated;
grant select on table public.onexa_sales_posting_configuration_gaps to authenticated;

revoke all on function public.onexa_post_sales_invoice(uuid, text) from public, anon;
grant execute on function public.onexa_post_sales_invoice(uuid, text) to authenticated;

commit;
