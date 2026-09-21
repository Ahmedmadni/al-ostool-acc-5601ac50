-- ONEXA ERP — B3 post-install verification (read only)
-- Every row must have status = ready.

with expected_functions(object_name, signature, expected_authenticated) as (
  values
    ('has_module_action', 'onexa_private.has_module_action(uuid,text,text)', true),
    ('is_admin', 'public.is_admin(uuid)', true),
    ('has_role', 'public.has_role(uuid,public.app_role)', true),
    ('user_has_any_role', 'public.user_has_any_role(uuid,text[])', true),
    ('has_permission', 'public.has_permission(uuid,text,text)', true),
    ('onexa_create_business_document', 'public.onexa_create_business_document(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb)', true),
    ('onexa_transition_business_document', 'public.onexa_transition_business_document(uuid,text,text)', true),
    ('onexa_post_journal', 'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)', true),
    ('onexa_reverse_journal', 'public.onexa_reverse_journal(uuid,date,text,text)', true),
    ('onexa_create_business_document_unchecked', 'public.onexa_create_business_document_unchecked(uuid,uuid,text,text,date,date,date,text,text,uuid,text,text,text,uuid,numeric,numeric,numeric,numeric,jsonb,jsonb,text,jsonb)', false),
    ('onexa_transition_business_document_unchecked', 'public.onexa_transition_business_document_unchecked(uuid,text,text)', false),
    ('onexa_post_journal_unchecked', 'public.onexa_post_journal_unchecked(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)', false),
    ('onexa_reverse_journal_unchecked', 'public.onexa_reverse_journal_unchecked(uuid,date,text,text)', false)
),
function_checks as (
  select
    'function'::text as check_type,
    expected.object_name,
    case
      when proc.oid is null then 'missing'
      when has_function_privilege('anon', proc.oid, 'EXECUTE') then 'anon_execute_exposed'
      when has_function_privilege('authenticated', proc.oid, 'EXECUTE') <> expected.expected_authenticated
        then 'authenticated_execute_mismatch'
      else 'ready'
    end::text as status,
    case when proc.oid is null then expected.signature
      else format(
        'security=%s; config=%s; anon=%s; authenticated=%s',
        case when proc.prosecdef then 'definer' else 'invoker' end,
        coalesce(array_to_string(proc.proconfig, ','), 'none'),
        has_function_privilege('anon', proc.oid, 'EXECUTE'),
        has_function_privilege('authenticated', proc.oid, 'EXECUTE')
      )
    end::text as details
  from expected_functions expected
  left join pg_proc proc on proc.oid = to_regprocedure(expected.signature)
),
legacy_function_checks as (
  select
    'legacy_function'::text as check_type,
    proc.proname::text as object_name,
    case
      when has_function_privilege('anon', proc.oid, 'EXECUTE') then 'anon_execute_exposed'
      when proc.prosecdef
       and coalesce(array_to_string(proc.proconfig, ','), '') not like '%search_path=pg_catalog%'
        then 'search_path_not_hardened'
      else 'ready'
    end::text as status,
    format(
      'signature=%s; config=%s; anon=%s',
      proc.oid::regprocedure,
      coalesce(array_to_string(proc.proconfig, ','), 'none'),
      has_function_privilege('anon', proc.oid, 'EXECUTE')
    )::text as details
  from pg_proc proc
  join pg_namespace ns on ns.oid = proc.pronamespace
  where ns.nspname = 'public'
    and proc.proname in (
      'is_admin','has_role','user_has_any_role','has_permission',
      'log_permission_change','hr_termination_undo_approval',
      'hr_termination_revert_approval'
    )
),
policy_checks as (
  select
    'policy'::text as check_type,
    policy.tablename || '.' || policy.policyname as object_name,
    case
      when coalesce(policy.qual, '') || coalesce(policy.with_check, '')
        not like '%has_module_action%' then 'module_authorization_missing'
      else 'ready'
    end::text as status,
    jsonb_build_object(
      'command', policy.cmd,
      'using', policy.qual,
      'with_check', policy.with_check
    )::text as details
  from pg_policies policy
  where policy.schemaname = 'public'
    and policy.policyname in (
      'onexa_documents_select_tenant','onexa_documents_insert_tenant',
      'onexa_documents_update_tenant','onexa_documents_delete_draft',
      'onexa_document_lines_select_tenant','onexa_document_lines_insert_tenant',
      'onexa_document_lines_update_tenant','onexa_document_lines_delete_tenant',
      'onexa_document_events_select_tenant'
    )
)
select * from function_checks
union all select * from legacy_function_checks
union all select * from policy_checks
order by check_type, object_name;
