-- ONEXA Gate 67: tenant lease schedule -> lease invoice -> lease receipt -> GL.
-- Manual rollout only. Legacy public.invoices/payments are not reposted.
begin;

do $preflight$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null
     or to_regclass('public.onexa_business_documents') is null
     or to_regclass('public.re_tenant_leases') is null
     or to_regclass('public.re_lease_schedules') is null
     or to_regprocedure('public.re_has_company_access(uuid)') is null then
    raise exception 'ONEXA_GATE67_FOUNDATION_REQUIRED';
  end if;
  if to_regprocedure('public.onexa_approval_separation_required(text,text)') is null
     or to_regprocedure('onexa_private.guard_approval_posting()') is null then
    raise exception 'ONEXA_GATE64_APPROVAL_POSTING_BRIDGE_REQUIRED';
  end if;
end;
$preflight$;

create table if not exists public.onexa_lease_accounting_scopes (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  tenant_lease_id uuid not null unique references public.re_tenant_leases(id) on delete restrict,
  property_id uuid not null references public.re_properties(id) on delete restrict,
  is_active boolean not null default true,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,legal_entity_id,tenant_lease_id)
);

create table if not exists public.onexa_lease_invoice_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  scope_id uuid not null references public.onexa_lease_accounting_scopes(id) on delete restrict,
  schedule_id uuid not null unique references public.re_lease_schedules(id) on delete restrict,
  tenant_lease_id uuid not null references public.re_tenant_leases(id) on delete restrict,
  property_id uuid not null references public.re_properties(id) on delete restrict,
  customer_id uuid not null,
  external_reference text not null check (length(btrim(external_reference))>0),
  net_amount numeric(20,4) not null check (net_amount>0),
  tax_amount numeric(20,4) not null check (tax_amount>=0),
  gross_amount numeric(20,4) not null check (gross_amount>0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision>0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  constraint onexa_lease_invoice_postings_math check (abs(gross_amount-(net_amount+tax_amount))<=0.01),
  unique (tenant_id,legal_entity_id,external_reference)
);

create table if not exists public.onexa_lease_receipt_postings (
  document_id uuid primary key references public.onexa_business_documents(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  invoice_id uuid not null references public.onexa_lease_invoice_postings(document_id) on delete restrict,
  property_id uuid not null references public.re_properties(id) on delete restrict,
  customer_id uuid not null,
  external_reference text not null check (length(btrim(external_reference))>0),
  amount numeric(20,4) not null check (amount>0),
  journal_id uuid not null unique,
  source_revision integer not null check (source_revision>0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  unique (tenant_id,legal_entity_id,external_reference)
);

create index if not exists onexa_lease_invoice_customer_idx
  on public.onexa_lease_invoice_postings(tenant_id,customer_id,posted_at desc);
create index if not exists onexa_lease_receipt_invoice_idx
  on public.onexa_lease_receipt_postings(tenant_id,invoice_id,posted_at desc);

create or replace function public.onexa_guard_posted_lease_scope()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if exists (select 1 from public.onexa_lease_invoice_postings p where p.scope_id=old.id) then
    if tg_op='DELETE' then raise exception 'ONEXA_POSTED_LEASE_SCOPE_IMMUTABLE'; end if;
    if row(new.tenant_id,new.legal_entity_id,new.branch_id,new.tenant_lease_id,new.property_id)
       is distinct from row(old.tenant_id,old.legal_entity_id,old.branch_id,old.tenant_lease_id,old.property_id) then
      raise exception 'ONEXA_POSTED_LEASE_SCOPE_IMMUTABLE';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  new.updated_at:=now();
  return new;
end;
$$;
drop trigger if exists onexa_guard_posted_lease_scope on public.onexa_lease_accounting_scopes;
create trigger onexa_guard_posted_lease_scope before update or delete
on public.onexa_lease_accounting_scopes for each row execute function public.onexa_guard_posted_lease_scope();

alter table public.onexa_lease_accounting_scopes enable row level security;
alter table public.onexa_lease_invoice_postings enable row level security;
alter table public.onexa_lease_receipt_postings enable row level security;

drop policy if exists onexa_lease_accounting_scopes_read on public.onexa_lease_accounting_scopes;
create policy onexa_lease_accounting_scopes_read on public.onexa_lease_accounting_scopes
for select to authenticated using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'facilities','read'));
drop policy if exists onexa_lease_invoice_postings_read on public.onexa_lease_invoice_postings;
create policy onexa_lease_invoice_postings_read on public.onexa_lease_invoice_postings
for select to authenticated using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'facilities','read'));
drop policy if exists onexa_lease_receipt_postings_read on public.onexa_lease_receipt_postings;
create policy onexa_lease_receipt_postings_read on public.onexa_lease_receipt_postings
for select to authenticated using (tenant_id=onexa_private.claim_tenant_id()
  and onexa_private.has_module_action(auth.uid(),'facilities','read'));

