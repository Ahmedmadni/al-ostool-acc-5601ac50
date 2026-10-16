-- ONEXA Gate 72: native tenant-scoped operations site/asset foundations.
-- MANUAL APPROVAL ONLY. Requires verified Gate 71 company scope and ONEXA RBAC.
-- Does NOT install legacy ops_* tables or a work-order posting engine.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_operations_sites') is not null
     or to_regclass('public.onexa_operations_assets') is not null
     or to_regprocedure('public.onexa_create_operations_site(uuid,uuid,text,text)') is not null
     or to_regprocedure('public.onexa_create_operations_asset(uuid,text,text,text)') is not null then
    raise exception 'ONEXA_GATE72_ALREADY_OR_PARTIALLY_INSTALLED_STOP';
  end if;
  if to_regclass('public.onexa_company_module_scopes') is null
     or to_regclass('public.onexa_branches') is null
     or to_regclass('public.onexa_legal_entities') is null
     or to_regclass('public.onexa_tenants') is null
     or to_regprocedure('public.onexa_has_company_module_access(text,text)') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null then
    raise exception 'ONEXA_GATE72_TENANT_COMPANY_SCOPE_BRANCH_RBAC_REQUIRED';
  end if;
end
$preflight$;

-- Composite referenced identities guarantee branch belongs to the same
-- ONEXA tenant and legal entity, and site belongs to that same branch.
create unique index if not exists onexa_branches_tenant_entity_id_uq
  on public.onexa_branches(tenant_id,legal_entity_id,id);
create unique index if not exists onexa_company_module_scopes_tenant_entity_id_uq
  on public.onexa_company_module_scopes(tenant_id,legal_entity_id,id);

create table public.onexa_operations_sites (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null references public.onexa_tenants(tenant_id) on delete restrict,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  company_scope_id uuid not null,
  site_code text not null
    check (site_code=upper(btrim(site_code)) and site_code~'^[A-Z0-9_-]{2,32}$'),
  name_ar text not null check (nullif(btrim(name_ar),'') is not null),
  name_en text,
  city text,
  address text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onexa_ops_site_branch_scope_fk
    foreign key (tenant_id,legal_entity_id,branch_id)
    references public.onexa_branches(tenant_id,legal_entity_id,id)
    on delete restrict,
  constraint onexa_ops_site_company_scope_fk
    foreign key (tenant_id,legal_entity_id,company_scope_id)
    references public.onexa_company_module_scopes(tenant_id,legal_entity_id,id)
    on delete restrict,
  constraint onexa_ops_site_tenant_entity_code_uq
    unique (tenant_id,legal_entity_id,site_code),
  constraint onexa_ops_site_tenant_entity_branch_id_uq
    unique (tenant_id,legal_entity_id,branch_id,id)
);

create table public.onexa_operations_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null references public.onexa_tenants(tenant_id) on delete restrict,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  site_id uuid not null,
  asset_code text not null
    check (asset_code=upper(btrim(asset_code)) and asset_code~'^[A-Z0-9_-]{2,32}$'),
  name_ar text not null check (nullif(btrim(name_ar),'') is not null),
  category text not null check (nullif(btrim(category),'') is not null),
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onexa_ops_asset_site_tenant_entity_branch_fk
    foreign key (tenant_id,legal_entity_id,branch_id,site_id)
    references public.onexa_operations_sites(tenant_id,legal_entity_id,branch_id,id)
    on delete restrict,
  constraint onexa_ops_asset_tenant_entity_code_uq
    unique (tenant_id,legal_entity_id,asset_code)
);

create index onexa_ops_sites_active_lookup
  on public.onexa_operations_sites(tenant_id,legal_entity_id,branch_id)
  where is_active;
create index onexa_ops_assets_site_active_lookup
  on public.onexa_operations_assets(tenant_id,legal_entity_id,site_id)
  where is_active;

alter table public.onexa_operations_sites enable row level security;
alter table public.onexa_operations_assets enable row level security;

