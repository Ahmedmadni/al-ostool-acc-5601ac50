-- Gate 39: approved ONEXA customer receipt -> invoice allocation -> B4 ledger.
-- Manual package only. Do not apply to production before rollout authorization.
begin;

do $$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
    or to_regclass('public.onexa_sales_posting_runs') is null
    or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE39_FOUNDATION_REQUIRED';
  end if;
end;
$$;

create table if not exists public.onexa_customer_receipt_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  customer_id uuid not null,
  journal_id uuid not null unique,
  amount numeric(20,4) not null check (amount > 0),
  source_revision integer not null check (source_revision > 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now()
);

create table if not exists public.onexa_customer_receipt_allocations (
  receipt_id uuid not null references public.onexa_customer_receipt_postings(document_id) on delete restrict,
  invoice_id uuid not null references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  customer_id uuid not null,
  amount numeric(20,4) not null check (amount > 0),
  primary key (receipt_id, invoice_id)
);
create index if not exists onexa_receipt_allocations_invoice_idx
  on public.onexa_customer_receipt_allocations(tenant_id, invoice_id);

alter table public.onexa_customer_receipt_postings enable row level security;
alter table public.onexa_customer_receipt_allocations enable row level security;
drop policy if exists onexa_receipt_postings_read on public.onexa_customer_receipt_postings;
create policy onexa_receipt_postings_read on public.onexa_customer_receipt_postings
  for select to authenticated using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'sales', 'read')
  );
drop policy if exists onexa_receipt_allocations_read on public.onexa_customer_receipt_allocations;
create policy onexa_receipt_allocations_read on public.onexa_customer_receipt_allocations
  for select to authenticated using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'sales', 'read')
  );

create or replace view public.onexa_customer_receivables_reconciliation
with (security_invoker = true) as
select invoice.id as invoice_id, invoice.tenant_id, invoice.legal_entity_id,
  invoice.branch_id, invoice.party_id as customer_id, invoice.document_number,
  invoice.currency, invoice.due_date, invoice.gross_total as invoiced_amount,
  coalesce(sum(allocation.amount), 0)::numeric(20,4) as collected_amount,
  (invoice.gross_total - coalesce(sum(allocation.amount), 0))::numeric(20,4) as outstanding_amount,
  case when invoice.status <> 'posted' then 'invoice_not_posted'
       when invoice.posted_journal_id is distinct from sales.journal_id then 'invoice_journal_mismatch'
       when coalesce(sum(allocation.amount), 0) > invoice.gross_total + 0.01 then 'overallocated'
       else 'reconciled' end as reconciliation_status
from public.onexa_business_documents invoice
left join public.onexa_sales_posting_runs sales on sales.document_id = invoice.id
  and sales.tenant_id = invoice.tenant_id
left join public.onexa_customer_receipt_allocations allocation on allocation.invoice_id = invoice.id
  and allocation.tenant_id = invoice.tenant_id
where invoice.document_type = 'sales_invoice'
group by invoice.id, sales.journal_id;

create or replace view public.onexa_customer_receipt_configuration_gaps
with (security_invoker = true) as
with roles(account_role) as (values ('accounts_receivable'::text), ('cash_or_bank'::text))
select entity.tenant_id, entity.id as legal_entity_id, entity.code as legal_entity_code,
  roles.account_role
from public.onexa_legal_entities entity cross join roles
left join public.onexa_account_role_mappings mapping
  on mapping.tenant_id = entity.tenant_id and mapping.legal_entity_id = entity.id
 and mapping.account_role = roles.account_role and mapping.is_active = true
where entity.is_active = true and mapping.id is null;

