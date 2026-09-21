-- ONEXA Gate 34: accounting-first business document foundation.
--
-- This migration extends the verified B1/B4 workspace and ledger foundation.
-- It does not recreate journal tables or posting functions. Approved financial
-- documents continue to post only through public.onexa_post_journal.

begin;

create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.onexa_document_sequences (
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  document_type text not null,
  fiscal_year integer not null check (fiscal_year between 2000 and 2200),
  prefix text not null check (prefix ~ '^[A-Z0-9-]{1,12}$'),
  next_number bigint not null default 1 check (next_number > 0),
  padding smallint not null default 6 check (padding between 4 and 12),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, legal_entity_id, document_type, fiscal_year)
);

create table if not exists public.onexa_business_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid references public.onexa_branches(id),
  module_key text not null check (module_key in (
    'finance', 'sales', 'procurement', 'inventory', 'projects',
    'facilities', 'logistics', 'assets', 'people'
  )),
  document_type text not null,
  document_number text not null,
  document_date date not null,
  accounting_date date not null,
  due_date date,
  status text not null default 'draft' check (status in (
    'draft', 'submitted', 'approved', 'posted', 'rejected', 'cancelled', 'reversed'
  )),
  revision integer not null default 1 check (revision > 0),
  currency text not null default 'SAR' check (currency ~ '^[A-Z]{3}$'),
  party_type text check (party_type in ('customer', 'vendor', 'employee', 'other')),
  party_id uuid,
  party_name_snapshot text,
  external_reference text,
  origin text not null default 'native' check (origin in ('native', 'import', 'api')),
  import_batch_id uuid,
  subtotal numeric(20, 4) not null default 0 check (subtotal >= 0),
  discount_total numeric(20, 4) not null default 0 check (discount_total >= 0),
  tax_total numeric(20, 4) not null default 0 check (tax_total >= 0),
  gross_total numeric(20, 4) not null default 0 check (gross_total >= 0),
  dimensions jsonb not null default '{}'::jsonb check (jsonb_typeof(dimensions) = 'object'),
  source_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(source_snapshot) = 'object'),
  memo text,
  posting_error text,
  posted_journal_id uuid,
  created_by uuid not null default auth.uid(),
  submitted_by uuid,
  approved_by uuid,
  posted_by uuid,
  rejected_by uuid,
  cancelled_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  approved_at timestamptz,
  posted_at timestamptz,
  rejected_at timestamptz,
  cancelled_at timestamptz,
  constraint onexa_business_documents_total_math check (
    abs(gross_total - ((subtotal - discount_total) + tax_total)) <= 0.01
  ),
  constraint onexa_business_documents_due_date check (due_date is null or due_date >= document_date),
  constraint onexa_business_documents_party_pair check (
    (party_type is null and party_id is null) or (party_type is not null and party_id is not null)
  ),
  constraint onexa_business_documents_import_pair check (
    origin <> 'import' or import_batch_id is not null
  ),
  unique (tenant_id, legal_entity_id, document_type, document_number, revision)
);

create table if not exists public.onexa_business_document_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  document_id uuid not null references public.onexa_business_documents(id) on delete cascade,
  line_number integer not null check (line_number > 0),
  item_id uuid,
  description text not null check (length(btrim(description)) > 0),
  quantity numeric(20, 6) not null default 1 check (quantity > 0),
  unit_of_measure text,
  unit_price numeric(20, 6) not null default 0 check (unit_price >= 0),
  discount_amount numeric(20, 4) not null default 0 check (discount_amount >= 0),
  net_amount numeric(20, 4) not null default 0 check (net_amount >= 0),
  tax_code text,
  tax_rate numeric(9, 6) not null default 0 check (tax_rate between 0 and 1),
  tax_amount numeric(20, 4) not null default 0 check (tax_amount >= 0),
  gross_amount numeric(20, 4) not null default 0 check (gross_amount >= 0),
  warehouse_id uuid,
  account_role text,
  dimensions jsonb not null default '{}'::jsonb check (jsonb_typeof(dimensions) = 'object'),
  created_at timestamptz not null default now(),
  constraint onexa_business_document_lines_math check (
    abs(gross_amount - (net_amount + tax_amount)) <= 0.01
  ),
  unique (document_id, line_number)
);

