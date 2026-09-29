-- ONEXA Gate 65: native inventory receipt/issue -> weighted-average stock -> journal.
-- Manual rollout only. Requires Gates 34, 35, 63, and 64 to be READY.

begin;

do $preflight$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null then
    raise exception 'ONEXA_B4_POST_JOURNAL_SIGNATURE_REQUIRED';
  end if;
  if to_regclass('public.onexa_inventory_balances') is null
     or to_regclass('public.onexa_inventory_movements') is null
     or to_regclass('public.onexa_business_documents') is null then
    raise exception 'ONEXA_GATE35_INVENTORY_FOUNDATION_REQUIRED';
  end if;
  if to_regprocedure('public.onexa_approval_separation_required(text,text)') is null
     or to_regprocedure('onexa_private.guard_approval_posting()') is null then
    raise exception 'ONEXA_GATE64_APPROVAL_POSTING_BRIDGE_REQUIRED';
  end if;
end;
$preflight$;

create table if not exists public.onexa_inventory_posting_runs (
  document_id uuid primary key references public.onexa_business_documents(id),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  document_type text not null check (document_type in ('inventory_receipt','inventory_issue')),
  inventory_value numeric(20,4) not null check (inventory_value > 0),
  movement_count integer not null check (movement_count > 0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision > 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now()
);

create index if not exists onexa_inventory_posting_runs_lookup_idx
  on public.onexa_inventory_posting_runs (tenant_id, legal_entity_id, document_type, posted_at desc);

alter table public.onexa_inventory_posting_runs enable row level security;
drop policy if exists onexa_inventory_posting_runs_select_tenant on public.onexa_inventory_posting_runs;
create policy onexa_inventory_posting_runs_select_tenant
  on public.onexa_inventory_posting_runs for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'inventory', 'read')
  );

create or replace view public.onexa_inventory_document_reconciliation
with (security_invoker = true)
as
with movement_totals as (
  select tenant_id, source_document_id,
    count(*)::integer as movement_count,
    round(sum(abs(value_delta)),4) as movement_value
  from public.onexa_inventory_movements
  where movement_type in ('receipt','adjustment_out')
  group by tenant_id, source_document_id
), expected_lines as (
  select tenant_id, document_id, count(*)::integer as expected_movement_count
  from public.onexa_business_document_lines
  where item_id is not null
  group by tenant_id, document_id
)
select document.id as document_id, document.tenant_id, document.legal_entity_id,
  document.branch_id, document.document_type, document.document_number,
  document.document_date, document.status, document.currency,
  document.gross_total as estimated_document_value,
  coalesce(run.inventory_value,0) as posted_inventory_value,
  coalesce(movement.movement_value,0) as movement_inventory_value,
  coalesce(expected.expected_movement_count,0) as expected_movement_count,
  coalesce(movement.movement_count,0) as actual_movement_count,
  document.posted_journal_id,
  case
    when document.status <> 'posted' then 'not_posted'
    when document.posted_journal_id is null or run.journal_id is null then 'journal_missing'
    when document.posted_journal_id <> run.journal_id then 'journal_mismatch'
    when coalesce(expected.expected_movement_count,0) <> coalesce(movement.movement_count,0) then 'movement_missing'
    when abs(coalesce(run.inventory_value,0)-coalesce(movement.movement_value,0)) > 0.01 then 'inventory_value_mismatch'
    else 'reconciled'
  end as reconciliation_status
from public.onexa_business_documents document
left join public.onexa_inventory_posting_runs run
  on run.document_id=document.id and run.tenant_id=document.tenant_id
left join movement_totals movement
  on movement.source_document_id=document.id and movement.tenant_id=document.tenant_id
left join expected_lines expected
  on expected.document_id=document.id and expected.tenant_id=document.tenant_id
where document.document_type in ('inventory_receipt','inventory_issue');

create or replace view public.onexa_inventory_posting_configuration_gaps
with (security_invoker = true)
as
with required_roles(account_role) as (
  values ('inventory'::text), ('goods_received_not_invoiced'::text),
         ('project_cost_cogs_or_expense'::text)
)
select entity.tenant_id, entity.id as legal_entity_id,
  entity.code as legal_entity_code, required.account_role
from public.onexa_legal_entities entity
cross join required_roles required
left join public.onexa_account_role_mappings mapping
  on mapping.tenant_id=entity.tenant_id
 and mapping.legal_entity_id=entity.id
 and mapping.account_role=required.account_role
 and mapping.is_active=true
where entity.is_active=true and mapping.id is null;

