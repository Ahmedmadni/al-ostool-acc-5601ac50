-- ONEXA Gate 71 (code only): tenant-native company/module scope bridge.
-- MANUAL, APPROVED MIGRATION ONLY. NO AUTO-SEED OR ENV-FLAG FLIP.
-- This does NOT retrofit legacy global group_* / ops_* / re_* tables or
-- authorize Gates 13–15. It establishes the tenant-safe company boundary.

begin;

do $preflight$
begin
  if to_regclass('public.onexa_company_module_scopes') is not null
     or to_regprocedure('public.onexa_has_company_module_access(text,text)') is not null
     or to_regprocedure('public.onexa_list_company_module_scopes()') is not null then
    raise exception 'ONEXA_GATE71_PARTIAL_OR_ALREADY_INSTALLED_STOP';
  end if;
  if to_regclass('public.onexa_tenants') is null
     or to_regclass('public.onexa_legal_entities') is null
     or to_regclass('public.onexa_workspace_memberships') is null
     or to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_GATE71_TENANT_MEMBERSHIP_AND_MODULE_RBAC_REQUIRED';
  end if;
  if exists (select 1 from (values
      ('onexa_legal_entities','id'),
      ('onexa_legal_entities','tenant_id'),
      ('onexa_legal_entities','is_active'),
      ('onexa_tenants','tenant_id')
    ) as expected(table_name,column_name)
    where not exists (select 1 from information_schema.columns c
      where c.table_schema='public'
        and c.table_name=expected.table_name
        and c.column_name=expected.column_name)) then
    raise exception 'ONEXA_GATE71_COMPANY_ENTITY_SCHEMA_MISMATCH';
  end if;
end
$preflight$;

-- A composite referenced key prevents a scope from pointing across tenants,
-- even when a privileged service user makes a provisioning mistake.
-- Index creation on existing legal entities needs separately reviewed lock
-- timing and a restore-capable backup before production execution.
create unique index if not exists onexa_legal_entities_tenant_id_id_uq
  on public.onexa_legal_entities(tenant_id,id);

create table public.onexa_company_module_scopes (
  id uuid primary key default gen_random_uuid(),
  tenant_id text not null references public.onexa_tenants(tenant_id) on delete restrict,
  legal_entity_id uuid not null,
  legacy_company_code text not null
    check (legacy_company_code in ('CORE','OM','RE')),
  module_key text not null
    check ((legacy_company_code='CORE' and module_key='finance')
        or (legacy_company_code='OM' and module_key='projects')
        or (legacy_company_code='RE' and module_key='facilities')),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint onexa_company_module_entity_tenant_fk
    foreign key (tenant_id,legal_entity_id)
    references public.onexa_legal_entities(tenant_id,id) on delete restrict,
  constraint onexa_company_module_tenant_code_uq
    unique (tenant_id,legacy_company_code),
  constraint onexa_company_module_tenant_entity_module_uq
    unique (tenant_id,legal_entity_id,module_key)
);

create index onexa_company_module_entity_scope_idx
  on public.onexa_company_module_scopes(tenant_id,legal_entity_id)
  where is_active;

alter table public.onexa_company_module_scopes enable row level security;
create policy onexa_company_module_scopes_member_select
  on public.onexa_company_module_scopes for select to authenticated
  using (
    tenant_id=onexa_private.claim_tenant_id()
    and auth.uid() is not null
    and onexa_private.is_active_member(auth.uid())
    and onexa_private.has_module_action(auth.uid(),module_key,'read')
    and exists (select 1 from public.onexa_legal_entities entity
      where entity.id=legal_entity_id
        and entity.tenant_id=onexa_company_module_scopes.tenant_id
        and entity.is_active)
  );

-- The provisioning identity is immutable after creation. Disabling an alias
-- and creating a separately approved replacement is an explicit admin action.
create function onexa_private.guard_company_module_scope_identity()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $$
begin
  if row(new.tenant_id,new.legal_entity_id,new.legacy_company_code,new.module_key)
     is distinct from
     row(old.tenant_id,old.legal_entity_id,old.legacy_company_code,old.module_key) then
    raise exception 'ONEXA_COMPANY_MODULE_SCOPE_IDENTITY_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger onexa_guard_company_module_scope_identity
before update on public.onexa_company_module_scopes for each row
execute function onexa_private.guard_company_module_scope_identity();

-- Compatibility aliases use the CURRENT ONEXA tenant and canonical RBAC.
-- Passing an arbitrary legacy code or a guessed legal_entity UUID cannot
-- bypass membership, module action or the composite entity/tenant boundary.
create function public.onexa_has_company_module_access(
  _company_code text, _legacy_module_key text
)
returns boolean language sql stable security definer
set search_path=pg_catalog,public as $$
select
  auth.uid() is not null
  and nullif(onexa_private.claim_tenant_id(),'') is not null
  and onexa_private.is_active_member(auth.uid())
  and exists (
    select 1 from public.onexa_company_module_scopes scope
    join public.onexa_legal_entities entity
      on entity.id=scope.legal_entity_id
     and entity.tenant_id=scope.tenant_id
    where scope.tenant_id=onexa_private.claim_tenant_id()
      and scope.is_active and entity.is_active
      and scope.legacy_company_code=upper(btrim(_company_code))
      and (
        (scope.legacy_company_code='CORE'
          and _legacy_module_key='corporate_erp' and scope.module_key='finance')
        or (scope.legacy_company_code='OM'
          and _legacy_module_key='maintenance' and scope.module_key='projects')
        or (scope.legacy_company_code='RE'
          and _legacy_module_key='real_estate' and scope.module_key='facilities')
      )
      and onexa_private.has_module_action(auth.uid(),scope.module_key,'read')
  );
$$;

-- An explicit permission-filtered and tenant-filtered source for future
-- native company selection. Legacy clients remain OFF until independent UAT.
create view public.onexa_active_company_module_scopes
with (security_invoker=true) as
select scope.id,scope.tenant_id,scope.legal_entity_id,
  scope.legacy_company_code,scope.module_key,
  entity.code as legal_entity_code,entity.name_ar as legal_entity_name_ar
from public.onexa_company_module_scopes scope
join public.onexa_legal_entities entity
  on entity.id=scope.legal_entity_id and entity.tenant_id=scope.tenant_id
where scope.is_active and entity.is_active
  and scope.tenant_id=onexa_private.claim_tenant_id()
  and auth.uid() is not null
  and onexa_private.is_active_member(auth.uid())
  and onexa_private.has_module_action(auth.uid(),scope.module_key,'read');

revoke all on public.onexa_company_module_scopes from public,anon,authenticated;
grant select on public.onexa_company_module_scopes to authenticated;
grant all on public.onexa_company_module_scopes to service_role;
revoke all on public.onexa_active_company_module_scopes from public,anon;
grant select on public.onexa_active_company_module_scopes to authenticated;
revoke all on function public.onexa_has_company_module_access(text,text)
  from public,anon;
grant execute on function public.onexa_has_company_module_access(text,text)
  to authenticated;
revoke all on function onexa_private.guard_company_module_scope_identity()
  from public,anon,authenticated;

commit;
