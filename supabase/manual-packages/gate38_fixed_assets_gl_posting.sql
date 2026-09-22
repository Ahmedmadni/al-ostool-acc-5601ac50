-- ONEXA Gate 38: fixed-asset register -> monthly depreciation -> general ledger.
-- Gate 36 already posts purchase acquisition value. Gate 38 never duplicates that
-- acquisition journal; it governs subsequent depreciation only.
-- Keep VITE_ENABLE_ONEXA_ASSET_POSTING disabled until the account mapping,
-- postcheck and rollback-only smoke test all pass.

begin;

do $$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null then
    raise exception 'ONEXA_B4_POST_JOURNAL_SIGNATURE_REQUIRED';
  end if;
  if to_regclass('public.fixed_assets') is null then
    raise exception 'ONEXA_FIXED_ASSET_REGISTER_REQUIRED';
  end if;
  if to_regclass('public.onexa_account_role_mappings') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null then
    raise exception 'ONEXA_ACCOUNTING_AUTHORIZATION_FOUNDATION_REQUIRED';
  end if;
end;
$$;

alter table public.fixed_assets
  add column if not exists legal_entity_id uuid references public.onexa_legal_entities(id) on delete restrict,
  add column if not exists branch_id uuid references public.onexa_branches(id) on delete restrict,
  add column if not exists salvage_value numeric(20,4) default 0,
  add column if not exists depreciation_start_date date,
  add column if not exists opening_accumulated_depreciation numeric(20,4),
  add column if not exists depreciation_method text default 'straight_line';

update public.fixed_assets
set opening_accumulated_depreciation = coalesce(accumulated_depreciation, 0)
where opening_accumulated_depreciation is null;

update public.fixed_assets set salvage_value = 0 where salvage_value is null;
update public.fixed_assets set depreciation_method = 'straight_line'
where depreciation_method is null;

alter table public.fixed_assets
  alter column salvage_value set default 0,
  alter column salvage_value set not null,
  alter column opening_accumulated_depreciation set default 0,
  alter column opening_accumulated_depreciation set not null,
  alter column depreciation_method set default 'straight_line',
  alter column depreciation_method set not null;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.fixed_assets'::regclass
      and conname = 'fixed_assets_gate38_values_check'
  ) then
    alter table public.fixed_assets
      add constraint fixed_assets_gate38_values_check check (
        coalesce(cost, 0) >= 0
        and salvage_value >= 0
        and coalesce(accumulated_depreciation, 0) >= 0
        and opening_accumulated_depreciation >= 0
        and coalesce(net_book_value, 0) >= 0
        and (cost is null or salvage_value <= cost)
        and depreciation_method = 'straight_line'
      ) not valid;
  end if;
end;
$constraints$;

create table if not exists public.onexa_asset_depreciation_postings (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  asset_id uuid not null references public.fixed_assets(id) on delete restrict,
  legal_entity_id uuid not null references public.onexa_legal_entities(id) on delete restrict,
  branch_id uuid not null references public.onexa_branches(id) on delete restrict,
  period_code text not null check (period_code ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  accounting_date date not null,
  journal_id uuid not null unique,
  source_revision integer not null default 1 check (source_revision = 1),
  opening_accumulated_depreciation numeric(20,4) not null check (opening_accumulated_depreciation >= 0),
  depreciation_amount numeric(20,4) not null check (depreciation_amount > 0),
  closing_accumulated_depreciation numeric(20,4) not null check (closing_accumulated_depreciation >= 0),
  closing_net_book_value numeric(20,4) not null check (closing_net_book_value >= 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  unique (tenant_id, asset_id, period_code),
  constraint onexa_asset_depreciation_rollforward_check check (
    abs(closing_accumulated_depreciation - (opening_accumulated_depreciation + depreciation_amount)) <= 0.01
  )
);

create index if not exists onexa_asset_depreciation_postings_lookup_idx
  on public.onexa_asset_depreciation_postings
  (tenant_id, legal_entity_id, branch_id, period_code, asset_id);

alter table public.onexa_asset_depreciation_postings enable row level security;
drop policy if exists onexa_asset_depreciation_postings_select_tenant
  on public.onexa_asset_depreciation_postings;
create policy onexa_asset_depreciation_postings_select_tenant
  on public.onexa_asset_depreciation_postings for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'assets', 'read')
  );