create policy onexa_operations_sites_read
  on public.onexa_operations_sites for select to authenticated
  using (tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null
    and onexa_private.is_active_member(auth.uid())
    and onexa_private.has_module_action(auth.uid(),'projects','read')
    and exists (select 1 from public.onexa_company_module_scopes scope
      where scope.id=company_scope_id and scope.tenant_id=onexa_operations_sites.tenant_id
        and scope.legal_entity_id=onexa_operations_sites.legal_entity_id
        and scope.legacy_company_code='OM' and scope.module_key='projects'
        and scope.is_active)
    and exists (select 1 from public.onexa_branches branch
      join public.onexa_legal_entities entity
        on entity.id=branch.legal_entity_id and entity.tenant_id=branch.tenant_id
      where branch.id=onexa_operations_sites.branch_id
        and branch.tenant_id=onexa_operations_sites.tenant_id
        and branch.legal_entity_id=onexa_operations_sites.legal_entity_id
        and branch.is_active and entity.is_active));

create policy onexa_operations_assets_read
  on public.onexa_operations_assets for select to authenticated
  using (tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null
    and onexa_private.is_active_member(auth.uid())
    and onexa_private.has_module_action(auth.uid(),'projects','read')
    and exists (select 1 from public.onexa_operations_sites site
      join public.onexa_company_module_scopes scope
        on scope.id=site.company_scope_id and scope.tenant_id=site.tenant_id
       and scope.legal_entity_id=site.legal_entity_id
       and scope.legacy_company_code='OM' and scope.module_key='projects'
       and scope.is_active
      join public.onexa_branches branch
        on branch.id=site.branch_id and branch.tenant_id=site.tenant_id
       and branch.legal_entity_id=site.legal_entity_id and branch.is_active
      join public.onexa_legal_entities entity
        on entity.id=branch.legal_entity_id
       and entity.tenant_id=branch.tenant_id and entity.is_active
      where site.id=site_id and site.is_active
        and site.tenant_id=onexa_operations_assets.tenant_id
        and site.legal_entity_id=onexa_operations_assets.legal_entity_id
        and site.branch_id=onexa_operations_assets.branch_id));

-- Even privileged provisioning cannot move a site or asset to a new tenant,
-- legal entity, branch, company alias or parent site via an UPDATE.
create function onexa_private.guard_native_operations_site_identity()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  if tg_op='UPDATE' and
     row(new.tenant_id,new.legal_entity_id,new.branch_id,new.company_scope_id)
       is distinct from
     row(old.tenant_id,old.legal_entity_id,old.branch_id,old.company_scope_id) then
    raise exception 'ONEXA_OPERATIONS_SITE_SCOPE_IMMUTABLE';
  end if;
  if not exists (
    select 1 from public.onexa_company_module_scopes scope
    join public.onexa_legal_entities entity
      on entity.id=scope.legal_entity_id and entity.tenant_id=scope.tenant_id
    join public.onexa_branches branch
      on branch.id=new.branch_id and branch.tenant_id=scope.tenant_id
     and branch.legal_entity_id=scope.legal_entity_id
    where scope.id=new.company_scope_id and scope.tenant_id=new.tenant_id
      and scope.legal_entity_id=new.legal_entity_id
      and scope.legacy_company_code='OM' and scope.module_key='projects'
      and scope.is_active and entity.is_active and branch.is_active
  ) then
    raise exception 'ONEXA_OPERATIONS_SITE_SCOPE_INVALID';
  end if;
  return new;
end;
$;

create trigger onexa_guard_native_operations_site_identity
before insert or update on public.onexa_operations_sites for each row
execute function onexa_private.guard_native_operations_site_identity();

create function onexa_private.guard_native_operations_asset_identity()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  if tg_op='UPDATE' and
     row(new.tenant_id,new.legal_entity_id,new.branch_id,new.site_id)
       is distinct from
     row(old.tenant_id,old.legal_entity_id,old.branch_id,old.site_id) then
    raise exception 'ONEXA_OPERATIONS_ASSET_SCOPE_IMMUTABLE';
  end if;
  if not exists (
    select 1 from public.onexa_operations_sites site
    where site.id=new.site_id and site.tenant_id=new.tenant_id
      and site.legal_entity_id=new.legal_entity_id
      and site.branch_id=new.branch_id and site.is_active
  ) then
    raise exception 'ONEXA_OPERATIONS_ASSET_PARENT_SITE_INVALID';
  end if;
  return new;
end;
$;

create trigger onexa_guard_native_operations_asset_identity
before insert or update on public.onexa_operations_assets for each row
execute function onexa_private.guard_native_operations_asset_identity();

create function public.onexa_create_operations_site(
  _legal_entity_id uuid,_branch_id uuid,_site_code text,_name_ar text
)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _scope_id uuid;
  _new_id uuid;
