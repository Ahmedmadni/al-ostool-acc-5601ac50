-- ONEXA ERP — Gate 34 post-install verification
-- Run after 202609200001_onexa_business_document_foundation.sql.
-- One result grid only: every row must have status = ready.

with expected_tables(object_name) as (
  values
    ('onexa_document_sequences'::text),
    ('onexa_business_documents'::text),
    ('onexa_business_document_lines'::text),
    ('onexa_business_document_events'::text)
),
table_checks as (
  select
    'table'::text as check_type,
    e.object_name,
    case
      when c.oid is null then 'missing'
      when not c.relrowsecurity then 'rls_disabled'
      else 'ready'
    end::text as status,
    coalesce('rls=' || c.relrowsecurity::text, 'not installed')::text as details
  from expected_tables e
  left join pg_class c
    on c.oid = to_regclass('public.' || e.object_name)
),
expected_views(object_name) as (
  values
    ('onexa_accounting_inbox'::text),
    ('onexa_module_document_summary'::text)
),
view_checks as (
  select
    'view'::text as check_type,
    e.object_name,
    case
      when c.oid is null then 'missing'
      when coalesce(c.reloptions, array[]::text[]) @> array['security_invoker=true']::text[] then 'ready'
      else 'security_invoker_missing'
    end::text as status,
    coalesce(array_to_string(c.reloptions, ','), 'not installed')::text as details
  from expected_views e
  left join pg_class c
    on c.oid = to_regclass('public.' || e.object_name)
),
expected_functions(object_name) as (
  values
    ('onexa_create_business_document'::text),
    ('onexa_transition_business_document'::text)
),
function_checks as (
  select
    'function'::text as check_type,
    e.object_name,
    case
      when p.oid is null then 'missing'
      when not has_function_privilege('authenticated', p.oid, 'EXECUTE') then 'authenticated_execute_missing'
      when has_function_privilege('anon', p.oid, 'EXECUTE') then 'anon_execute_exposed'
      else 'ready'
    end::text as status,
    case
      when p.oid is null then 'not installed'
      else pg_get_function_identity_arguments(p.oid)
    end::text as details
  from expected_functions e
  left join lateral (
    select p0.oid
    from pg_proc p0
    join pg_namespace n0 on n0.oid = p0.pronamespace
    where n0.nspname = 'public'
      and p0.proname = e.object_name
    order by p0.oid
    limit 1
  ) p on true
),
privilege_checks as (
  select
    'privilege'::text as check_type,
    'onexa_business_documents_direct_writes'::text as object_name,
    case
      when to_regclass('public.onexa_business_documents') is null then 'missing'
      when has_table_privilege('authenticated', 'public.onexa_business_documents', 'INSERT')
        or has_table_privilege('authenticated', 'public.onexa_business_documents', 'UPDATE')
        or has_table_privilege('authenticated', 'public.onexa_business_documents', 'DELETE')
        then 'direct_write_exposed'
      else 'ready'
    end::text as status,
    'authenticated direct insert/update/delete must remain false'::text as details
)
select * from table_checks
union all select * from view_checks
union all select * from function_checks
union all select * from privilege_checks
order by check_type, object_name;
