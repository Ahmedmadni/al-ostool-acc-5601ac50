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

-- Native ONEXA finance shell ONLY: Gate42 table/function DDL comes from real SQL.
-- Journal publisher below is a test double, NOT the B4 accounting engine.
create table public.onexa_business_documents (
  id uuid primary key,
  tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid references public.onexa_branches(id),
  document_type text not null, module_key text not null,
  status text not null, origin text not null default 'native',
  posted_journal_id uuid,
  currency text not null default 'SAR',
  source_snapshot jsonb not null default '{}'::jsonb,
  dimensions jsonb not null default '{}'::jsonb,
  gross_total numeric(20,4) not null default 0,
  tax_total numeric(20,4) not null default 0,
  discount_total numeric(20,4) not null default 0,
  subtotal numeric(20,4) not null default 0,
  revision integer not null default 1,
  external_reference text,document_number text not null default 'FAKE',
  accounting_date date not null default current_date,
  party_id uuid,party_type text,memo text,posting_error text,
  created_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),posted_at timestamptz
);
create table public.onexa_business_document_lines (
 id uuid primary key default gen_random_uuid(),tenant_id text not null,
 document_id uuid not null references public.onexa_business_documents(id),
 item_id uuid,tax_amount numeric(20,4) not null,
 net_amount numeric(20,4) not null,gross_amount numeric(20,4) not null
);
create table public.onexa_business_document_events (
 id uuid primary key default gen_random_uuid(),tenant_id text not null,
 document_id uuid not null,event_type text not null,from_status text,
 to_status text,actor_id uuid,event_data jsonb
);
create table public.onexa_journal_headers (
  id uuid primary key,tenant_id text not null references public.onexa_tenants(tenant_id),
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  state text not null,reversal_journal_id uuid,reversal_of_id uuid,
  source_document_type text,source_document_id text,source_revision integer,
  currency text not null default 'SAR',total_debit numeric(20,4),
  total_credit numeric(20,4),accounting_date date not null default current_date
);
create table public.onexa_account_role_mappings(
 tenant_id text not null,legal_entity_id uuid not null,account_role text not null,
 account_code text not null,is_active boolean not null default true,
 primary key(tenant_id,legal_entity_id,account_role)
);
create table public.chart_of_accounts(
 tenant_id text not null,code text not null,account_type text not null,
 category text not null,is_active boolean not null default true,
 primary key(tenant_id,code)
);
create function public.onexa_post_journal(
 _legal_entity_id uuid,_source_document_type text,_source_document_id text,
 _source_revision integer,_source_status text,_source_snapshot jsonb,
 _accounting_date date,_period_code text,_currency text,_memo text,_lines jsonb
) returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _id uuid:=gen_random_uuid();
 _tenant text:=onexa_private.claim_tenant_id();
 _debit numeric:=(select coalesce(sum((v->>'debit')::numeric),0)
                    from jsonb_array_elements(_lines) v);
 _credit numeric:=(select coalesce(sum((v->>'credit')::numeric),0)
                    from jsonb_array_elements(_lines) v);
begin
 if auth.uid() is null or _tenant is null or _source_status<>'approved'
    or _source_document_type<>'project_cost' or _debit<>_credit or _debit<=0
    or jsonb_array_length(_lines)<>2 then
   raise exception 'SMOKE_B4_STUB_INVALID_JOURNAL_SOURCE';
 end if;
 insert into public.onexa_journal_headers(
   id,tenant_id,legal_entity_id,state,source_document_type,source_document_id,
   source_revision,currency,total_debit,total_credit,accounting_date
 ) values(_id,_tenant,_legal_entity_id,'posted',_source_document_type,
    _source_document_id,_source_revision,_currency,_debit,_credit,_accounting_date);
 return _id;
end;
$$;

grant select on public.onexa_legal_entities,public.onexa_branches to authenticated;
grant select on public.onexa_workspace_memberships to authenticated;
grant select on public.onexa_tenants,public.customers,public.contracts to authenticated;
grant select on public.onexa_business_documents,public.onexa_journal_headers,
 public.onexa_business_document_lines,public.onexa_business_document_events,
 public.chart_of_accounts,public.onexa_account_role_mappings to authenticated;
grant execute on function public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb) to authenticated;
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
cross join (values ('read'),('create'),('approve'),('post')) action(action);
insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select tenant_id,user_id,'finance','read' from public.onexa_workspace_memberships;

-- Synthetic account role maps for the *real Gate42* posting RPC.
insert into public.chart_of_accounts(tenant_id,code,account_type,category)
values('tenant-smoke-A','5200','detail','expenses'),
('tenant-smoke-A','2100','detail','liabilities'),
('tenant-smoke-B','5200','detail','expenses'),
('tenant-smoke-B','2100','detail','liabilities');
insert into public.onexa_account_role_mappings(tenant_id,legal_entity_id,account_role,account_code)
values('tenant-smoke-A','a0000000-0000-4000-8000-000000000001','project_wip_or_expense','5200'),
('tenant-smoke-A','a0000000-0000-4000-8000-000000000001','cost_source_or_clearing','2100'),
('tenant-smoke-B','b0000000-0000-4000-8000-000000000001','project_wip_or_expense','5200'),
('tenant-smoke-B','b0000000-0000-4000-8000-000000000001','cost_source_or_clearing','2100');


