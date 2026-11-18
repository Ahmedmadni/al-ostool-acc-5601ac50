-- EXCLUSIVELY FOR disposable onexa_gate_test PostgreSQL, after the
-- native-g42-real-posting-parent.sql synthetic base. Never deploy to hosted.
-- Creates the MINIMAL *synthetic* columns and roles needed to compile and
-- execute the captured REAL B4 function bodies.
do $stop$
begin
  if current_database() <> 'onexa_gate_test'
     or to_regclass('public.fixture_module_grants') is null
     or to_regclass('public.onexa_tenants') is null then
    raise exception 'ONEXA_B4_DISPOSABLE_PARENT_REQUIRED';
  end if;
end $stop$;

alter table public.chart_of_accounts
  add column id uuid not null default gen_random_uuid();

alter table public.onexa_journal_headers
  add column journal_number text not null default 'TEST-B4-PARENT',
  add column fiscal_period_id uuid,
  add column source_snapshot jsonb not null default '{}'::jsonb,
  add column memo text,
  add column posted_by uuid,
  add column posted_at timestamptz not null default now();
alter table public.onexa_journal_headers alter column state set default 'posted';

create table public.onexa_journal_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  journal_id uuid not null references public.onexa_journal_headers(id),
  line_number integer not null,
  account_code text not null,
  debit numeric(20,4) not null,
  credit numeric(20,4) not null,
  description text,
  dimensions jsonb not null default '{}'::jsonb,
  created_at timestamptz default now(),
  unique (journal_id,line_number)
);
create table public.onexa_fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null,
  legal_entity_id uuid not null,
  period_code text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null check(status in ('open','closed')),
  unique(tenant_id,legal_entity_id,period_code)
);
create table public.onexa_posting_registry (
  idempotency_key text primary key,
  tenant_id text not null,
  legal_entity_id uuid not null,
  source_document_type text not null,
  source_document_id text not null,
  source_revision integer not null,
  journal_id uuid not null unique references public.onexa_journal_headers(id)
);
create table public.onexa_workspace_audit_events (
  id bigint generated always as identity primary key,
  tenant_id text not null,
  actor_user_id uuid not null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  details jsonb not null default '{}'::jsonb
);
create sequence public.onexa_journal_number_seq start with 1;

-- Authorization surrogate only; actual B4 has_workspace_role membership
-- logic must still be exercised against an independently cloned Staging.
create function onexa_private.has_workspace_role(_user uuid,_roles text[])
returns boolean language sql stable security definer
set search_path = pg_catalog,public
as $fixture$
  select exists(select 1 from public.onexa_workspace_memberships m
                where m.tenant_id=onexa_private.claim_tenant_id()
                and m.user_id=_user and m.status='active')
$fixture$;

insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select m.tenant_id,m.user_id,'finance',v.action
from public.onexa_workspace_memberships m
cross join (values ('create'),('submit'),('approve'),('post'),('reverse')) v(action)
on conflict do nothing;

insert into public.onexa_fiscal_periods(
  tenant_id,legal_entity_id,period_code,starts_on,ends_on,status)
values
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000001','2026-11',date '2026-11-01',date '2026-11-30','open'),
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000001','2026-12',date '2026-12-01',date '2026-12-31','open'),
 ('tenant-smoke-B','b0000000-0000-4000-8000-000000000001','2026-11',date '2026-11-01',date '2026-11-30','open');

grant select on public.onexa_fiscal_periods,public.onexa_journal_lines,
  public.onexa_posting_registry to authenticated;
grant execute on function onexa_private.has_workspace_role(uuid,text[]) to authenticated;

-- The real B4 functions will be loaded AFTER this fixture, replacing the
-- minimal test-only parent publisher. No fake B4 publisher is loaded here.
