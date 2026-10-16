-- Gate 71: READ ONLY postflight, run AFTER explicitly approved migration.
-- The first result set is architectural/security readiness, not proof of UAT.

select 'tenant_company_scope_table'::text as check_name,
 case when to_regclass('public.onexa_company_module_scopes') is not null then 'READY' else 'MISSING' end as status
union all
select 'tenant_scope_access_rpc',
 case when to_regprocedure('public.onexa_has_company_module_access(text,text)') is not null
   then 'READY' else 'MISSING' end
union all
select 'tenant_scoped_company_view',
 case when to_regclass('public.onexa_active_company_module_scopes') is not null
   then 'READY' else 'MISSING' end
union all
select 'tenant_identity_guard',
 case when exists(select 1 from pg_trigger t
   where t.tgname='onexa_guard_company_module_scope_identity'
     and t.tgrelid=to_regclass('public.onexa_company_module_scopes')
     and t.tgenabled in ('O','A') and not t.tgisinternal)
   then 'READY' else 'MISSING' end
union all
select 'company_scope_rls',
 case when exists(select 1 from pg_class c
   where c.oid=to_regclass('public.onexa_company_module_scopes')
     and c.relrowsecurity) then 'READY' else 'MISSING' end
union all
select 'view_security_invoker',
 case when exists(select 1 from pg_class c
   where c.oid=to_regclass('public.onexa_active_company_module_scopes')
     and c.reloptions @> array['security_invoker=true'])
   then 'READY' else 'MISSING' end
union all
select 'tenant_and_entity_composite_fk',
 case when exists(select 1 from pg_constraint c
   where c.conrelid=to_regclass('public.onexa_company_module_scopes')
     and c.conname='onexa_company_module_entity_tenant_fk'
     and c.contype='f' and c.convalidated)
   then 'READY' else 'MISSING' end
union all
select 'scope_id_immutability_function',
 case when to_regprocedure('onexa_private.guard_company_module_scope_identity()') is not null
   then 'READY' else 'MISSING' end
order by check_name;

-- Requires the migration table and routine; only run once objects are READY.
select has_table_privilege('anon','public.onexa_company_module_scopes','SELECT') as anon_can_read_scope,
 has_table_privilege('authenticated','public.onexa_company_module_scopes','SELECT') as authenticated_can_read_scope,
 has_table_privilege('authenticated','public.onexa_company_module_scopes','INSERT,UPDATE,DELETE') as authenticated_can_write_scope,
 has_function_privilege('anon','public.onexa_has_company_module_access(text,text)','EXECUTE') as anon_can_execute_access,
 has_function_privilege('authenticated','public.onexa_has_company_module_access(text,text)','EXECUTE') as authenticated_can_execute_access,
 has_table_privilege('anon','public.onexa_active_company_module_scopes','SELECT') as anon_can_read_view;

-- Security-definer protection is checked in addition to RLS. Unknown legacy
-- names must NEVER be resolved automatically.
select pg_get_functiondef(to_regprocedure('public.onexa_has_company_module_access(text,text)'))
  ~ 'scope.tenant_id=onexa_private.claim_tenant_id' as has_explicit_tenant_filter,
 pg_get_functiondef(to_regprocedure('public.onexa_has_company_module_access(text,text)'))
  ~ 'onexa_private.has_module_action' as has_canonical_module_permission,
 pg_get_functiondef(to_regprocedure('public.onexa_has_company_module_access(text,text)'))
  ~ 'onexa_private.is_active_member' as has_workspace_membership_check;

-- Must yield zero. Cross-tenant FK should make this impossible even under
-- service-role provisioning mistakes.
select scope.id,scope.tenant_id,scope.legal_entity_id
from public.onexa_company_module_scopes scope
left join public.onexa_legal_entities e
  on e.id=scope.legal_entity_id and e.tenant_id=scope.tenant_id
where e.id is null;

-- No seed values are provided by Gate 71. Any mapping should have a separate
-- approved provisioning record and two-tenant negative-access test.
select tenant_id,legacy_company_code,module_key,count(*) as scope_count
from public.onexa_company_module_scopes
group by tenant_id,legacy_company_code,module_key
order by tenant_id,legacy_company_code,module_key;
