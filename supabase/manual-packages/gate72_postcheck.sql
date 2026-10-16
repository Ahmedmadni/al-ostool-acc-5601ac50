-- Gate72 postflight; READ ONLY; run only after independently approved SQL.
select 'sites_table' as check_name,
  case when to_regclass('public.onexa_operations_sites') is not null then 'READY' else 'MISSING' end as status
union all select 'assets_table',
  case when to_regclass('public.onexa_operations_assets') is not null then 'READY' else 'MISSING' end
union all select 'create_site_rpc',
  case when to_regprocedure('public.onexa_create_operations_site(uuid,uuid,text,text)') is not null then 'READY' else 'MISSING' end
union all select 'create_asset_rpc',
  case when to_regprocedure('public.onexa_create_operations_asset(uuid,text,text,text)') is not null then 'READY' else 'MISSING' end
union all select 'site_scope_rls',
  case when exists(select 1 from pg_class where oid=to_regclass('public.onexa_operations_sites')
    and relrowsecurity) then 'READY' else 'MISSING' end
union all select 'asset_scope_rls',
  case when exists(select 1 from pg_class where oid=to_regclass('public.onexa_operations_assets')
    and relrowsecurity) then 'READY' else 'MISSING' end
union all select 'site_scope_immutable',
  case when exists(select 1 from pg_trigger
    where tgrelid=to_regclass('public.onexa_operations_sites')
     and tgname='onexa_guard_native_operations_site_identity'
     and tgenabled in ('O','A') and not tgisinternal) then 'READY' else 'MISSING' end
union all select 'asset_scope_immutable',
  case when exists(select 1 from pg_trigger
    where tgrelid=to_regclass('public.onexa_operations_assets')
     and tgname='onexa_guard_native_operations_asset_identity'
     and tgenabled in ('O','A') and not tgisinternal) then 'READY' else 'MISSING' end
union all select 'site_branch_and_company_fks',
  case when (select count(*) from pg_constraint c where c.conrelid=to_regclass('public.onexa_operations_sites')
    and c.contype='f' and c.convalidated
    and c.conname in ('onexa_ops_site_branch_scope_fk','onexa_ops_site_company_scope_fk'))=2
     then 'READY' else 'MISSING' end
union all select 'asset_site_composite_fk',
  case when exists(select 1 from pg_constraint c
    where c.conrelid=to_regclass('public.onexa_operations_assets')
      and c.conname='onexa_ops_asset_site_tenant_entity_branch_fk'
      and c.contype='f' and c.convalidated) then 'READY' else 'MISSING' end
order by check_name;

-- These access checks require installed objects, and must show
-- false/true/false/false for anonymous read, authenticated read/write and
-- anonymous execution respectively. No writes are executed here.
select has_table_privilege('anon','public.onexa_operations_sites','SELECT') as anon_can_read_sites,
  has_table_privilege('authenticated','public.onexa_operations_sites','SELECT') as authenticated_can_read_sites,
  has_table_privilege('authenticated','public.onexa_operations_sites','INSERT,UPDATE,DELETE') as authenticated_can_write_sites,
  has_table_privilege('authenticated','public.onexa_operations_assets','INSERT,UPDATE,DELETE') as authenticated_can_write_assets,
  has_function_privilege('anon','public.onexa_create_operations_site(uuid,uuid,text,text)','EXECUTE') as anon_can_create_site,
  has_function_privilege('anon','public.onexa_create_operations_asset(uuid,text,text,text)','EXECUTE') as anon_can_create_asset;

-- Should be zero. Composite FKs must reject every mismatch, including
-- a privileged service-role mistake.
select a.id,a.tenant_id,a.legal_entity_id,a.branch_id,a.site_id
from public.onexa_operations_assets a
left join public.onexa_operations_sites s
  on s.id=a.site_id and s.tenant_id=a.tenant_id
 and s.legal_entity_id=a.legal_entity_id and s.branch_id=a.branch_id
where s.id is null;

select s.id,s.tenant_id,s.legal_entity_id,s.branch_id,s.company_scope_id
from public.onexa_operations_sites s
left join public.onexa_company_module_scopes scope
  on scope.id=s.company_scope_id and scope.tenant_id=s.tenant_id
 and scope.legal_entity_id=s.legal_entity_id
where scope.id is null or scope.module_key<>'projects'
  or scope.legacy_company_code<>'OM';