create or replace function public.onexa_post_inventory_document(
  _document_id uuid,
  _period_code text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
  _line public.onexa_business_document_lines%rowtype;
  _balance public.onexa_inventory_balances%rowtype;
  _run public.onexa_inventory_posting_runs%rowtype;
  _inventory_account text;
  _offset_account text;
  _movement_type text;
  _line_value numeric(20,4);
  _total_value numeric(20,4) := 0;
  _movement_count integer := 0;
  _journal_lines jsonb := '[]'::jsonb;
  _dimensions jsonb;
  _journal uuid;
begin
  if _actor is null or nullif(_tenant,'') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor,'inventory','post') then
    raise exception 'ONEXA_INVENTORY_POST_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_period_code),'') is null or btrim(_period_code) !~ '^\\d{4}-\\d{2}$' then
    raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':inventory:' || _document_id::text,0));
  select * into _document from public.onexa_business_documents
  where id=_document_id and tenant_id=_tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;

  select * into _run from public.onexa_inventory_posting_runs
  where document_id=_document.id and tenant_id=_tenant;
  if _document.status='posted' then
    if _document.posted_journal_id is not null
       and _run.journal_id is not distinct from _document.posted_journal_id then
      return _document.posted_journal_id;
    end if;
    raise exception 'ONEXA_INVENTORY_POSTING_RETRY_STATE_INVALID';
  end if;
  if _document.module_key<>'inventory'
     or _document.document_type not in ('inventory_receipt','inventory_issue') then
    raise exception 'ONEXA_INVENTORY_DOCUMENT_REQUIRED';
  end if;
  if _document.status<>'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.branch_id is null then raise exception 'ONEXA_BRANCH_REQUIRED'; end if;
  if _actor=_document.created_by
     and public.onexa_approval_separation_required(_document.document_type,'post') then
    raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
  end if;

  if not exists (select 1 from public.onexa_business_document_lines where document_id=_document.id) then
    raise exception 'ONEXA_DOCUMENT_LINES_REQUIRED';
  end if;
  if exists (
    select 1 from public.onexa_business_document_lines
    where document_id=_document.id
      and (item_id is null or warehouse_id is null or quantity<=0
        or tax_amount<>0 or discount_amount<>0)
  ) then raise exception 'ONEXA_INVENTORY_LINE_INVALID'; end if;
  if exists (
    select 1 from public.onexa_business_document_lines line
    left join public.inventory_items item
      on item.id=line.item_id and item.tenant_id=_tenant and item.is_active=true
    left join public.inventory_warehouses warehouse
      on warehouse.id=line.warehouse_id and warehouse.tenant_id=_tenant and warehouse.is_active=true
    where line.document_id=_document.id and (item.id is null or warehouse.id is null)
  ) then raise exception 'ONEXA_INVENTORY_ITEM_OR_WAREHOUSE_INVALID'; end if;
  if _document.document_type='inventory_issue' and exists (
    select 1 from public.onexa_business_document_lines line
    where line.document_id=_document.id
      and nullif(btrim(coalesce(line.dimensions->>'costCenter',_document.dimensions->>'costCenter','')),'') is null
  ) then raise exception 'ONEXA_INVENTORY_ISSUE_COST_CENTER_REQUIRED'; end if;

  select account_code into _inventory_account from public.onexa_account_role_mappings
  where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
    and account_role='inventory' and is_active=true;
  select account_code into _offset_account from public.onexa_account_role_mappings
  where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
    and account_role=case when _document.document_type='inventory_receipt'
      then 'goods_received_not_invoiced' else 'project_cost_cogs_or_expense' end
    and is_active=true;
  if _inventory_account is null or _offset_account is null then
    raise exception 'ONEXA_INVENTORY_ACCOUNT_MAPPING_REQUIRED';
  end if;
  _movement_type := case when _document.document_type='inventory_receipt'
    then 'receipt' else 'adjustment_out' end;

  for _line in
    select * from public.onexa_business_document_lines
    where document_id=_document.id order by warehouse_id,item_id,line_number
  loop
    _dimensions := coalesce(_document.dimensions,'{}'::jsonb)
      || coalesce(_line.dimensions,'{}'::jsonb)
      || jsonb_build_object('legalEntity',_document.legal_entity_id,
        'branch',_document.branch_id,'warehouse',_line.warehouse_id,'item',_line.item_id);

    if _document.document_type='inventory_receipt' then
      _line_value := round(_line.quantity*_line.unit_price,4);
      if _line.unit_price<=0 or abs(_line.net_amount-_line_value)>0.01
         or abs(_line.gross_amount-_line_value)>0.01 then
        raise exception 'ONEXA_INVENTORY_RECEIPT_VALUE_INVALID:line=%',_line.line_number;
      end if;
      insert into public.onexa_inventory_balances
        (tenant_id,legal_entity_id,branch_id,warehouse_id,item_id,valuation_currency)
      values (_tenant,_document.legal_entity_id,_document.branch_id,
        _line.warehouse_id,_line.item_id,_document.currency)
      on conflict do nothing;
      select * into _balance from public.onexa_inventory_balances
      where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
        and branch_id=_document.branch_id and warehouse_id=_line.warehouse_id
        and item_id=_line.item_id and valuation_currency=_document.currency for update;
      update public.onexa_inventory_balances
      set quantity_on_hand=quantity_on_hand+_line.quantity,
          inventory_value=inventory_value+_line_value,updated_at=now()
      where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
        and branch_id=_document.branch_id and warehouse_id=_line.warehouse_id
        and item_id=_line.item_id and valuation_currency=_document.currency;
    else
      select * into _balance from public.onexa_inventory_balances
      where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
        and branch_id=_document.branch_id and warehouse_id=_line.warehouse_id
        and item_id=_line.item_id and valuation_currency=_document.currency for update;
      if not found then raise exception 'ONEXA_INVENTORY_BALANCE_NOT_FOUND:%:%',_line.warehouse_id,_line.item_id; end if;
      if _balance.quantity_on_hand<_line.quantity then
        raise exception 'ONEXA_INSUFFICIENT_STOCK:%:%',_line.item_id,_balance.quantity_on_hand;
      end if;
      _line_value := case when _balance.quantity_on_hand=_line.quantity then _balance.inventory_value
        else round((_balance.inventory_value/_balance.quantity_on_hand)*_line.quantity,4) end;
      if _line_value<=0 then raise exception 'ONEXA_INVENTORY_ISSUE_ZERO_VALUE:%',_line.item_id; end if;
      update public.onexa_inventory_balances
      set quantity_on_hand=quantity_on_hand-_line.quantity,
          inventory_value=case when quantity_on_hand-_line.quantity=0 then 0 else inventory_value-_line_value end,
          updated_at=now()
      where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id
        and branch_id=_document.branch_id and warehouse_id=_line.warehouse_id
        and item_id=_line.item_id and valuation_currency=_document.currency;
    end if;

    insert into public.onexa_inventory_movements (
      tenant_id,legal_entity_id,branch_id,warehouse_id,item_id,valuation_currency,
      movement_type,quantity_delta,unit_cost,value_delta,source_document_id,
      source_document_line_id,source_revision,created_by
    ) values (
      _tenant,_document.legal_entity_id,_document.branch_id,_line.warehouse_id,_line.item_id,
      _document.currency,_movement_type,
      case when _document.document_type='inventory_receipt' then _line.quantity else -_line.quantity end,
      round(_line_value/_line.quantity,6),
      case when _document.document_type='inventory_receipt' then _line_value else -_line_value end,
      _document.id,_line.id,_document.revision,_actor
    );

    _journal_lines := _journal_lines || jsonb_build_array(
      jsonb_build_object('account_code',case when _document.document_type='inventory_receipt' then _inventory_account else _offset_account end,
        'debit',_line_value,'credit',0,'description',case when _document.document_type='inventory_receipt' then 'Inventory receipt' else 'Inventory issue cost' end,
        'dimensions',_dimensions),
      jsonb_build_object('account_code',case when _document.document_type='inventory_receipt' then _offset_account else _inventory_account end,
        'debit',0,'credit',_line_value,'description',case when _document.document_type='inventory_receipt' then 'Goods received not invoiced' else 'Inventory issued' end,
        'dimensions',_dimensions)
    );
    _total_value := _total_value+_line_value;
    _movement_count := _movement_count+1;
  end loop;

  if _total_value<=0 or _movement_count=0 then raise exception 'ONEXA_INVENTORY_POSTING_VALUE_REQUIRED'; end if;
  _journal := public.onexa_post_journal(
    _document.legal_entity_id,_document.document_type,_document.id::text,_document.revision,
    'approved',coalesce(_document.source_snapshot,'{}'::jsonb)||jsonb_build_object(
      'document_number',_document.document_number,'inventory_value',_total_value,
      'movement_count',_movement_count,'posting_contract_version','inventory-v1'),
    _document.accounting_date,btrim(_period_code),_document.currency,
    coalesce(_document.memo,case when _document.document_type='inventory_receipt'
      then 'Inventory receipt ' else 'Inventory issue ' end||_document.document_number),_journal_lines
  );
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  update public.onexa_inventory_movements set journal_id=_journal
  where tenant_id=_tenant and source_document_id=_document.id
    and source_revision=_document.revision and movement_type=_movement_type;
  insert into public.onexa_inventory_posting_runs
    (document_id,tenant_id,legal_entity_id,document_type,inventory_value,movement_count,
     journal_id,source_revision,posted_by)
  values (_document.id,_tenant,_document.legal_entity_id,_document.document_type,
    _total_value,_movement_count,_journal,_document.revision,_actor);

  perform set_config('onexa.transition_authorized','true',true);
  perform set_config('onexa.transition_reason','posted_from_inventory_document',true);
  update public.onexa_business_documents set status='posted',posted_by=_actor,posted_at=now(),
    posted_journal_id=_journal,posting_error=null
  where id=_document.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id,document_id,event_type,from_status,to_status,actor_id,event_data)
  values (_tenant,_document.id,'posting_completed','approved','posted',_actor,
    jsonb_build_object('journal_id',_journal,'inventory_value',_total_value,
      'movement_count',_movement_count,'posting_contract_version','inventory-v1'));
  return _journal;
end;
$$;

revoke all on public.onexa_inventory_posting_runs from anon,authenticated;
grant select on public.onexa_inventory_posting_runs to authenticated;
grant select on public.onexa_inventory_document_reconciliation,
  public.onexa_inventory_posting_configuration_gaps to authenticated;
revoke all on function public.onexa_post_inventory_document(uuid,text) from public,anon;
grant execute on function public.onexa_post_inventory_document(uuid,text) to authenticated;

commit;