create or replace function public.onexa_save_lease_accounting_scope(_tenant_lease_id uuid,_branch_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _lease public.re_tenant_leases%rowtype;
  _entity uuid;
  _property uuid;
  _scope uuid;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'facilities','create') then
    raise exception 'ONEXA_LEASE_SCOPE_NOT_AUTHORIZED'; end if;
  select * into _lease from public.re_tenant_leases where id=_tenant_lease_id for update;
  if not found or not public.re_has_company_access(_lease.company_id) then
    raise exception 'ONEXA_TENANT_LEASE_NOT_ACCESSIBLE'; end if;
  if _lease.status not in ('approved','active') then raise exception 'ONEXA_TENANT_LEASE_MUST_BE_APPROVED_OR_ACTIVE'; end if;
  select property.id into _property
  from public.re_units unit join public.re_buildings building on building.id=unit.building_id
  join public.re_properties property on property.id=building.property_id
  where unit.id=_lease.unit_id and property.company_id=_lease.company_id and property.status='active'
    and property.ownership_model in ('owned','leased_in');
  if _property is null then raise exception 'ONEXA_ACTIVE_LEASE_PROPERTY_REQUIRED'; end if;
  select branch.legal_entity_id into _entity from public.onexa_branches branch
  join public.onexa_legal_entities entity on entity.id=branch.legal_entity_id
  where branch.id=_branch_id and branch.tenant_id=_tenant and branch.is_active
    and entity.tenant_id=_tenant and entity.is_active;
  if _entity is null then raise exception 'ONEXA_ACTIVE_LEGAL_ENTITY_BRANCH_REQUIRED'; end if;
  insert into public.onexa_lease_accounting_scopes
    (tenant_id,legal_entity_id,branch_id,tenant_lease_id,property_id,created_by)
  values (_tenant,_entity,_branch_id,_lease.id,_property,_actor)
  on conflict (tenant_lease_id) do update set tenant_id=excluded.tenant_id,
    legal_entity_id=excluded.legal_entity_id,branch_id=excluded.branch_id,
    property_id=excluded.property_id,is_active=true,updated_at=now()
  where public.onexa_lease_accounting_scopes.tenant_id=excluded.tenant_id
  returning id into _scope;
  if _scope is null then raise exception 'ONEXA_LEASE_ALREADY_SCOPED_TO_ANOTHER_TENANT'; end if;
  return _scope;
end;
$$;

create or replace view public.onexa_lease_accounting_scope_details with (security_invoker=true) as
select scope.id,scope.tenant_id,scope.legal_entity_id,scope.branch_id,branch.code as branch_code,
  scope.tenant_lease_id,lease.lease_no,lease.customer_id,customer.name as customer_name,
  lease.contract_id,scope.property_id,property.property_code,property.name_ar as property_name,
  unit.id as unit_id,unit.unit_code,scope.is_active
from public.onexa_lease_accounting_scopes scope
join public.onexa_branches branch on branch.id=scope.branch_id and branch.tenant_id=scope.tenant_id
join public.re_tenant_leases lease on lease.id=scope.tenant_lease_id
join public.customers customer on customer.id=lease.customer_id
join public.re_units unit on unit.id=lease.unit_id
join public.re_buildings building on building.id=unit.building_id
join public.re_properties property on property.id=building.property_id and property.id=scope.property_id
where scope.is_active and branch.is_active and property.status='active'
  and property.ownership_model in ('owned','leased_in')
  and lease.status in ('approved','active');

create or replace view public.onexa_lease_billing_candidates with (security_invoker=true) as
select detail.*,schedule.id as schedule_id,schedule.due_date,schedule.period_start,
  schedule.period_end,schedule.amount::numeric(20,4) as net_amount
