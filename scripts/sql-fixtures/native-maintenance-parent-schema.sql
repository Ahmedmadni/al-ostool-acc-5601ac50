-- SYNTHETIC EPHEMERAL TEST DB ONLY. NEVER APPLY TO CUSTOMER DATABASE.
-- Minimal ONEXA parent surfaces to compile the production SQL packages.
-- These mocks DO NOT certify real production parent schema compatibility.
create schema auth;
create schema onexa_private;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
grant usage on schema public,auth,onexa_private to authenticated,service_role;

create table auth.users (
  id uuid primary key
);

create table public.onexa_tenants (
  tenant_id text primary key,
  status text not null default 'active'
);
create table public.onexa_legal_entities (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  code text not null,
  name_ar text not null,
  is_active boolean not null default true
);
create table public.onexa_branches (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  is_active boolean not null default true
);
create table public.onexa_workspace_memberships (
  tenant_id text not null references public.onexa_tenants(tenant_id),
  user_id uuid not null references auth.users(id),
  status text not null default 'active',
  primary key(tenant_id,user_id)
);
create table public.fixture_module_grants (
  tenant_id text not null,
  user_id uuid not null,
  module_key text not null,
  action text not null,
  primary key(tenant_id,user_id,module_key,action)
);

create function auth.uid() returns uuid
language sql stable as $$
 select nullif(current_setting('test.user_id',true),'')::uuid
$$;
create function onexa_private.claim_tenant_id() returns text
language sql stable as $$
 select nullif(current_setting('test.tenant_id',true),'')
$$;
create function onexa_private.is_active_member(_user_id uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public as $$
 select exists (
   select 1 from public.onexa_workspace_memberships m
   where m.user_id=_user_id and m.tenant_id=onexa_private.claim_tenant_id()
     and m.status='active'
 )
$$;
create function onexa_private.has_module_action(_user_id uuid,_module text,_action text)
returns boolean language sql stable security definer
set search_path=pg_catalog,public as $$
 select exists (
   select 1 from public.fixture_module_grants g
   where g.user_id=_user_id and g.tenant_id=onexa_private.claim_tenant_id()
     and g.module_key=_module and g.action=_action
 )
$$;

-- Gate 73 contract and customer reference surfaces.
create table public.customers (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  is_active boolean not null default true
);
create table public.contracts (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  customer_id uuid not null references public.customers(id),
  status text not null default 'active',
  start_date date,
  end_date date
);

-- Gate 42 posting references: mocked parent schema only. Real Gate 42 still
-- requires a separate application of its actual, approved SQL package.
create table public.onexa_project_cost_centers (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  project_code text not null,
  cost_center_code text not null,
  is_active boolean not null default true
);
create table public.onexa_business_documents (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid references public.onexa_branches(id),
  document_type text not null,
  module_key text not null,
  status text not null,
  origin text not null default 'native',
  posted_journal_id uuid,
  currency text not null default 'SAR',
  source_snapshot jsonb not null default '{}'::jsonb,
  gross_total numeric(20,4) not null default 0,
  tax_total numeric(20,4) not null default 0,
  discount_total numeric(20,4) not null default 0,
  subtotal numeric(20,4) not null default 0,
  revision integer not null default 1,
  external_reference text,
  document_number text not null default 'FAKE',
  accounting_date date not null default current_date
);
create table public.onexa_journal_headers (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  state text not null,
  reversal_journal_id uuid,
  reversal_of_id uuid,
  source_document_type text,
  source_document_id text,
  source_revision integer,
  currency text not null default 'SAR',
  total_debit numeric(20,4),
  total_credit numeric(20,4),
  accounting_date date not null default current_date
);
create table public.onexa_project_cost_postings (
  document_id uuid primary key references public.onexa_business_documents(id),
  tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  project_cost_center_id uuid not null references public.onexa_project_cost_centers(id),
  amount numeric(20,4) not null,
  source_revision integer not null,
  journal_id uuid not null references public.onexa_journal_headers(id),
  posted_by uuid not null references auth.users(id)
);

grant select on public.onexa_legal_entities,public.onexa_branches to authenticated;
grant select on public.onexa_workspace_memberships to authenticated;
grant select on public.onexa_tenants,public.customers,public.contracts to authenticated;
grant select on public.onexa_project_cost_centers,public.onexa_business_documents,
  public.onexa_project_cost_postings,public.onexa_journal_headers to authenticated;
grant execute on all functions in schema auth,onexa_private to authenticated;

-- Fake two tenants; no production customer IDs, users or financial figures.
insert into public.onexa_tenants(tenant_id) values ('tenant-smoke-A'),('tenant-smoke-B');
insert into public.onexa_legal_entities(id,tenant_id,code,name_ar) values
 ('a0000000-0000-4000-8000-000000000001','tenant-smoke-A','TESTA','مستأجر اختبار أ'),
 ('b0000000-0000-4000-8000-000000000001','tenant-smoke-B','TESTB','مستأجر اختبار ب');
insert into public.onexa_branches(id,tenant_id,legal_entity_id) values
 ('a0000000-0000-4000-8000-000000000002','tenant-smoke-A','a0000000-0000-4000-8000-000000000001'),
 ('b0000000-0000-4000-8000-000000000002','tenant-smoke-B','b0000000-0000-4000-8000-000000000001');
insert into public.customers(id,tenant_id) values
 ('a0000000-0000-4000-8000-000000000003','tenant-smoke-A'),
 ('b0000000-0000-4000-8000-000000000003','tenant-smoke-B');
insert into public.contracts(id,tenant_id,customer_id,status) values
 ('a0000000-0000-4000-8000-000000000004','tenant-smoke-A','a0000000-0000-4000-8000-000000000003','active'),
 ('b0000000-0000-4000-8000-000000000004','tenant-smoke-B','b0000000-0000-4000-8000-000000000003','active');
insert into public.onexa_project_cost_centers
  (id,tenant_id,legal_entity_id,branch_id,project_code,cost_center_code)
 values
 ('a0000000-0000-4000-8000-000000000005','tenant-smoke-A',
  'a0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','PROJ_A','OM_A'),
 ('b0000000-0000-4000-8000-000000000005','tenant-smoke-B',
  'b0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000002','PROJ_B','OM_B');
insert into auth.users(id) values
 ('a0000000-0000-4000-8000-000000000011'),
 ('a0000000-0000-4000-8000-000000000012'),
 ('a0000000-0000-4000-8000-000000000013'),
 ('a0000000-0000-4000-8000-000000000014'),
 ('a0000000-0000-4000-8000-000000000015'),
 ('b0000000-0000-4000-8000-000000000011');
insert into public.onexa_workspace_memberships(tenant_id,user_id) values
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000011'),
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000012'),
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000013'),
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000014'),
 ('tenant-smoke-A','a0000000-0000-4000-8000-000000000015'),
 ('tenant-smoke-B','b0000000-0000-4000-8000-000000000011');
insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select m.tenant_id,m.user_id,'projects',action.action
from public.onexa_workspace_memberships m
cross join (values ('read'),('create'),('approve')) action(action);
insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select tenant_id,user_id,'finance','read' from public.onexa_workspace_memberships;
