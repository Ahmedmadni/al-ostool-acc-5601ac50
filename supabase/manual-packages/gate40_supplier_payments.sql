-- Gate 40: approved ONEXA supplier payment -> invoice allocation -> B4 ledger.
-- Manual package only. Do not apply to production before rollout authorization.
begin;

do $$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
    or to_regclass('public.onexa_purchase_posting_runs') is null
    or to_regclass('public.onexa_business_documents') is null
    or to_regclass('public.onexa_business_document_lines') is null
    or to_regclass('public.onexa_business_document_events') is null
    or to_regclass('public.onexa_legal_entities') is null
    or to_regclass('public.onexa_account_role_mappings') is null
    or to_regclass('public.chart_of_accounts') is null
    or to_regprocedure('onexa_private.claim_tenant_id()') is null
    or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE40_FOUNDATION_REQUIRED';
  end if;
end;
$$;

create table if not exists public.onexa_supplier_payment_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  vendor_id uuid not null,
  journal_id uuid not null unique,
  amount numeric(20,4) not null check (amount > 0),
  source_revision integer not null check (source_revision > 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now()
);

create table if not exists public.onexa_supplier_payment_allocations (
  payment_id uuid not null references public.onexa_supplier_payment_postings(document_id) on delete restrict,
  invoice_id uuid not null references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  vendor_id uuid not null,
  amount numeric(20,4) not null check (amount > 0),
  primary key (payment_id, invoice_id)
);
create index if not exists onexa_supplier_payment_allocations_invoice_idx
  on public.onexa_supplier_payment_allocations(tenant_id, invoice_id);

alter table public.onexa_supplier_payment_postings enable row level security;
alter table public.onexa_supplier_payment_allocations enable row level security;
drop policy if exists onexa_supplier_payment_postings_read on public.onexa_supplier_payment_postings;
create policy onexa_supplier_payment_postings_read on public.onexa_supplier_payment_postings
  for select to authenticated using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'procurement', 'read')
  );
drop policy if exists onexa_supplier_payment_allocations_read on public.onexa_supplier_payment_allocations;
create policy onexa_supplier_payment_allocations_read on public.onexa_supplier_payment_allocations
  for select to authenticated using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'procurement', 'read')
  );

-- Liability reduction must have an immutable posted payment source and a
-- matching B4 journal. A stray allocation or unposted payment cannot suppress AP.
-- The lateral aggregate also avoids multiplying invoices by unrelated allocations.
create or replace view public.onexa_supplier_payables_reconciliation
with (security_invoker = true) as
select invoice.id as invoice_id, invoice.tenant_id, invoice.legal_entity_id,
  invoice.branch_id, invoice.party_id as vendor_id, invoice.document_number,
  invoice.currency, invoice.due_date, invoice.gross_total as invoiced_amount,
  coalesce(paid.paid_amount, 0)::numeric(20,4) as paid_amount,
  (invoice.gross_total - coalesce(paid.paid_amount, 0))::numeric(20,4) as outstanding_amount,
  case when invoice.status <> 'posted' then 'invoice_not_posted'
       when invoice.posted_journal_id is distinct from purchase_run.journal_id then 'invoice_journal_mismatch'
       when coalesce(paid.paid_amount, 0) > invoice.gross_total + 0.01 then 'overallocated'
       else 'reconciled' end as reconciliation_status
from public.onexa_business_documents invoice
left join public.onexa_purchase_posting_runs purchase_run
  on purchase_run.document_id = invoice.id
 and purchase_run.tenant_id = invoice.tenant_id
left join lateral (
  select coalesce(sum(allocation.amount), 0) as paid_amount
  from public.onexa_supplier_payment_allocations allocation
  join public.onexa_supplier_payment_postings posted_payment
    on posted_payment.document_id = allocation.payment_id
   and posted_payment.tenant_id = allocation.tenant_id
   and posted_payment.legal_entity_id = allocation.legal_entity_id
   and posted_payment.vendor_id = allocation.vendor_id
  join public.onexa_business_documents payment_document
    on payment_document.id = posted_payment.document_id
   and payment_document.tenant_id = posted_payment.tenant_id
   and payment_document.legal_entity_id = posted_payment.legal_entity_id
   and payment_document.party_type = 'vendor'
   and payment_document.party_id = posted_payment.vendor_id
   and payment_document.document_type = 'supplier_payment'
   and payment_document.module_key = 'procurement'
   and payment_document.status = 'posted'
   and payment_document.posted_journal_id = posted_payment.journal_id
  where allocation.invoice_id = invoice.id
    and allocation.tenant_id = invoice.tenant_id
    and allocation.legal_entity_id = invoice.legal_entity_id
    and allocation.vendor_id = invoice.party_id
) paid on true
where invoice.document_type = 'purchase_invoice';

create or replace view public.onexa_supplier_payment_configuration_gaps
with (security_invoker = true) as
with roles(account_role) as (values ('accounts_payable'::text), ('cash_or_bank'::text))
select entity.tenant_id, entity.id as legal_entity_id, entity.code as legal_entity_code,
  roles.account_role