-- Extra synthetic Gate63 parent records/functions for REAL Gate64 installation.
alter table public.onexa_business_documents
 add column document_date date not null default current_date,
 add column party_name_snapshot text,
 add column approved_by uuid,
 add column approved_at timestamptz;

create table public.onexa_approval_workflows(
 id uuid primary key, tenant_id text not null, process_key text not null,
 is_active boolean not null default true
);
create table public.onexa_approval_workflow_steps(
 id uuid primary key,tenant_id text not null,workflow_id uuid not null,
 action_key text not null,step_order integer not null,name_ar text not null,
 is_required boolean not null default true
);
create table public.onexa_approval_instances(
 id uuid primary key,tenant_id text not null,document_id uuid not null,
 status text not null,started_at timestamptz not null default now(),
 current_step_id uuid,current_step_order integer,
 updated_at timestamptz not null default now(),completed_at timestamptz
);
create table public.onexa_approval_decisions(
 tenant_id text not null,instance_id uuid not null,document_id uuid not null,
 step_id uuid not null,step_order integer not null,step_snapshot jsonb not null,
 actor_user_id uuid not null,decision text not null,reason text not null,
 unique(tenant_id,instance_id,step_id,decision)
);

grant select on public.onexa_approval_instances,
 public.onexa_approval_decisions,public.onexa_approval_workflow_steps,
 public.onexa_approval_workflows to authenticated;

create function public.onexa_approval_separation_required(_document_type text,_action text)
returns boolean language sql stable as $$
 select _document_type='project_cost' and _action='post'
$$;
create function onexa_private.approval_actor_matches_step(
 _step_id uuid,_document_id uuid,_actor uuid
) returns boolean language sql stable as $$
 select _step_id='a0000000-0000-4000-8000-000000000032'::uuid
   and _document_id='a0000000-0000-4000-8000-000000000021'::uuid
   and _actor='a0000000-0000-4000-8000-000000000015'::uuid
   and onexa_private.claim_tenant_id()='tenant-smoke-A'
$$;

-- Stub ONLY to satisfy Gate64's seven-engine patch contract.
create function public.onexa_post_sales_invoice(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _actor uuid:=auth.uid();
 _document public.onexa_business_documents%rowtype;
begin
 select * into _document from public.onexa_business_documents
   where id=_document_id and tenant_id=onexa_private.claim_tenant_id();
 if _actor = _document.created_by then
   raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
 end if;
 return null;
end;
$$;

-- Stub ONLY to satisfy Gate64's seven-engine patch contract.
create function public.onexa_post_purchase_invoice(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _actor uuid:=auth.uid();
 _document public.onexa_business_documents%rowtype;
begin
 select * into _document from public.onexa_business_documents
   where id=_document_id and tenant_id=onexa_private.claim_tenant_id();
 if _actor = _document.created_by then
   raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
 end if;
 return null;
end;
$$;

-- Stub ONLY to satisfy Gate64's seven-engine patch contract.
create function public.onexa_post_customer_receipt(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _actor uuid:=auth.uid();
 _receipt public.onexa_business_documents%rowtype;
begin
 select * into _receipt from public.onexa_business_documents
   where id=_document_id and tenant_id=onexa_private.claim_tenant_id();
 if _actor = _receipt.created_by then
   raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
 end if;
 return null;
end;
$$;

-- Stub ONLY to satisfy Gate64's seven-engine patch contract.
create function public.onexa_post_supplier_payment(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _actor uuid:=auth.uid();
 _payment public.onexa_business_documents%rowtype;
begin
 select * into _payment from public.onexa_business_documents
   where id=_document_id and tenant_id=onexa_private.claim_tenant_id();
 if _actor = _payment.created_by then
   raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
 end if;
 return null;
end;
$$;

-- Stub ONLY to satisfy Gate64's seven-engine patch contract.
create function public.onexa_post_bank_transfer(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _actor uuid:=auth.uid();
 _document public.onexa_business_documents%rowtype;
begin
 select * into _document from public.onexa_business_documents
   where id=_document_id and tenant_id=onexa_private.claim_tenant_id();
 if _actor = _document.created_by then
   raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
 end if;
 return null;
end;
$$;

-- Stub ONLY to satisfy Gate64's seven-engine patch contract.
create function public.onexa_post_fleet_trip_cost(_document_id uuid,_period_code text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 _actor uuid:=auth.uid();
 _document public.onexa_business_documents%rowtype;
begin
 select * into _document from public.onexa_business_documents
   where id=_document_id and tenant_id=onexa_private.claim_tenant_id();
 if _actor = _document.created_by then
   raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
 end if;
 return null;
end;
$$;