from public.onexa_lease_accounting_scope_details detail
join public.re_lease_schedules schedule on schedule.tenant_lease_id=detail.tenant_lease_id
where schedule.status='pending' and schedule.invoice_id is null and schedule.amount>0
  and not exists (select 1 from public.onexa_lease_invoice_postings posted
    where posted.schedule_id=schedule.id and posted.tenant_id=detail.tenant_id);

create or replace view public.onexa_lease_receivables_reconciliation with (security_invoker=true) as
select invoice.id as invoice_id,invoice.tenant_id,invoice.legal_entity_id,invoice.branch_id,
  invoice.party_id as customer_id,invoice.party_name_snapshot as customer_name,
  invoice.document_number,invoice.currency,invoice.due_date,posting.property_id,
  property.property_code,invoice.gross_total::numeric(20,4) as invoiced_amount,
  coalesce(sum(receipt.amount),0)::numeric(20,4) as collected_amount,
  (invoice.gross_total-coalesce(sum(receipt.amount),0))::numeric(20,4) as outstanding_amount,
  case when invoice.status<>'posted' then 'invoice_not_posted'
    when invoice.posted_journal_id is distinct from posting.journal_id then 'invoice_journal_mismatch'
    when coalesce(sum(receipt.amount),0)>invoice.gross_total then 'overallocated'
    else 'reconciled' end as reconciliation_status
from public.onexa_business_documents invoice
join public.onexa_lease_invoice_postings posting on posting.document_id=invoice.id
  and posting.tenant_id=invoice.tenant_id
join public.re_properties property on property.id=posting.property_id
left join public.onexa_lease_receipt_postings receipt on receipt.invoice_id=invoice.id
  and receipt.tenant_id=invoice.tenant_id
where invoice.document_type='lease_invoice'
group by invoice.id,posting.property_id,posting.journal_id,property.property_code;

create or replace view public.onexa_lease_accounting_reconciliation with (security_invoker=true) as
select document.id as document_id,document.tenant_id,document.document_type,
  document.document_number,document.status,document.gross_total,document.posted_journal_id,
  coalesce(invoice_posting.journal_id,receipt_posting.journal_id) as run_journal_id,
  case when document.status<>'posted' then 'not_posted'
    when document.posted_journal_id is distinct from coalesce(invoice_posting.journal_id,receipt_posting.journal_id) then 'journal_mismatch'
    else 'reconciled' end as reconciliation_status
from public.onexa_business_documents document
left join public.onexa_lease_invoice_postings invoice_posting on invoice_posting.document_id=document.id
left join public.onexa_lease_receipt_postings receipt_posting on receipt_posting.document_id=document.id
where document.document_type in ('lease_invoice','lease_receipt');

create or replace view public.onexa_lease_posting_configuration_gaps with (security_invoker=true) as
with roles(account_role) as (values ('accounts_receivable'::text),('rental_revenue'::text),
  ('output_vat'::text),('cash_or_bank'::text))
select entity.tenant_id,entity.id as legal_entity_id,entity.code as legal_entity_code,roles.account_role
from public.onexa_legal_entities entity cross join roles
left join public.onexa_account_role_mappings mapping on mapping.tenant_id=entity.tenant_id
 and mapping.legal_entity_id=entity.id and mapping.account_role=roles.account_role and mapping.is_active
where entity.is_active and mapping.id is null;