begin
  if _actor is null or nullif(_tenant,'') is null
     or not onexa_private.is_active_member(_actor)
     or not onexa_private.has_module_action(_actor,'projects','create')
     or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_OPERATIONS_SITE_CREATE_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_site_code),'') is null or nullif(btrim(_name_ar),'') is null then
    raise exception 'ONEXA_OPERATIONS_SITE_DETAILS_REQUIRED';
  end if;
  select scope.id into _scope_id
  from public.onexa_company_module_scopes scope
  join public.onexa_legal_entities entity
    on entity.id=scope.legal_entity_id and entity.tenant_id=scope.tenant_id
  join public.onexa_branches branch
    on branch.id=_branch_id and branch.tenant_id=scope.tenant_id
   and branch.legal_entity_id=scope.legal_entity_id
  where scope.tenant_id=_tenant and scope.legal_entity_id=_legal_entity_id
    and scope.legacy_company_code='OM' and scope.module_key='projects'
    and scope.is_active and entity.is_active and branch.is_active;
  if _scope_id is null then raise exception 'ONEXA_OPERATIONS_SITE_ENTITY_SCOPE_INVALID'; end if;
  insert into public.onexa_operations_sites
    (tenant_id,legal_entity_id,branch_id,company_scope_id,site_code,name_ar,created_by)
  values (_tenant,_legal_entity_id,_branch_id,_scope_id,upper(btrim(_site_code)),
    btrim(_name_ar),_actor)
  returning id into _new_id;
  return _new_id;
end;
$$;

create function public.onexa_create_operations_asset(
  _site_id uuid,_asset_code text,_name_ar text,_category text
)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public as $$
declare
  _tenant text:=onexa_private.claim_tenant_id();
  _actor uuid:=auth.uid();
  _site public.onexa_operations_sites%rowtype;
  _new_id uuid;
begin
  if _actor is null or nullif(_tenant,'') is null
     or not onexa_private.is_active_member(_actor)
     or not onexa_private.has_module_action(_actor,'projects','create')
     or not public.onexa_has_company_module_access('OM','maintenance') then
    raise exception 'ONEXA_OPERATIONS_ASSET_CREATE_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_asset_code),'') is null or nullif(btrim(_name_ar),'') is null
     or nullif(btrim(_category),'') is null then
    raise exception 'ONEXA_OPERATIONS_ASSET_DETAILS_REQUIRED';
  end if;
  select * into _site
  from public.onexa_operations_sites
  where id=_site_id and tenant_id=_tenant and is_active
  for update;
  if _site.id is null or not exists (
    select 1 from public.onexa_company_module_scopes scope
    join public.onexa_legal_entities entity
      on entity.id=scope.legal_entity_id and entity.tenant_id=scope.tenant_id
    join public.onexa_branches branch
      on branch.id=_site.branch_id and branch.tenant_id=scope.tenant_id
     and branch.legal_entity_id=scope.legal_entity_id
    where scope.id=_site.company_scope_id
      and scope.tenant_id=_tenant
      and scope.legal_entity_id=_site.legal_entity_id
      and scope.legacy_company_code='OM' and scope.module_key='projects'
      and scope.is_active and entity.is_active and branch.is_active
  ) then
    raise exception 'ONEXA_OPERATIONS_ASSET_SITE_SCOPE_INVALID';
  end if;
  insert into public.onexa_operations_assets
    (tenant_id,legal_entity_id,branch_id,site_id,asset_code,name_ar,category,created_by)
  values (_tenant,_site.legal_entity_id,_site.branch_id,_site.id,
    upper(btrim(_asset_code)),btrim(_name_ar),btrim(_category),_actor)
  returning id into _new_id;
  return _new_id;
end;
$$;

revoke all on public.onexa_operations_sites,public.onexa_operations_assets
  from public,anon,authenticated;
grant select on public.onexa_operations_sites,public.onexa_operations_assets
  to authenticated;
grant all on public.onexa_operations_sites,public.onexa_operations_assets
  to service_role;
revoke all on function public.onexa_create_operations_site(uuid,uuid,text,text),
  public.onexa_create_operations_asset(uuid,text,text,text) from public,anon;
grant execute on function public.onexa_create_operations_site(uuid,uuid,text,text),
  public.onexa_create_operations_asset(uuid,text,text,text) to authenticated;
revoke all on function onexa_private.guard_native_operations_site_identity(),
  onexa_private.guard_native_operations_asset_identity() from public,anon,authenticated;

commit;