create table if not exists public.onexa_business_document_events (
  id bigint generated always as identity primary key,
  tenant_id text not null,
  document_id uuid not null references public.onexa_business_documents(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  actor_id uuid,
  reason text,
  event_data jsonb not null default '{}'::jsonb check (jsonb_typeof(event_data) = 'object'),
  created_at timestamptz not null default now()
);

create index if not exists onexa_documents_entity_status_date_idx
  on public.onexa_business_documents (tenant_id, legal_entity_id, status, accounting_date desc);
create index if not exists onexa_documents_module_status_date_idx
  on public.onexa_business_documents (tenant_id, module_key, status, document_date desc);
create index if not exists onexa_documents_party_due_idx
  on public.onexa_business_documents (tenant_id, party_type, party_id, due_date)
  where party_id is not null and status in ('approved', 'posted');
create index if not exists onexa_documents_pending_idx
  on public.onexa_business_documents (tenant_id, module_key, updated_at desc)
  where status in ('draft', 'submitted', 'approved');
create index if not exists onexa_documents_dimensions_gin_idx
  on public.onexa_business_documents using gin (dimensions jsonb_path_ops);
create index if not exists onexa_document_lines_document_idx
  on public.onexa_business_document_lines (tenant_id, document_id, line_number);
create index if not exists onexa_document_lines_item_idx
  on public.onexa_business_document_lines (tenant_id, item_id)
  where item_id is not null;
create index if not exists onexa_document_events_document_idx
  on public.onexa_business_document_events (tenant_id, document_id, created_at desc);

alter table public.onexa_document_sequences enable row level security;
alter table public.onexa_business_documents enable row level security;
alter table public.onexa_business_document_lines enable row level security;
alter table public.onexa_business_document_events enable row level security;

drop policy if exists onexa_documents_select_tenant on public.onexa_business_documents;
create policy onexa_documents_select_tenant
  on public.onexa_business_documents for select
  to authenticated
  using (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'));

drop policy if exists onexa_documents_insert_tenant on public.onexa_business_documents;
create policy onexa_documents_insert_tenant
  on public.onexa_business_documents for insert
  to authenticated
  with check (
    tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id')
    and created_by = (select auth.uid())
    and status = 'draft'
  );

drop policy if exists onexa_documents_update_tenant on public.onexa_business_documents;
create policy onexa_documents_update_tenant
  on public.onexa_business_documents for update
  to authenticated
  using (
    tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id')
    and status not in ('posted', 'reversed')
    and (
      created_by = (select auth.uid())
      or coalesce(current_setting('onexa.transition_authorized', true), '') = 'true'
    )
  )
  with check (
    tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id')
    and (
      created_by = (select auth.uid())
      or coalesce(current_setting('onexa.transition_authorized', true), '') = 'true'
    )
  );

drop policy if exists onexa_documents_delete_draft on public.onexa_business_documents;
create policy onexa_documents_delete_draft
  on public.onexa_business_documents for delete
  to authenticated
  using (
    tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id')
    and created_by = (select auth.uid())
    and status = 'draft'
  );

drop policy if exists onexa_document_lines_select_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_select_tenant
  on public.onexa_business_document_lines for select
  to authenticated
  using (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'));

drop policy if exists onexa_document_lines_insert_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_insert_tenant
  on public.onexa_business_document_lines for insert
  to authenticated
  with check (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'));

drop policy if exists onexa_document_lines_update_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_update_tenant
  on public.onexa_business_document_lines for update
  to authenticated
  using (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'))
  with check (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'));

drop policy if exists onexa_document_lines_delete_tenant on public.onexa_business_document_lines;
create policy onexa_document_lines_delete_tenant
  on public.onexa_business_document_lines for delete
  to authenticated
  using (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'));

drop policy if exists onexa_document_events_select_tenant on public.onexa_business_document_events;
create policy onexa_document_events_select_tenant
  on public.onexa_business_document_events for select
  to authenticated
  using (tenant_id = (select auth.jwt()->'app_metadata'->>'onexa_tenant_id'));

create or replace function private.onexa_document_prefix(_document_type text)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case _document_type
    when 'sales_invoice' then 'SI'
    when 'customer_receipt' then 'CR'
    when 'purchase_invoice' then 'PI'
    when 'supplier_payment' then 'SP'
    when 'inventory_receipt' then 'IR'
    when 'inventory_issue' then 'II'
    when 'payroll_run' then 'PR'
    when 'fixed_asset_acquisition' then 'FA'
    when 'depreciation_run' then 'DR'
    when 'project_cost' then 'PC'
    when 'maintenance_work_order_cost' then 'MW'
    when 'lease_invoice' then 'LI'
    when 'lease_receipt' then 'LR'
    when 'fleet_trip_cost' then 'FT'
    when 'fuel_issue' then 'FI'
    when 'bank_transfer' then 'BT'
    else 'DOC'
  end;
$$;

create or replace function private.onexa_next_document_number(
  _tenant_id text,
  _legal_entity_id uuid,
  _document_type text,
  _document_date date
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  _year integer := extract(year from _document_date)::integer;
  _prefix text := private.onexa_document_prefix(_document_type);
  _issued bigint;
  _padding smallint;
begin
  if _tenant_id is distinct from (select auth.jwt()->'app_metadata'->>'onexa_tenant_id') then
    raise exception 'ONEXA_TENANT_MISMATCH';
  end if;

  insert into public.onexa_document_sequences (
    tenant_id, legal_entity_id, document_type, fiscal_year, prefix, next_number
  ) values (
    _tenant_id, _legal_entity_id, _document_type, _year, _prefix, 2
  )
  on conflict (tenant_id, legal_entity_id, document_type, fiscal_year)
  do update set next_number = public.onexa_document_sequences.next_number + 1, updated_at = now()
  returning next_number - 1, padding into _issued, _padding;

  return format('%s-%s-%s', _prefix, _year, lpad(_issued::text, _padding, '0'));
end;
$$;

create or replace function private.onexa_guard_business_document_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  _transition_authorized boolean := coalesce(current_setting('onexa.transition_authorized', true), '') = 'true';
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then raise exception 'ONEXA_ONLY_DRAFT_CAN_BE_DELETED'; end if;
    return old;
  end if;

  if old.status in ('posted', 'reversed') then
    raise exception 'ONEXA_POSTED_DOCUMENT_IS_IMMUTABLE';
  end if;

  if new.status is distinct from old.status and not _transition_authorized then
    raise exception 'ONEXA_STATUS_CHANGE_REQUIRES_RPC';
  end if;

  if old.status not in ('draft', 'rejected') and not _transition_authorized then
    raise exception 'ONEXA_DOCUMENT_IS_LOCKED_OUTSIDE_WORKFLOW';
  end if;

  if not _transition_authorized and
     row(new.tenant_id, new.legal_entity_id, new.document_number, new.revision,
         new.status, new.created_by, new.submitted_by, new.approved_by, new.posted_by,
         new.rejected_by, new.cancelled_by, new.created_at, new.submitted_at,
         new.approved_at, new.posted_at, new.rejected_at, new.cancelled_at,
         new.posted_journal_id, new.posting_error)
     is distinct from
     row(old.tenant_id, old.legal_entity_id, old.document_number, old.revision,
         old.status, old.created_by, old.submitted_by, old.approved_by, old.posted_by,
         old.rejected_by, old.cancelled_by, old.created_at, old.submitted_at,
         old.approved_at, old.posted_at, old.rejected_at, old.cancelled_at,
         old.posted_journal_id, old.posting_error) then
    raise exception 'ONEXA_SYSTEM_FIELDS_REQUIRE_WORKFLOW_RPC';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists onexa_guard_business_document_mutation on public.onexa_business_documents;
create trigger onexa_guard_business_document_mutation
before update or delete on public.onexa_business_documents
for each row execute function private.onexa_guard_business_document_mutation();

create or replace function private.onexa_guard_business_document_line_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  _document_id uuid;
  _status text;
  _tenant_id text;
  _created_by uuid;
begin
  _document_id := case when tg_op = 'DELETE' then old.document_id else new.document_id end;

  select status, tenant_id, created_by into _status, _tenant_id, _created_by
  from public.onexa_business_documents
  where id = _document_id;

  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;

  if _tenant_id is distinct from (select auth.jwt()->'app_metadata'->>'onexa_tenant_id') then
    raise exception 'ONEXA_TENANT_MISMATCH';
  end if;
  if _created_by is distinct from auth.uid() then
    raise exception 'ONEXA_ONLY_DOCUMENT_CREATOR_CAN_EDIT_LINES';
  end if;
  if _status not in ('draft', 'rejected') then
    raise exception 'ONEXA_DOCUMENT_LINES_ARE_LOCKED';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists onexa_guard_business_document_line_mutation on public.onexa_business_document_lines;
create trigger onexa_guard_business_document_line_mutation
before insert or update or delete on public.onexa_business_document_lines
for each row execute function private.onexa_guard_business_document_line_mutation();

create or replace function private.onexa_audit_business_document_created()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.onexa_business_document_events (
    tenant_id, document_id, event_type, to_status, actor_id, event_data
  ) values (
    new.tenant_id, new.id, 'created', 'draft', new.created_by,
    jsonb_build_object('origin', new.origin)
  );
  return new;
end;
$$;
revoke all on function private.onexa_audit_business_document_created() from public, anon, authenticated;

drop trigger if exists onexa_audit_business_document_created on public.onexa_business_documents;
create trigger onexa_audit_business_document_created
after insert on public.onexa_business_documents
for each row execute function private.onexa_audit_business_document_created();

create or replace function private.onexa_audit_business_document_status()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status is distinct from old.status then
    insert into public.onexa_business_document_events (
      tenant_id, document_id, event_type, from_status, to_status, actor_id, reason
    ) values (
      new.tenant_id, new.id, 'status_changed', old.status, new.status, auth.uid(),
      nullif(current_setting('onexa.transition_reason', true), '')
    );
  end if;
  return new;
end;
$$;
revoke all on function private.onexa_audit_business_document_status() from public, anon, authenticated;

drop trigger if exists onexa_audit_business_document_status on public.onexa_business_documents;
create trigger onexa_audit_business_document_status
after update of status on public.onexa_business_documents
for each row execute function private.onexa_audit_business_document_status();

create or replace function public.onexa_create_business_document(
  _legal_entity_id uuid,
  _branch_id uuid,
  _module_key text,
  _document_type text,
  _document_date date,
  _accounting_date date,
  _due_date date,
  _currency text,
  _party_type text,
  _party_id uuid,
  _party_name_snapshot text,
  _external_reference text,
  _origin text,
  _import_batch_id uuid,
  _subtotal numeric,
  _discount_total numeric,
  _tax_total numeric,
  _gross_total numeric,
  _dimensions jsonb,
  _source_snapshot jsonb,
  _memo text,
  _lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  _tenant_id text := (select auth.jwt()->'app_metadata'->>'onexa_tenant_id');
  _document_id uuid;
  _document_number text;
  _line_count integer;
  _line_total numeric(20, 4);
begin
  if auth.uid() is null or nullif(_tenant_id, '') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if _lines is null or jsonb_typeof(_lines) <> 'array' or jsonb_array_length(_lines) = 0 then raise exception 'ONEXA_DOCUMENT_LINES_REQUIRED'; end if;
  if _module_key not in ('finance','sales','procurement','inventory','projects','facilities','logistics','assets','people') then raise exception 'ONEXA_INVALID_MODULE'; end if;
  if _origin not in ('native','import','api') then raise exception 'ONEXA_INVALID_DOCUMENT_ORIGIN'; end if;
  if _origin = 'import' and _import_batch_id is null then raise exception 'ONEXA_IMPORT_BATCH_REQUIRED'; end if;

  perform 1 from public.onexa_legal_entities
  where id = _legal_entity_id and tenant_id = _tenant_id and is_active = true;
  if not found then raise exception 'ONEXA_LEGAL_ENTITY_NOT_AVAILABLE'; end if;

  if _branch_id is not null then
    perform 1 from public.onexa_branches
    where id = _branch_id and tenant_id = _tenant_id
      and legal_entity_id = _legal_entity_id and is_active = true;
    if not found then raise exception 'ONEXA_BRANCH_NOT_AVAILABLE'; end if;
  end if;

  perform 1 from public.onexa_module_entitlements
  where tenant_id = _tenant_id and module_key = _module_key and is_enabled = true;
  if not found then raise exception 'ONEXA_MODULE_NOT_ENTITLED'; end if;

  if (case _document_type
       when 'sales_invoice' then 'sales'
       when 'customer_receipt' then 'sales'
       when 'purchase_invoice' then 'procurement'
       when 'supplier_payment' then 'procurement'
       when 'inventory_receipt' then 'inventory'
       when 'inventory_issue' then 'inventory'
       when 'payroll_run' then 'people'
       when 'fixed_asset_acquisition' then 'assets'
       when 'depreciation_run' then 'assets'
       when 'project_cost' then 'projects'
       when 'maintenance_work_order_cost' then 'projects'
       when 'lease_invoice' then 'facilities'
       when 'lease_receipt' then 'facilities'
       when 'fleet_trip_cost' then 'logistics'
       when 'fuel_issue' then 'logistics'
       when 'bank_transfer' then 'finance'
       else null
     end) is distinct from _module_key then
    raise exception 'ONEXA_DOCUMENT_TYPE_MODULE_MISMATCH';
  end if;

  select count(*), coalesce(sum(gross_amount), 0)
  into _line_count, _line_total
  from jsonb_to_recordset(_lines) as line(
    line_number integer, description text, quantity numeric, unit_of_measure text,
    unit_price numeric, discount_amount numeric, net_amount numeric, tax_code text,
    tax_rate numeric, tax_amount numeric, gross_amount numeric, item_id uuid,
    warehouse_id uuid, account_role text, dimensions jsonb
  );

  if _line_count = 0 then raise exception 'ONEXA_DOCUMENT_LINES_REQUIRED'; end if;
  if abs(_line_total - _gross_total) > 0.01 then raise exception 'ONEXA_DOCUMENT_LINE_TOTAL_MISMATCH'; end if;

  _document_number := private.onexa_next_document_number(_tenant_id, _legal_entity_id, _document_type, _document_date);

  insert into public.onexa_business_documents (
    tenant_id, legal_entity_id, branch_id, module_key, document_type,
    document_number, document_date, accounting_date, due_date, currency,
    party_type, party_id, party_name_snapshot, external_reference, origin,
    import_batch_id, subtotal, discount_total, tax_total, gross_total,
    dimensions, source_snapshot, memo, created_by
  ) values (
    _tenant_id, _legal_entity_id, _branch_id, _module_key, _document_type,
    _document_number, _document_date, _accounting_date, _due_date, upper(_currency),
    _party_type, _party_id, _party_name_snapshot, _external_reference, _origin,
    _import_batch_id, _subtotal, _discount_total, _tax_total, _gross_total,
    coalesce(_dimensions, '{}'::jsonb), coalesce(_source_snapshot, '{}'::jsonb), _memo, auth.uid()
  ) returning id into _document_id;

  insert into public.onexa_business_document_lines (
    tenant_id, document_id, line_number, item_id, description, quantity,
    unit_of_measure, unit_price, discount_amount, net_amount, tax_code,
    tax_rate, tax_amount, gross_amount, warehouse_id, account_role, dimensions
  )
  select
    _tenant_id, _document_id, line_number, item_id, description, quantity,
    unit_of_measure, unit_price, discount_amount, net_amount, tax_code,
    tax_rate, tax_amount, gross_amount, warehouse_id, account_role,
    coalesce(dimensions, '{}'::jsonb)
  from jsonb_to_recordset(_lines) as line(
    line_number integer, description text, quantity numeric, unit_of_measure text,
    unit_price numeric, discount_amount numeric, net_amount numeric, tax_code text,
    tax_rate numeric, tax_amount numeric, gross_amount numeric, item_id uuid,
    warehouse_id uuid, account_role text, dimensions jsonb
  );

  return _document_id;
end;
$$;

create or replace function public.onexa_transition_business_document(
  _document_id uuid,
  _to_status text,
  _reason text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  _tenant_id text := (select auth.jwt()->'app_metadata'->>'onexa_tenant_id');
  _actor uuid := auth.uid();
  _document public.onexa_business_documents%rowtype;
begin
  if _actor is null or nullif(_tenant_id, '') is null then raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED'; end if;
  if _to_status not in ('draft','submitted','approved','rejected','cancelled') then raise exception 'ONEXA_INVALID_MANUAL_TRANSITION'; end if;

  select * into _document
  from public.onexa_business_documents
  where id = _document_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_DOCUMENT_NOT_FOUND'; end if;

  if not (
    (_document.status = 'draft' and _to_status in ('submitted','cancelled')) or
    (_document.status = 'submitted' and _to_status in ('approved','rejected','cancelled')) or
    (_document.status = 'rejected' and _to_status in ('draft','cancelled')) or
    (_document.status = 'approved' and _to_status = 'cancelled')
  ) then raise exception 'ONEXA_INVALID_STATUS_TRANSITION'; end if;

  if _to_status = 'approved' and _actor = _document.created_by then
    raise exception 'ONEXA_SEGREGATION_OF_DUTIES_REQUIRED';
  end if;
  if _to_status in ('rejected','cancelled') and nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_TRANSITION_REASON_REQUIRED';
  end if;
  if _document.status in ('draft', 'rejected') and _actor <> _document.created_by then
    raise exception 'ONEXA_ONLY_DOCUMENT_CREATOR_CAN_SUBMIT';
  end if;

  perform set_config('onexa.transition_authorized', 'true', true);
  perform set_config('onexa.transition_reason', coalesce(_reason, ''), true);

  update public.onexa_business_documents
  set status = _to_status,
      submitted_by = case when _to_status = 'submitted' then _actor else submitted_by end,
      submitted_at = case when _to_status = 'submitted' then now() else submitted_at end,
      approved_by = case when _to_status = 'approved' then _actor else approved_by end,
      approved_at = case when _to_status = 'approved' then now() else approved_at end,
      rejected_by = case when _to_status = 'rejected' then _actor else rejected_by end,
      rejected_at = case when _to_status = 'rejected' then now() else rejected_at end,
      cancelled_by = case when _to_status = 'cancelled' then _actor else cancelled_by end,
      cancelled_at = case when _to_status = 'cancelled' then now() else cancelled_at end
  where id = _document_id;

  return _to_status;
end;
$$;

create or replace view public.onexa_module_document_summary
with (security_invoker = true)
as
select
  tenant_id,
  legal_entity_id,
  branch_id,
  module_key,
  document_type,
  status,
  currency,
  count(*) as document_count,
  sum(subtotal) as subtotal,
  sum(tax_total) as tax_total,
  sum(gross_total) as gross_total,
  min(document_date) as first_document_date,
  max(document_date) as last_document_date
from public.onexa_business_documents
group by tenant_id, legal_entity_id, branch_id, module_key, document_type, status, currency;

create or replace view public.onexa_accounting_inbox
with (security_invoker = true)
as
select
  id,
  tenant_id,
  legal_entity_id,
  branch_id,
  module_key,
  document_type,
  document_number,
  document_date,
  accounting_date,
  currency,
  party_type,
  party_id,
  party_name_snapshot,
  gross_total,
  dimensions,
  approved_by,
  approved_at,
  revision
from public.onexa_business_documents
where status = 'approved' and posted_journal_id is null;

revoke all on table public.onexa_document_sequences from anon, authenticated;
revoke all on table public.onexa_business_documents from anon, authenticated;
revoke all on table public.onexa_business_document_lines from anon, authenticated;
revoke all on table public.onexa_business_document_events from anon, authenticated;
grant select on table public.onexa_business_documents to authenticated;
grant select, insert, update, delete on table public.onexa_business_document_lines to authenticated;
grant select on table public.onexa_business_document_events to authenticated;
grant select on table public.onexa_module_document_summary to authenticated;
grant select on table public.onexa_accounting_inbox to authenticated;

revoke all on function private.onexa_document_prefix(text) from public, anon, authenticated;
revoke all on function private.onexa_next_document_number(text, uuid, text, date) from public, anon, authenticated;
revoke all on function private.onexa_guard_business_document_mutation() from public, anon, authenticated;
revoke all on function private.onexa_guard_business_document_line_mutation() from public, anon, authenticated;
revoke all on function public.onexa_create_business_document(uuid, uuid, text, text, date, date, date, text, text, uuid, text, text, text, uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, text, jsonb) from public, anon;
grant execute on function public.onexa_create_business_document(uuid, uuid, text, text, date, date, date, text, text, uuid, text, text, text, uuid, numeric, numeric, numeric, numeric, jsonb, jsonb, text, jsonb) to authenticated;
revoke all on function public.onexa_transition_business_document(uuid, text, text) from public, anon;
grant execute on function public.onexa_transition_business_document(uuid, text, text) to authenticated;

commit;