create or replace function public.onexa_guard_posted_asset_financials()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if current_setting('app.onexa_asset_depreciation_write', true) = 'on' then
    return new;
  end if;
  if exists (
    select 1
    from public.onexa_asset_depreciation_postings posting
    where posting.asset_id = old.id
      and posting.tenant_id = old.tenant_id
  ) and (
    new.cost is distinct from old.cost
    or new.salvage_value is distinct from old.salvage_value
    or new.useful_life_years is distinct from old.useful_life_years
    or new.depreciation_start_date is distinct from old.depreciation_start_date
    or new.opening_accumulated_depreciation is distinct from old.opening_accumulated_depreciation
    or new.accumulated_depreciation is distinct from old.accumulated_depreciation
    or new.net_book_value is distinct from old.net_book_value
    or new.legal_entity_id is distinct from old.legal_entity_id
    or new.branch_id is distinct from old.branch_id
  ) then
    raise exception 'ONEXA_POSTED_ASSET_FINANCIALS_IMMUTABLE';
  end if;
  return new;
end;
$$;

drop trigger if exists onexa_guard_posted_asset_financials
  on public.fixed_assets;
create trigger onexa_guard_posted_asset_financials
before update on public.fixed_assets
for each row execute function public.onexa_guard_posted_asset_financials();

create or replace view public.onexa_asset_accounting_reconciliation
with (security_invoker = true)
as
with posting_totals as (
  select
    tenant_id,
    asset_id,
    count(*)::integer as posted_periods,
    coalesce(sum(depreciation_amount), 0) as gate38_depreciation,
    max(period_code) as latest_posted_period,
    max(posted_at) as latest_posted_at
  from public.onexa_asset_depreciation_postings
  group by tenant_id, asset_id
)
select
  asset.id as asset_id,
  asset.tenant_id,
  asset.legal_entity_id,
  asset.branch_id,
  asset.asset_code,
  asset.asset_name,
  asset.category,
  asset.project_id,
  asset.department_id,
  asset.purchase_date,
  asset.depreciation_start_date,
  asset.depreciation_method,
  coalesce(asset.cost, 0)::numeric(20,4) as cost,
  asset.salvage_value,
  coalesce(asset.annual_depreciation, 0)::numeric(20,4) as annual_depreciation,
  asset.opening_accumulated_depreciation,
  coalesce(asset.accumulated_depreciation, 0)::numeric(20,4) as accumulated_depreciation,
  coalesce(asset.net_book_value, 0)::numeric(20,4) as net_book_value,
  coalesce(posting.posted_periods, 0) as posted_periods,
  coalesce(posting.gate38_depreciation, 0)::numeric(20,4) as gate38_depreciation,
  posting.latest_posted_period,
  posting.latest_posted_at,
  case
    when asset.legal_entity_id is null then 'legal_entity_required'
    when asset.branch_id is null then 'branch_required'
    when not exists (
      select 1 from public.onexa_legal_entities entity
      where entity.id = asset.legal_entity_id
        and entity.tenant_id = asset.tenant_id
        and entity.is_active = true
    ) then 'invalid_legal_entity'
    when not exists (
      select 1 from public.onexa_branches branch
      where branch.id = asset.branch_id
        and branch.legal_entity_id = asset.legal_entity_id
        and branch.tenant_id = asset.tenant_id
        and branch.is_active = true
    ) then 'invalid_branch'
    when coalesce(asset.cost, 0) <= 0 then 'cost_required'
    when asset.salvage_value < 0 or asset.salvage_value >= coalesce(asset.cost, 0) then 'invalid_salvage_value'
    when coalesce(asset.useful_life_years, 0) <= 0 then 'useful_life_required'
    when asset.depreciation_start_date is null then 'depreciation_start_required'
    when asset.depreciation_method <> 'straight_line' then 'unsupported_method'
    when abs(
      coalesce(asset.accumulated_depreciation, 0)
      - (asset.opening_accumulated_depreciation + coalesce(posting.gate38_depreciation, 0))
    ) > 0.01 then 'register_mismatch'
    when coalesce(asset.net_book_value, 0) <= asset.salvage_value + 0.01 then 'fully_depreciated'
    else 'ready'
  end as reconciliation_status
from public.fixed_assets asset
left join posting_totals posting
  on posting.tenant_id = asset.tenant_id
 and posting.asset_id = asset.id;