create or replace function public.onexa_post_customer_receipt(_document_id uuid, _period_code text)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _receipt public.onexa_business_documents%rowtype;
  _invoice public.onexa_business_documents%rowtype;
  _allocation record;
  _allocation_total numeric(20,4) := 0;
  _allocated numeric(20,4);
  _cash text;
  _ar text;
  _journal uuid;
  _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant, '') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor, 'sales', 'post') then
    raise exception 'ONEXA_RECEIPT_POST_NOT_AUTHORIZED';
  end if;
  if coalesce(btrim(_period_code), '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':receipt:' || _document_id::text, 0));
  select * into _receipt from public.onexa_business_documents
    where id = _document_id and tenant_id = _tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _receipt.document_type <> 'customer_receipt' or _receipt.module_key <> 'sales' then
    raise exception 'ONEXA_CUSTOMER_RECEIPT_REQUIRED';
  end if;
  if _receipt.status = 'posted' and _receipt.posted_journal_id is not null then
    select journal_id into _journal from public.onexa_customer_receipt_postings
      where document_id = _receipt.id and tenant_id = _tenant;
    if _journal is distinct from _receipt.posted_journal_id then
      raise exception 'ONEXA_RECEIPT_RETRY_JOURNAL_MISMATCH';
    end if;
    return _journal;
  end if;
  if _receipt.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _receipt.created_by = _actor then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _receipt.branch_id is null or _receipt.party_type <> 'customer' or _receipt.party_id is null then
    raise exception 'ONEXA_RECEIPT_CUSTOMER_BRANCH_REQUIRED';
  end if;
  if _receipt.gross_total <= 0 or _receipt.tax_total <> 0 or _receipt.discount_total <> 0
    or _receipt.subtotal <> _receipt.gross_total then
    raise exception 'ONEXA_RECEIPT_AMOUNT_INVALID';
  end if;
  if (select count(*) from public.onexa_business_document_lines where document_id = _receipt.id) <> 1
    or not exists (
      select 1 from public.onexa_business_document_lines
      where document_id = _receipt.id and tenant_id = _tenant
        and item_id is null and tax_amount = 0 and net_amount = _receipt.gross_total
        and gross_amount = _receipt.gross_total
    ) then raise exception 'ONEXA_RECEIPT_LINE_MISMATCH'; end if;
  if jsonb_typeof(_receipt.source_snapshot->'invoice_allocations') <> 'array'
    or jsonb_array_length(_receipt.source_snapshot->'invoice_allocations') = 0 then
    raise exception 'ONEXA_RECEIPT_ALLOCATIONS_REQUIRED';
  end if;
  if exists (
    select 1 from (
      select entry->>'invoice_id' as invoice_id
      from jsonb_array_elements(_receipt.source_snapshot->'invoice_allocations') entry
      group by entry->>'invoice_id' having count(*) > 1
    ) duplicated
  ) then raise exception 'ONEXA_RECEIPT_DUPLICATE_INVOICE'; end if;

  -- Lock every invoice in stable order to serialize receipts competing for its balance.
  for _allocation in
    select (entry->>'invoice_id')::uuid as invoice_id,
      (entry->>'amount')::numeric(20,4) as amount
    from jsonb_array_elements(_receipt.source_snapshot->'invoice_allocations') entry
    order by (entry->>'invoice_id')::uuid
  loop
    if _allocation.amount is null or _allocation.amount <= 0 then
      raise exception 'ONEXA_RECEIPT_ALLOCATION_AMOUNT_INVALID';
    end if;
    select * into _invoice from public.onexa_business_documents
      where id = _allocation.invoice_id and tenant_id = _tenant for update;
    if not found or _invoice.document_type <> 'sales_invoice' or _invoice.status <> 'posted'
      or _invoice.posted_journal_id is null
      or _invoice.legal_entity_id <> _receipt.legal_entity_id
      or _invoice.branch_id <> _receipt.branch_id
      or _invoice.party_id <> _receipt.party_id
      or _invoice.currency <> _receipt.currency then
      raise exception 'ONEXA_RECEIPT_INVOICE_MISMATCH';
    end if;
    perform 1 from public.onexa_sales_posting_runs
      where document_id = _invoice.id and tenant_id = _tenant
        and journal_id = _invoice.posted_journal_id;
    if not found then raise exception 'ONEXA_RECEIPT_INVOICE_LEDGER_MISSING'; end if;
    select coalesce(sum(amount), 0) into _allocated
      from public.onexa_customer_receipt_allocations
      where tenant_id = _tenant and invoice_id = _invoice.id;
    if _allocated + _allocation.amount > _invoice.gross_total then
      raise exception 'ONEXA_RECEIPT_INVOICE_OVERPAYMENT';
    end if;
    _allocation_total := _allocation_total + _allocation.amount;
  end loop;
  if _allocation_total <> _receipt.gross_total then
    raise exception 'ONEXA_RECEIPT_ALLOCATION_TOTAL_MISMATCH';
  end if;

  select account_code into _cash from public.onexa_account_role_mappings
    where tenant_id = _tenant and legal_entity_id = _receipt.legal_entity_id
      and account_role = 'cash_or_bank' and is_active = true;
  select account_code into _ar from public.onexa_account_role_mappings
    where tenant_id = _tenant and legal_entity_id = _receipt.legal_entity_id
      and account_role = 'accounts_receivable' and is_active = true;
  if _cash is null or _ar is null then raise exception 'ONEXA_RECEIPT_ACCOUNT_MAPPING_REQUIRED'; end if;
  _dimensions := _receipt.dimensions || jsonb_build_object(
    'legalEntity', _receipt.legal_entity_id, 'branch', _receipt.branch_id,
    'customer', _receipt.party_id
  );
  select public.onexa_post_journal(
    _legal_entity_id => _receipt.legal_entity_id,
    _source_document_type => 'customer_receipt',
    _source_document_id => _receipt.id::text,
    _source_revision => _receipt.revision,
    _source_status => 'approved',
    _source_snapshot => _receipt.source_snapshot || jsonb_build_object(
      'document_number', _receipt.document_number,
      'posting_contract_version', 'customer-receipt-v1'),
    _accounting_date => _receipt.accounting_date,
    _period_code => btrim(_period_code),
    _currency => _receipt.currency,
    _memo => coalesce(_receipt.memo, 'Customer receipt ' || _receipt.document_number),
    _lines => jsonb_build_array(
      jsonb_build_object('account_code', _cash, 'debit', _receipt.gross_total,
        'credit', 0, 'description', 'Customer collection', 'dimensions', _dimensions),
      jsonb_build_object('account_code', _ar, 'debit', 0,
        'credit', _receipt.gross_total, 'description', 'Accounts receivable settlement',
        'dimensions', _dimensions)
    )
  )::uuid into _journal;
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  insert into public.onexa_customer_receipt_postings
    (document_id, tenant_id, legal_entity_id, customer_id, journal_id, amount,
     source_revision, posted_by)
  values (_receipt.id, _tenant, _receipt.legal_entity_id, _receipt.party_id,
    _journal, _receipt.gross_total, _receipt.revision, _actor);
  insert into public.onexa_customer_receipt_allocations
    (receipt_id, invoice_id, tenant_id, legal_entity_id, customer_id, amount)
  select _receipt.id, (entry->>'invoice_id')::uuid, _tenant,
    _receipt.legal_entity_id, _receipt.party_id, (entry->>'amount')::numeric(20,4)
  from jsonb_array_elements(_receipt.source_snapshot->'invoice_allocations') entry;

  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', 'posted_from_customer_receipt', true);
  update public.onexa_business_documents
    set status = 'posted', posted_by = _actor, posted_at = now(),
      posted_journal_id = _journal, posting_error = null
    where id = _receipt.id and tenant_id = _tenant and status = 'approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id, document_id, event_type, from_status, to_status, actor_id, event_data)
  values (_tenant, _receipt.id, 'posting_completed', 'approved', 'posted', _actor,
    jsonb_build_object('journal_id', _journal, 'posting_contract_version', 'customer-receipt-v1'));
  return _journal;
end;
$$;

revoke all on public.onexa_customer_receipt_postings from anon, authenticated;
revoke all on public.onexa_customer_receipt_allocations from anon, authenticated;
grant select on public.onexa_customer_receipt_postings to authenticated;
grant select on public.onexa_customer_receipt_allocations to authenticated;
grant select on public.onexa_customer_receivables_reconciliation to authenticated;
grant select on public.onexa_customer_receipt_configuration_gaps to authenticated;
revoke all on function public.onexa_post_customer_receipt(uuid,text) from public, anon;
grant execute on function public.onexa_post_customer_receipt(uuid,text) to authenticated;
commit;