create or replace function public.onexa_post_lease_invoice(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id(); _actor uuid:=auth.uid();
  _document public.onexa_business_documents%rowtype; _line public.onexa_business_document_lines%rowtype;
  _scope public.onexa_lease_accounting_scopes%rowtype; _lease public.re_tenant_leases%rowtype;
  _schedule public.re_lease_schedules%rowtype; _posting public.onexa_lease_invoice_postings%rowtype;
  _ar text; _revenue text; _vat text; _reference text; _journal uuid; _property_id uuid;
  _lines jsonb; _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'facilities','post') then raise exception 'ONEXA_LEASE_INVOICE_POST_NOT_AUTHORIZED'; end if;
  if coalesce(btrim(_period_code),'')!~'^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant||':lease-invoice:'||_document_id::text,0));
  select * into _document from public.onexa_business_documents where id=_document_id and tenant_id=_tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  select * into _posting from public.onexa_lease_invoice_postings where document_id=_document.id and tenant_id=_tenant;
  if _document.status='posted' then
    if _document.posted_journal_id is not null and _posting.journal_id is not distinct from _document.posted_journal_id then return _document.posted_journal_id; end if;
    raise exception 'ONEXA_LEASE_INVOICE_RETRY_STATE_INVALID';
  end if;
  if _document.document_type<>'lease_invoice' or _document.module_key<>'facilities' then raise exception 'ONEXA_LEASE_INVOICE_REQUIRED'; end if;
  if _document.status<>'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _actor=_document.created_by and public.onexa_approval_separation_required(_document.document_type,'post') then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _document.branch_id is null or _document.currency<>'SAR' or _document.party_type<>'customer'
    or _document.party_id is null or _document.origin<>'native' or _document.gross_total<=0
    or _document.discount_total<>0 or _document.subtotal<=0
    or abs(_document.gross_total-(_document.subtotal+_document.tax_total))>0.01 then
    raise exception 'ONEXA_LEASE_INVOICE_DOCUMENT_INVALID'; end if;
  select * into _line from public.onexa_business_document_lines where document_id=_document.id and tenant_id=_tenant;
  if not found or (select count(*) from public.onexa_business_document_lines where document_id=_document.id)<>1
    or _line.item_id is not null or _line.account_role is distinct from 'rental_revenue'
    or _line.tax_code not in ('VAT15','EXEMPT')
    or (_line.tax_code='VAT15' and (_line.tax_rate<>0.15 or abs(_line.tax_amount-round(_line.net_amount*0.15,2))>0.01))
    or (_line.tax_code='EXEMPT' and (_line.tax_rate<>0 or _line.tax_amount<>0))
    or abs(_line.net_amount-_document.subtotal)>0.01 or abs(_line.tax_amount-_document.tax_total)>0.01
    or abs(_line.gross_amount-_document.gross_total)>0.01 then raise exception 'ONEXA_LEASE_INVOICE_LINE_MISMATCH'; end if;
  if _document.source_snapshot->>'source_kind' is distinct from 'tenant_lease_schedule' then raise exception 'ONEXA_LEASE_INVOICE_SOURCE_INVALID'; end if;
  select * into _scope from public.onexa_lease_accounting_scopes
    where id=(_document.source_snapshot->>'lease_scope_id')::uuid and tenant_id=_tenant for update;
  if not found or not _scope.is_active or _scope.legal_entity_id is distinct from _document.legal_entity_id
    or _scope.branch_id is distinct from _document.branch_id then raise exception 'ONEXA_LEASE_SCOPE_INVALID'; end if;
  select * into _lease from public.re_tenant_leases where id=_scope.tenant_lease_id for update;
  select * into _schedule from public.re_lease_schedules
    where id=(_document.source_snapshot->>'schedule_id')::uuid and tenant_lease_id=_scope.tenant_lease_id for update;
  select property.id into _property_id from public.re_units unit
  join public.re_buildings building on building.id=unit.building_id
  join public.re_properties property on property.id=building.property_id
  where unit.id=_lease.unit_id and property.company_id=_lease.company_id
    and property.status='active' and property.ownership_model in ('owned','leased_in');
  if _lease.id is null or _schedule.id is null or _property_id is distinct from _scope.property_id
    or _lease.status not in ('approved','active')
    or _schedule.status<>'pending' or _schedule.invoice_id is not null or not public.re_has_company_access(_lease.company_id)
    or _document.party_id is distinct from _lease.customer_id
    or _document.source_snapshot->>'tenant_lease_id' is distinct from _lease.id::text
    or _document.source_snapshot->>'property_id' is distinct from _scope.property_id::text
    or _document.dimensions->>'property' is distinct from _scope.property_id::text
    or _document.dimensions->>'customer' is distinct from _lease.customer_id::text
    or abs(_document.subtotal-_schedule.amount)>0.01
    or _document.due_date is distinct from greatest(_schedule.due_date,_document.document_date) then
    raise exception 'ONEXA_LEASE_SCHEDULE_DOCUMENT_MISMATCH'; end if;
  if exists (select 1 from public.onexa_lease_invoice_postings where schedule_id=_schedule.id) then raise exception 'ONEXA_LEASE_SCHEDULE_ALREADY_POSTED'; end if;
  _reference:=nullif(btrim(_document.external_reference),'');
  if _reference is null then raise exception 'ONEXA_LEASE_INVOICE_EXTERNAL_REFERENCE_REQUIRED'; end if;
  if exists (select 1 from public.onexa_lease_invoice_postings where tenant_id=_tenant
    and legal_entity_id=_document.legal_entity_id and external_reference=_reference) then raise exception 'ONEXA_LEASE_INVOICE_REFERENCE_ALREADY_POSTED'; end if;
  select account_code into _ar from public.onexa_account_role_mappings where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id and account_role='accounts_receivable' and is_active;
  select account_code into _revenue from public.onexa_account_role_mappings where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id and account_role='rental_revenue' and is_active;
  select account_code into _vat from public.onexa_account_role_mappings where tenant_id=_tenant and legal_entity_id=_document.legal_entity_id and account_role='output_vat' and is_active;
  if _ar is null or _revenue is null or (_document.tax_total>0 and _vat is null) then raise exception 'ONEXA_LEASE_INVOICE_ACCOUNT_MAPPING_REQUIRED'; end if;
  if not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant and code=_ar and is_active and account_type::text='detail' and category::text='assets')
    or not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant and code=_revenue and is_active and account_type::text='detail' and category::text='revenue')
    or (_document.tax_total>0 and not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant and code=_vat and is_active and account_type::text='detail' and category::text='liabilities')) then
    raise exception 'ONEXA_LEASE_INVOICE_ACCOUNT_MAPPING_INVALID'; end if;
  _dimensions:=_document.dimensions||jsonb_build_object('legalEntity',_document.legal_entity_id,'branch',_document.branch_id,'customer',_document.party_id,'property',_scope.property_id);
  _lines:=jsonb_build_array(
    jsonb_build_object('account_code',_ar,'debit',_document.gross_total,'credit',0,'description','Lease receivable - '||_document.document_number,'dimensions',_dimensions),
    jsonb_build_object('account_code',_revenue,'debit',0,'credit',_document.subtotal,'description','Rental revenue - '||_document.document_number,'dimensions',_dimensions));
  if _document.tax_total>0 then _lines:=_lines||jsonb_build_array(jsonb_build_object('account_code',_vat,'debit',0,'credit',_document.tax_total,'description','Lease output VAT - '||_document.document_number,'dimensions',_dimensions)); end if;
  _journal:=public.onexa_post_journal(_document.legal_entity_id,'lease_invoice',_document.id::text,
    _document.revision,'approved',_document.source_snapshot||jsonb_build_object('document_number',_document.document_number,'external_reference',_reference,'posting_contract_version','lease-invoice-v1'),
    _document.accounting_date,btrim(_period_code),_document.currency,coalesce(_document.memo,'Lease invoice '||_document.document_number),_lines);
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;
  insert into public.onexa_lease_invoice_postings(document_id,tenant_id,legal_entity_id,scope_id,schedule_id,tenant_lease_id,property_id,customer_id,external_reference,net_amount,tax_amount,gross_amount,journal_id,source_revision,posted_by)
  values (_document.id,_tenant,_document.legal_entity_id,_scope.id,_schedule.id,_lease.id,_scope.property_id,_lease.customer_id,_reference,_document.subtotal,_document.tax_total,_document.gross_total,_journal,_document.revision,_actor);
  perform set_config('onexa.transition_authorized','true',true); perform set_config('onexa.transition_reason','posted_from_lease_invoice',true);
  update public.onexa_business_documents set status='posted',posted_by=_actor,posted_at=now(),posted_journal_id=_journal,posting_error=null where id=_document.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events(tenant_id,document_id,event_type,from_status,to_status,actor_id,event_data)
  values (_tenant,_document.id,'posting_completed','approved','posted',_actor,jsonb_build_object('journal_id',_journal,'schedule_id',_schedule.id,'posting_contract_version','lease-invoice-v1'));
  return _journal;