create or replace view public.onexa_asset_posting_configuration_gaps
with (security_invoker = true)
as
with required_roles(account_role) as (
  values
    ('depreciation_expense'::text),
    ('accumulated_depreciation'::text)
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
where entity.is_active = true
  and mapping.id is null;

create or replace function public.onexa_post_asset_depreciation(
  _asset_id uuid,
  _period_code text,
  _accounting_date date
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _asset public.fixed_assets%rowtype;
  _expense_account text;
  _accumulated_account text;
  _journal_id uuid;
  _monthly_amount numeric(20,4);
  _remaining_amount numeric(20,4);
  _depreciation_amount numeric(20,4);
  _closing_accumulated numeric(20,4);
  _closing_nbv numeric(20,4);
  _dimensions jsonb;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'assets', 'post') then
    raise exception 'ONEXA_ASSET_DEPRECIATION_POST_NOT_AUTHORIZED';
  end if;
  if coalesce(btrim(_period_code), '') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or to_char(_accounting_date, 'YYYY-MM') <> btrim(_period_code) then
    raise exception 'ONEXA_ASSET_DEPRECIATION_PERIOD_INVALID';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(_tenant_id || ':asset-depreciation:' || _asset_id::text || ':' || btrim(_period_code), 0)
  );

  select * into _asset
  from public.fixed_assets
  where id = _asset_id and tenant_id = _tenant_id
  for update;
  if not found then
    raise exception 'ONEXA_FIXED_ASSET_NOT_FOUND';
  end if;

  select journal_id into _journal_id
  from public.onexa_asset_depreciation_postings
  where tenant_id = _tenant_id
    and asset_id = _asset_id
    and period_code = btrim(_period_code);
  if found then
    return _journal_id;
  end if;

  if lower(coalesce(_asset.status, 'active')) <> 'active' then
    raise exception 'ONEXA_FIXED_ASSET_MUST_BE_ACTIVE';
  end if;
  if _asset.imported_by is not null and _actor = _asset.imported_by then
    raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
  end if;
  if _asset.legal_entity_id is null or _asset.branch_id is null then
    raise exception 'ONEXA_ASSET_ENTITY_BRANCH_REQUIRED';
  end if;
  if not exists (
    select 1 from public.onexa_legal_entities
    where id = _asset.legal_entity_id
      and tenant_id = _tenant_id
      and is_active = true
  ) then
    raise exception 'ONEXA_LEGAL_ENTITY_NOT_FOUND';
  end if;
  if not exists (
    select 1 from public.onexa_branches
    where id = _asset.branch_id
      and legal_entity_id = _asset.legal_entity_id
      and tenant_id = _tenant_id
      and is_active = true
  ) then
    raise exception 'ONEXA_BRANCH_NOT_FOUND';
  end if;
  if coalesce(_asset.cost, 0) <= 0
     or coalesce(_asset.useful_life_years, 0) <= 0
     or _asset.depreciation_start_date is null
     or _asset.depreciation_method <> 'straight_line'
     or _asset.salvage_value < 0
     or _asset.salvage_value >= _asset.cost then
    raise exception 'ONEXA_ASSET_DEPRECIATION_CONFIGURATION_INVALID';
  end if;
  if _accounting_date < _asset.depreciation_start_date then
    raise exception 'ONEXA_ASSET_DEPRECIATION_BEFORE_START_DATE';
  end if;
  if exists (
    select 1
    from public.onexa_asset_depreciation_postings
    where tenant_id = _tenant_id
      and asset_id = _asset_id
      and period_code > btrim(_period_code)
  ) then
    raise exception 'ONEXA_ASSET_DEPRECIATION_OUT_OF_SEQUENCE';
  end if;

  _remaining_amount := round(
    _asset.cost - _asset.salvage_value - coalesce(_asset.accumulated_depreciation, 0),
    4
  );
  if _remaining_amount <= 0.01 then
    raise exception 'ONEXA_FIXED_ASSET_FULLY_DEPRECIATED';
  end if;

  _monthly_amount := round(
    (_asset.cost - _asset.salvage_value)
    / (_asset.useful_life_years * 12),
    4
  );
  _depreciation_amount := least(_monthly_amount, _remaining_amount);
  if _depreciation_amount <= 0 then
    raise exception 'ONEXA_ASSET_DEPRECIATION_AMOUNT_INVALID';
  end if;

  select account_code into _expense_account
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id
    and legal_entity_id = _asset.legal_entity_id
    and account_role = 'depreciation_expense'
    and is_active = true;
  select account_code into _accumulated_account
  from public.onexa_account_role_mappings
  where tenant_id = _tenant_id
    and legal_entity_id = _asset.legal_entity_id
    and account_role = 'accumulated_depreciation'
    and is_active = true;
  if _expense_account is null or _accumulated_account is null then
    raise exception 'ONEXA_ASSET_DEPRECIATION_ACCOUNT_MAPPING_REQUIRED';
  end if;

  _dimensions := jsonb_strip_nulls(jsonb_build_object(
    'legalEntity', _asset.legal_entity_id,
    'branch', _asset.branch_id,
    'asset', _asset.id,
    'project', _asset.project_id,
    'department', _asset.department_id
  ));

  select public.onexa_post_journal(
    _legal_entity_id => _asset.legal_entity_id,
    _source_document_type => 'depreciation_run',
    _source_document_id => _asset.id::text || ':' || btrim(_period_code),
    _source_revision => 1,
    _source_status => 'approved',
    _source_snapshot => jsonb_build_object(
      'asset_id', _asset.id,
      'asset_code', _asset.asset_code,
      'asset_name', _asset.asset_name,
      'period_code', btrim(_period_code),
      'cost', _asset.cost,
      'salvage_value', _asset.salvage_value,
      'opening_accumulated_depreciation', coalesce(_asset.accumulated_depreciation, 0),
      'depreciation_amount', _depreciation_amount,
      'posting_contract_version', 'asset-depreciation-v1'
    ),
    _accounting_date => _accounting_date,
    _period_code => btrim(_period_code),
    _currency => 'SAR',
    _memo => 'Asset depreciation - ' || coalesce(_asset.asset_code, _asset.id::text)
      || ' - ' || btrim(_period_code),
    _lines => jsonb_build_array(
      jsonb_build_object(
        'account_code', _expense_account,
        'debit', _depreciation_amount,
        'credit', 0,
        'description', 'Depreciation expense - ' || _asset.asset_name,
        'dimensions', _dimensions
      ),
      jsonb_build_object(
        'account_code', _accumulated_account,
        'debit', 0,
        'credit', _depreciation_amount,
        'description', 'Accumulated depreciation - ' || _asset.asset_name,
        'dimensions', _dimensions
      )
    )
  )::uuid into _journal_id;
  if _journal_id is null then
    raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE';
  end if;

  _closing_accumulated := round(
    coalesce(_asset.accumulated_depreciation, 0) + _depreciation_amount,
    4
  );
  _closing_nbv := greatest(round(_asset.cost - _closing_accumulated, 4), _asset.salvage_value);

  insert into public.onexa_asset_depreciation_postings (
    tenant_id, asset_id, legal_entity_id, branch_id, period_code,
    accounting_date, journal_id, opening_accumulated_depreciation,
    depreciation_amount, closing_accumulated_depreciation,
    closing_net_book_value, posted_by
  ) values (
    _tenant_id, _asset.id, _asset.legal_entity_id, _asset.branch_id,
    btrim(_period_code), _accounting_date, _journal_id,
    coalesce(_asset.accumulated_depreciation, 0), _depreciation_amount,
    _closing_accumulated, _closing_nbv, _actor
  );

  perform set_config('app.onexa_asset_depreciation_write', 'on', true);
  update public.fixed_assets
  set
    annual_depreciation = round(_monthly_amount * 12, 4),
    accumulated_depreciation = _closing_accumulated,
    net_book_value = _closing_nbv
  where id = _asset.id and tenant_id = _tenant_id;
  perform set_config('app.onexa_asset_depreciation_write', 'off', true);

  return _journal_id;
end;
$$;

revoke all on table public.onexa_asset_depreciation_postings
  from anon, authenticated;
grant select on table public.onexa_asset_depreciation_postings
  to authenticated;
grant select on table public.onexa_asset_accounting_reconciliation
  to authenticated;
grant select on table public.onexa_asset_posting_configuration_gaps
  to authenticated;

revoke all on function public.onexa_guard_posted_asset_financials()
  from public, anon, authenticated;
revoke all on function public.onexa_post_asset_depreciation(uuid, text, date) from public, anon;
grant execute on function public.onexa_post_asset_depreciation(uuid, text, date)
  to authenticated;

commit;