from public.onexa_legal_entities entity cross join roles
left join public.onexa_account_role_mappings mapping
  on mapping.tenant_id = entity.tenant_id and mapping.legal_entity_id = entity.id
 and mapping.account_role = roles.account_role and mapping.is_active = true
where entity.is_active = true and mapping.id is null;

create or replace function public.onexa_post_supplier_payment(_document_id uuid, _period_code text)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _payment public.onexa_business_documents%rowtype;
  _invoice public.onexa_business_documents%rowtype;
  _allocation record;
  _allocation_total numeric(20,4) := 0;
  _allocated numeric(20,4);
  _cash text;
  _ap text;
  _journal uuid;
  _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant, '') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor, 'procurement', 'post') then
    raise exception 'ONEXA_PAYMENT_POST_NOT_AUTHORIZED';
  end if;
  if coalesce(btrim(_period_code), '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':payment:' || _document_id::text, 0));
  select * into _payment from public.onexa_business_documents
    where id = _document_id and tenant_id = _tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _payment.document_type <> 'supplier_payment' or _payment.module_key <> 'procurement' then
    raise exception 'ONEXA_SUPPLIER_PAYMENT_REQUIRED';
  end if;
  if _payment.status = 'posted' and _payment.posted_journal_id is not null then
    select journal_id into _journal from public.onexa_supplier_payment_postings
      where document_id = _payment.id and tenant_id = _tenant;
    if _journal is distinct from _payment.posted_journal_id then
      raise exception 'ONEXA_PAYMENT_RETRY_JOURNAL_MISMATCH';
    end if;
    return _journal;
  end if;
  if _payment.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _payment.created_by = _actor then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _payment.branch_id is null or _payment.party_type <> 'vendor' or _payment.party_id is null then
    raise exception 'ONEXA_PAYMENT_VENDOR_BRANCH_REQUIRED';
  end if;
  if _payment.gross_total <= 0 or _payment.tax_total <> 0 or _payment.discount_total <> 0
    or _payment.subtotal <> _payment.gross_total then
    raise exception 'ONEXA_PAYMENT_AMOUNT_INVALID';
  end if;
  if (select count(*) from public.onexa_business_document_lines where document_id = _payment.id) <> 1
    or not exists (
      select 1 from public.onexa_business_document_lines
      where document_id = _payment.id and tenant_id = _tenant
        and item_id is null and tax_amount = 0 and net_amount = _payment.gross_total
        and gross_amount = _payment.gross_total
    ) then raise exception 'ONEXA_PAYMENT_LINE_MISMATCH'; end if;
  if coalesce(
      jsonb_typeof(_payment.source_snapshot->'invoice_allocations'),
      ''
    ) <> 'array'
    or jsonb_array_length(_payment.source_snapshot->'invoice_allocations') = 0 then
    raise exception 'ONEXA_PAYMENT_ALLOCATIONS_REQUIRED';
  end if;
  if exists (
    select 1 from (
      select entry->>'invoice_id' as invoice_id
      from jsonb_array_elements(_payment.source_snapshot->'invoice_allocations') entry
      group by entry->>'invoice_id' having count(*) > 1
    ) duplicated
  ) then raise exception 'ONEXA_PAYMENT_DUPLICATE_INVOICE'; end if;

  -- Lock every invoice in stable order to serialize payments competing for its balance.
  for _allocation in
    select (entry->>'invoice_id')::uuid as invoice_id,
      (entry->>'amount')::numeric(20,4) as amount
    from jsonb_array_elements(_payment.source_snapshot->'invoice_allocations') entry
    order by (entry->>'invoice_id')::uuid
  loop
    if _allocation.amount is null or _allocation.amount <= 0 then
      raise exception 'ONEXA_PAYMENT_ALLOCATION_AMOUNT_INVALID';
    end if;
    select * into _invoice from public.onexa_business_documents
      where id = _allocation.invoice_id and tenant_id = _tenant for update;
    if not found or _invoice.document_type <> 'purchase_invoice' or _invoice.status <> 'posted'
      or _invoice.posted_journal_id is null
      or _invoice.party_type is distinct from 'vendor'
      or _invoice.legal_entity_id is distinct from _payment.legal_entity_id
      or _invoice.branch_id is distinct from _payment.branch_id
      or _invoice.party_id is distinct from _payment.party_id
      or _invoice.currency is distinct from _payment.currency then
      raise exception 'ONEXA_PAYMENT_INVOICE_MISMATCH';
    end if;
    perform 1 from public.onexa_purchase_posting_runs
      where document_id = _invoice.id and tenant_id = _tenant
        and journal_id = _invoice.posted_journal_id;
    if not found then raise exception 'ONEXA_PAYMENT_INVOICE_LEDGER_MISSING'; end if;
    select coalesce(sum(amount), 0) into _allocated
      from public.onexa_supplier_payment_allocations
      where tenant_id = _tenant and invoice_id = _invoice.id;
    if _allocated + _allocation.amount > _invoice.gross_total then
      raise exception 'ONEXA_PAYMENT_INVOICE_OVERPAYMENT';
    end if;
    _allocation_total := _allocation_total + _allocation.amount;
  end loop;
  if _allocation_total <> _payment.gross_total then
    raise exception 'ONEXA_PAYMENT_ALLOCATION_TOTAL_MISMATCH';
  end if;

  select mapping.account_code
  into _cash
  from public.onexa_account_role_mappings as mapping
  join public.chart_of_accounts as account
    on account.tenant_id = mapping.tenant_id
   and account.code = mapping.account_code
  where mapping.tenant_id = _tenant
    and mapping.legal_entity_id = _payment.legal_entity_id
    and mapping.account_role = 'cash_or_bank'
    and mapping.is_active = true
    and account.is_active = true
    and account.account_type::text = 'detail'
    and account.category::text = 'assets';

  select mapping.account_code
  into _ap
  from public.onexa_account_role_mappings as mapping
  join public.chart_of_accounts as account
    on account.tenant_id = mapping.tenant_id
   and account.code = mapping.account_code
  where mapping.tenant_id = _tenant
    and mapping.legal_entity_id = _payment.legal_entity_id
    and mapping.account_role = 'accounts_payable'
    and mapping.is_active = true
    and account.is_active = true
    and account.account_type::text = 'detail'
    and account.category::text = 'liabilities';
  if _cash is null or _ap is null then raise exception 'ONEXA_PAYMENT_ACCOUNT_MAPPING_REQUIRED'; end if;
  _dimensions := coalesce(_payment.dimensions, '{}'::jsonb) || jsonb_build_object(
    'legalEntity', _payment.legal_entity_id, 'branch', _payment.branch_id,
    'vendor', _payment.party_id
  );
  select public.onexa_post_journal(
    _legal_entity_id => _payment.legal_entity_id,
    _source_document_type => 'supplier_payment',
    _source_document_id => _payment.id::text,
    _source_revision => _payment.revision,
    _source_status => 'approved',
    _source_snapshot => coalesce(_payment.source_snapshot, '{}'::jsonb)
      || jsonb_build_object(
      'document_number', _payment.document_number,
      'posting_contract_version', 'supplier-payment-v1'),
    _accounting_date => _payment.accounting_date,
    _period_code => btrim(_period_code),
    _currency => _payment.currency,
    _memo => coalesce(_payment.memo, 'Supplier payment ' || _payment.document_number),
    _lines => jsonb_build_array(
      jsonb_build_object('account_code', _cash, 'debit', 0,
        'credit', _payment.gross_total, 'description', 'Cash or bank payment', 'dimensions', _dimensions),
      jsonb_build_object('account_code', _ap, 'debit', _payment.gross_total,
        'credit', 0, 'description', 'Accounts payable settlement',
        'dimensions', _dimensions)
    )
  )::uuid into _journal;
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  insert into public.onexa_supplier_payment_postings
    (document_id, tenant_id, legal_entity_id, vendor_id, journal_id, amount,
     source_revision, posted_by)
  values (_payment.id, _tenant, _payment.legal_entity_id, _payment.party_id,
    _journal, _payment.gross_total, _payment.revision, _actor);
  insert into public.onexa_supplier_payment_allocations
    (payment_id, invoice_id, tenant_id, legal_entity_id, vendor_id, amount)
  select _payment.id, (entry->>'invoice_id')::uuid, _tenant,
    _payment.legal_entity_id, _payment.party_id, (entry->>'amount')::numeric(20,4)
  from jsonb_array_elements(_payment.source_snapshot->'invoice_allocations') entry;

  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', 'posted_from_supplier_payment', true);
  update public.onexa_business_documents
    set status = 'posted', posted_by = _actor, posted_at = now(),
      posted_journal_id = _journal, posting_error = null
    where id = _payment.id and tenant_id = _tenant and status = 'approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id, document_id, event_type, from_status, to_status, actor_id, event_data)
  values (_tenant, _payment.id, 'posting_completed', 'approved', 'posted', _actor,
    jsonb_build_object('journal_id', _journal, 'posting_contract_version', 'supplier-payment-v1'));
  return _journal;
end;
$$;

revoke all on public.onexa_supplier_payment_postings from anon, authenticated;
revoke all on public.onexa_supplier_payment_allocations from anon, authenticated;
grant select on public.onexa_supplier_payment_postings to authenticated;
grant select on public.onexa_supplier_payment_allocations to authenticated;
grant select on public.onexa_supplier_payables_reconciliation to authenticated;
grant select on public.onexa_supplier_payment_configuration_gaps to authenticated;
revoke all on function public.onexa_post_supplier_payment(uuid,text) from public, anon;
grant execute on function public.onexa_post_supplier_payment(uuid,text) to authenticated;
commit;