end;
$$;

create or replace function public.onexa_post_lease_receipt(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id(); _actor uuid:=auth.uid();
  _receipt public.onexa_business_documents%rowtype; _invoice public.onexa_business_documents%rowtype;
  _invoice_run public.onexa_lease_invoice_postings%rowtype; _run public.onexa_lease_receipt_postings%rowtype;
  _allocated numeric(20,4); _cash text; _ar text; _reference text; _journal uuid; _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant,'') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if not onexa_private.has_module_action(_actor,'facilities','post') then raise exception 'ONEXA_LEASE_RECEIPT_POST_NOT_AUTHORIZED'; end if;
  if coalesce(btrim(_period_code),'')!~'^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant||':lease-receipt:'||_document_id::text,0));
  select * into _receipt from public.onexa_business_documents where id=_document_id and tenant_id=_tenant for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;
  select * into _run from public.onexa_lease_receipt_postings where document_id=_receipt.id and tenant_id=_tenant;
  if _receipt.status='posted' then
    if _receipt.posted_journal_id is not null and _run.journal_id is not distinct from _receipt.posted_journal_id then return _receipt.posted_journal_id; end if;
    raise exception 'ONEXA_LEASE_RECEIPT_RETRY_STATE_INVALID';
  end if;
  if _receipt.document_type<>'lease_receipt' or _receipt.module_key<>'facilities' then raise exception 'ONEXA_LEASE_RECEIPT_REQUIRED'; end if;
  if _receipt.status<>'approved' then raise exception 'ONEXA_DOCUMENT_MUST_BE_APPROVED'; end if;
  if _actor=_receipt.created_by and public.onexa_approval_separation_required(_receipt.document_type,'post') then raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR'; end if;
  if _receipt.branch_id is null or _receipt.party_type<>'customer' or _receipt.party_id is null
    or _receipt.origin<>'native' or _receipt.gross_total<=0 or _receipt.tax_total<>0
    or _receipt.discount_total<>0 or _receipt.subtotal<>_receipt.gross_total then raise exception 'ONEXA_LEASE_RECEIPT_DOCUMENT_INVALID'; end if;
  if (select count(*) from public.onexa_business_document_lines where document_id=_receipt.id)<>1
    or not exists (select 1 from public.onexa_business_document_lines where document_id=_receipt.id and tenant_id=_tenant
      and item_id is null and tax_amount=0 and net_amount=_receipt.gross_total and gross_amount=_receipt.gross_total) then raise exception 'ONEXA_LEASE_RECEIPT_LINE_MISMATCH'; end if;
  if _receipt.source_snapshot->>'source_kind' is distinct from 'lease_invoice_collection' then raise exception 'ONEXA_LEASE_RECEIPT_SOURCE_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_tenant||':lease-invoice-allocation:'||(_receipt.source_snapshot->>'lease_invoice_id'),0));
  select * into _invoice from public.onexa_business_documents where id=(_receipt.source_snapshot->>'lease_invoice_id')::uuid and tenant_id=_tenant for update;
  select * into _invoice_run from public.onexa_lease_invoice_postings where document_id=_invoice.id and tenant_id=_tenant;
  if _invoice.id is null or _invoice_run.document_id is null or _invoice.status<>'posted'
    or _invoice.posted_journal_id is distinct from _invoice_run.journal_id
    or _invoice.legal_entity_id is distinct from _receipt.legal_entity_id
    or _invoice.branch_id is distinct from _receipt.branch_id or _invoice.party_id is distinct from _receipt.party_id
    or _invoice.currency is distinct from _receipt.currency
    or _receipt.dimensions->>'property' is distinct from _invoice_run.property_id::text
    or _receipt.dimensions->>'customer' is distinct from _invoice_run.customer_id::text then raise exception 'ONEXA_LEASE_RECEIPT_INVOICE_MISMATCH'; end if;
  select coalesce(sum(amount),0) into _allocated from public.onexa_lease_receipt_postings where tenant_id=_tenant and invoice_id=_invoice.id;
  if _allocated+_receipt.gross_total>_invoice.gross_total then raise exception 'ONEXA_LEASE_RECEIPT_OVERPAYMENT'; end if;
  _reference:=nullif(btrim(_receipt.external_reference),'');
  if _reference is null then raise exception 'ONEXA_LEASE_RECEIPT_EXTERNAL_REFERENCE_REQUIRED'; end if;
  if exists (select 1 from public.onexa_lease_receipt_postings where tenant_id=_tenant and legal_entity_id=_receipt.legal_entity_id and external_reference=_reference) then raise exception 'ONEXA_LEASE_RECEIPT_REFERENCE_ALREADY_POSTED'; end if;
  select account_code into _cash from public.onexa_account_role_mappings where tenant_id=_tenant and legal_entity_id=_receipt.legal_entity_id and account_role='cash_or_bank' and is_active;
  select account_code into _ar from public.onexa_account_role_mappings where tenant_id=_tenant and legal_entity_id=_receipt.legal_entity_id and account_role='accounts_receivable' and is_active;
  if _cash is null or _ar is null or not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant and code=_cash and is_active and account_type::text='detail' and category::text='assets')
    or not exists (select 1 from public.chart_of_accounts where tenant_id=_tenant and code=_ar and is_active and account_type::text='detail' and category::text='assets') then raise exception 'ONEXA_LEASE_RECEIPT_ACCOUNT_MAPPING_REQUIRED'; end if;
  _dimensions:=_receipt.dimensions||jsonb_build_object('legalEntity',_receipt.legal_entity_id,'branch',_receipt.branch_id,'customer',_receipt.party_id,'property',_invoice_run.property_id);
  _journal:=public.onexa_post_journal(_receipt.legal_entity_id,'lease_receipt',_receipt.id::text,
    _receipt.revision,'approved',_receipt.source_snapshot||jsonb_build_object('document_number',_receipt.document_number,'external_reference',_reference,'posting_contract_version','lease-receipt-v1'),
    _receipt.accounting_date,btrim(_period_code),_receipt.currency,coalesce(_receipt.memo,'Lease receipt '||_receipt.document_number),
    jsonb_build_array(
      jsonb_build_object('account_code',_cash,'debit',_receipt.gross_total,'credit',0,'description','Lease collection - '||_receipt.document_number,'dimensions',_dimensions),
      jsonb_build_object('account_code',_ar,'debit',0,'credit',_receipt.gross_total,'description','Lease receivable settlement - '||_invoice.document_number,'dimensions',_dimensions)));
  if _journal is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;
  insert into public.onexa_lease_receipt_postings(document_id,tenant_id,legal_entity_id,invoice_id,property_id,customer_id,external_reference,amount,journal_id,source_revision,posted_by)
  values (_receipt.id,_tenant,_receipt.legal_entity_id,_invoice.id,_invoice_run.property_id,_receipt.party_id,_reference,_receipt.gross_total,_journal,_receipt.revision,_actor);
  perform set_config('onexa.transition_authorized','true',true); perform set_config('onexa.transition_reason','posted_from_lease_receipt',true);
  update public.onexa_business_documents set status='posted',posted_by=_actor,posted_at=now(),posted_journal_id=_journal,posting_error=null where id=_receipt.id and tenant_id=_tenant and status='approved';
  if not found then raise exception 'ONEXA_DOCUMENT_POST_STATUS_UPDATE_FAILED'; end if;
  insert into public.onexa_business_document_events(tenant_id,document_id,event_type,from_status,to_status,actor_id,event_data)
  values (_tenant,_receipt.id,'posting_completed','approved','posted',_actor,jsonb_build_object('journal_id',_journal,'lease_invoice_id',_invoice.id,'posting_contract_version','lease-receipt-v1'));
  return _journal;
end;
$$;

revoke all on public.onexa_lease_accounting_scopes,public.onexa_lease_invoice_postings,
  public.onexa_lease_receipt_postings from anon,authenticated;
grant select on public.onexa_lease_accounting_scopes,public.onexa_lease_invoice_postings,
  public.onexa_lease_receipt_postings to authenticated;
grant select on public.onexa_lease_accounting_scope_details,public.onexa_lease_billing_candidates,
  public.onexa_lease_receivables_reconciliation,public.onexa_lease_accounting_reconciliation,
  public.onexa_lease_posting_configuration_gaps to authenticated;
revoke all on function public.onexa_save_lease_accounting_scope(uuid,uuid) from public,anon;
grant execute on function public.onexa_save_lease_accounting_scope(uuid,uuid) to authenticated;
revoke all on function public.onexa_post_lease_invoice(uuid,text),public.onexa_post_lease_receipt(uuid,text) from public,anon;
grant execute on function public.onexa_post_lease_invoice(uuid,text),public.onexa_post_lease_receipt(uuid,text) to authenticated;
revoke all on function public.onexa_guard_posted_lease_scope() from public,anon,authenticated;
commit;
