-- ONEXA Gate 41: approved bank transfer -> controlled treasury accounts -> B4 GL.
-- Manual database package; feature flag stays disabled until verified.
begin;

do $$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
    or to_regclass('public.onexa_business_documents') is null
    or to_regclass('public.onexa_journal_headers') is null
    or to_regclass('public.chart_of_accounts') is null
    or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE41_ACCOUNTING_FOUNDATION_REQUIRED';
  end if;
end;
$$;

create table if not exists public.onexa_treasury_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id) on delete restrict,
  branch_id uuid not null references public.onexa_branches(id) on delete restrict,
  account_code text not null,
  display_name text not null check (length(btrim(display_name)) > 0),
  currency text not null default 'SAR' check (currency = 'SAR'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, legal_entity_id, account_code)
);

create table if not exists public.onexa_bank_transfer_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  source_account_id uuid not null references public.onexa_treasury_accounts(id) on delete restrict,
  destination_account_id uuid not null references public.onexa_treasury_accounts(id) on delete restrict,
  amount numeric(20,4) not null check (amount > 0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision > 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  check (source_account_id <> destination_account_id)
);

create or replace function public.onexa_guard_posted_treasury_account()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if exists (select 1 from public.onexa_bank_transfer_postings posting
    where posting.source_account_id = old.id or posting.destination_account_id = old.id) then
    if tg_op = 'DELETE' then raise exception 'ONEXA_POSTED_TREASURY_ACCOUNT_IMMUTABLE'; end if;
    if new.tenant_id is distinct from old.tenant_id
      or new.legal_entity_id is distinct from old.legal_entity_id
      or new.branch_id is distinct from old.branch_id
      or new.account_code is distinct from old.account_code
      or new.currency is distinct from old.currency then
      raise exception 'ONEXA_POSTED_TREASURY_ACCOUNT_IMMUTABLE';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists onexa_guard_posted_treasury_account on public.onexa_treasury_accounts;
create trigger onexa_guard_posted_treasury_account
before update or delete on public.onexa_treasury_accounts
for each row execute function public.onexa_guard_posted_treasury_account();

alter table public.onexa_treasury_accounts enable row level security;
alter table public.onexa_bank_transfer_postings enable row level security;
drop policy if exists onexa_treasury_accounts_read on public.onexa_treasury_accounts;
create policy onexa_treasury_accounts_read on public.onexa_treasury_accounts
  for select to authenticated using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'finance', 'read')
  );
drop policy if exists onexa_bank_transfer_postings_read on public.onexa_bank_transfer_postings;
create policy onexa_bank_transfer_postings_read on public.onexa_bank_transfer_postings
  for select to authenticated using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'finance', 'read')
  );

create or replace view public.onexa_bank_transfer_reconciliation
with (security_invoker = true) as
select document.id as document_id, document.tenant_id, document.legal_entity_id,
  document.document_number, document.accounting_date, document.currency,
  document.status, document.gross_total as transfer_amount,
  posting.journal_id, posting.amount as posted_amount,
  source.account_code as source_account_code,
  destination.account_code as destination_account_code,
  case when document.status <> 'posted' then 'not_posted'
       when document.posted_journal_id is distinct from posting.journal_id then 'journal_mismatch'
       when journal.id is null then 'journal_reversed_or_missing'
       when journal.source_document_type is distinct from 'bank_transfer'
         or journal.source_document_id is distinct from document.id::text
         or journal.total_debit is distinct from document.gross_total
         or journal.total_credit is distinct from document.gross_total
         or journal.currency is distinct from document.currency
         then 'journal_source_or_amount_mismatch'
       when document.gross_total is distinct from posting.amount then 'amount_mismatch'
       when source.account_code is null or destination.account_code is null then 'account_missing'
       when source.legal_entity_id is distinct from document.legal_entity_id
         or destination.legal_entity_id is distinct from document.legal_entity_id
         or source.branch_id is distinct from document.branch_id
         or destination.branch_id is distinct from document.branch_id then 'account_scope_mismatch'
       else 'reconciled' end as reconciliation_status
from public.onexa_business_documents document
left join public.onexa_bank_transfer_postings posting
  on posting.document_id = document.id and posting.tenant_id = document.tenant_id
  and posting.legal_entity_id = document.legal_entity_id
left join public.onexa_journal_headers journal
  on journal.id = posting.journal_id
 and journal.tenant_id = document.tenant_id
 and journal.legal_entity_id = document.legal_entity_id
 and journal.state = 'posted'
 and journal.reversal_journal_id is null
left join public.onexa_treasury_accounts source on source.id = posting.source_account_id
  and source.tenant_id = document.tenant_id
left join public.onexa_treasury_accounts destination on destination.id = posting.destination_account_id
  and destination.tenant_id = document.tenant_id
where document.document_type = 'bank_transfer';

create or replace function public.onexa_post_bank_transfer(_document_id uuid, _period_code text)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  _tenant text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
  _source public.onexa_treasury_accounts%rowtype;
  _destination public.onexa_treasury_accounts%rowtype;
  _account public.onexa_treasury_accounts%rowtype;
  _source_id uuid;
  _destination_id uuid;
  _journal uuid;
  _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'post') then
    raise exception 'ONEXA_BANK_TRANSFER_POST_NOT_AUTHORIZED';
  end if;
  if coalesce(btrim(_period_code), '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'ONEXA_BANK_TRANSFER_PERIOD_REQUIRED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant || ':bank-transfer:' || _document_id::text, 0));
  select * into _document from public.onexa_business_documents
    where id = _document_id and tenant_id = _tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  if _document.document_type <> 'bank_transfer' or _document.module_key <> 'finance' then
    raise exception 'ONEXA_BANK_TRANSFER_DOCUMENT_REQUIRED';
  end if;
  if _document.status = 'posted' and _document.posted_journal_id is not null then
    select journal_id into _journal from public.onexa_bank_transfer_postings
      where document_id = _document.id and tenant_id = _tenant;
    if _journal is distinct from _document.posted_journal_id then
      raise exception 'ONEXA_BANK_TRANSFER_RETRY_JOURNAL_MISMATCH';
    end if;
    perform 1 from public.onexa_journal_headers
      where id = _journal and tenant_id = _tenant
        and legal_entity_id = _document.legal_entity_id
        and state = 'posted' and reversal_journal_id is null;
    if not found then raise exception 'ONEXA_BANK_TRANSFER_JOURNAL_REVERSED_OR_MISSING'; end if;
    return _journal;
  end if;
  if _document.status <> 'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _document.created_by = _actor then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _document.branch_id is null or _document.party_id is not null
    or _document.party_type is not null or _document.currency <> 'SAR'
    or _document.gross_total <= 0 or _document.tax_total <> 0
    or _document.discount_total <> 0 or _document.subtotal <> _document.gross_total then
    raise exception 'ONEXA_BANK_TRANSFER_DOCUMENT_INVALID';
  end if;
  if (select count(*) from public.onexa_business_document_lines
       where document_id = _document.id) <> 1 or not exists (
    select 1 from public.onexa_business_document_lines
    where document_id = _document.id and tenant_id = _tenant
      and item_id is null and tax_amount = 0
      and net_amount = _document.gross_total
      and gross_amount = _document.gross_total
  ) then raise exception 'ONEXA_BANK_TRANSFER_LINE_MISMATCH'; end if;
  if nullif(_document.source_snapshot->>'source_account_id', '') is null
    or nullif(_document.source_snapshot->>'destination_account_id', '') is null then
    raise exception 'ONEXA_BANK_TRANSFER_ACCOUNTS_REQUIRED';
  end if;
  _source_id := (_document.source_snapshot->>'source_account_id')::uuid;
  _destination_id := (_document.source_snapshot->>'destination_account_id')::uuid;
  if _source_id = _destination_id then raise exception 'ONEXA_BANK_TRANSFER_SAME_ACCOUNT'; end if;

  -- Consistent lock order for concurrent transfers that share accounts.
  for _account in select * from public.onexa_treasury_accounts
    where tenant_id = _tenant and id in (_source_id, _destination_id)
    order by id for update
  loop
    if _account.id = _source_id then _source := _account; end if;
    if _account.id = _destination_id then _destination := _account; end if;
  end loop;
  if _source.id is null or _destination.id is null
    or not _source.is_active or not _destination.is_active
    or _source.legal_entity_id is distinct from _document.legal_entity_id
    or _destination.legal_entity_id is distinct from _document.legal_entity_id
    or _source.branch_id is distinct from _document.branch_id
    or _destination.branch_id is distinct from _document.branch_id
    or _source.currency <> 'SAR' or _destination.currency <> 'SAR'
    or _source.account_code = _destination.account_code then
    raise exception 'ONEXA_BANK_TRANSFER_ACCOUNT_SCOPE_INVALID';
  end if;
  if (select count(*) from public.chart_of_accounts account
    where account.tenant_id = _tenant
      and account.code in (_source.account_code, _destination.account_code)
      and account.account_type::text = 'detail'
      and account.category::text = 'assets' and account.is_active) <> 2 then
    raise exception 'ONEXA_BANK_TRANSFER_CONTROL_ACCOUNT_INVALID';
  end if;

  _dimensions := _document.dimensions || jsonb_build_object(
    'legalEntity', _document.legal_entity_id, 'branch', _document.branch_id
  );
  select public.onexa_post_journal(
    _legal_entity_id => _document.legal_entity_id,
    _source_document_type => 'bank_transfer',
    _source_document_id => _document.id::text,
    _source_revision => _document.revision,
    _source_status => 'approved',
    _source_snapshot => _document.source_snapshot || jsonb_build_object(
      'document_number', _document.document_number,
      'source_account_code', _source.account_code,
      'destination_account_code', _destination.account_code,
      'posting_contract_version', 'bank-transfer-v1'),
    _accounting_date => _document.accounting_date,
    _period_code => btrim(_period_code),
    _currency => 'SAR',
    _memo => coalesce(_document.memo, 'Bank transfer ' || _document.document_number),
    _lines => jsonb_build_array(
      jsonb_build_object('account_code', _destination.account_code,
        'debit', _document.gross_total, 'credit', 0,
        'description', 'Destination bank transfer',
        'dimensions', _dimensions || jsonb_build_object('bankAccount', _destination.id)),
      jsonb_build_object('account_code', _source.account_code,
        'debit', 0, 'credit', _document.gross_total,
        'description', 'Source bank transfer',
        'dimensions', _dimensions || jsonb_build_object('bankAccount', _source.id))
    )
  )::uuid into _journal;
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;
  insert into public.onexa_bank_transfer_postings
    (document_id, tenant_id, legal_entity_id, source_account_id,
     destination_account_id, amount, journal_id, source_revision, posted_by)
  values (_document.id, _tenant, _document.legal_entity_id, _source.id,
    _destination.id, _document.gross_total, _journal, _document.revision, _actor);
  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', 'posted_from_bank_transfer', true);
  update public.onexa_business_documents
    set status = 'posted', posted_by = _actor, posted_at = now(),
      posted_journal_id = _journal, posting_error = null
    where id = _document.id and tenant_id = _tenant and status = 'approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events
    (tenant_id, document_id, event_type, from_status, to_status, actor_id, event_data)
  values (_tenant, _document.id, 'posting_completed', 'approved', 'posted', _actor,
    jsonb_build_object('journal_id', _journal, 'posting_contract_version', 'bank-transfer-v1'));
  return _journal;
end;
$$;

revoke all on public.onexa_treasury_accounts from anon, authenticated;
revoke all on public.onexa_bank_transfer_postings from anon, authenticated;
grant select on public.onexa_treasury_accounts to authenticated;
grant select on public.onexa_bank_transfer_postings to authenticated;
grant select on public.onexa_bank_transfer_reconciliation to authenticated;
revoke all on function public.onexa_post_bank_transfer(uuid,text) from public, anon;
grant execute on function public.onexa_post_bank_transfer(uuid,text) to authenticated;
revoke all on function public.onexa_guard_posted_treasury_account() from public, anon, authenticated;
commit;
