-- ONEXA Gate 34/35 read-only preflight.
-- Safe to run in Supabase SQL Editor. This file performs no writes.

with required_tables(object_name) as (
  values
    ('onexa_legal_entities'::text),
    ('onexa_branches'::text),
    ('onexa_module_entitlements'::text)
)
select
  'required_table' as check_type,
  object_name,
  case when to_regclass('public.' || object_name) is not null then 'ready' else 'missing' end as status,
  null::text as details
from required_tables

union all

select
  'b4_posting_function',
  'onexa_post_journal',
  case when to_regprocedure(
    'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'
  ) is not null then 'ready' else 'signature_mismatch_or_missing' end,
  'expected: (uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'

union all

select
  'gate34_state',
  'onexa_business_documents',
  case when to_regclass('public.onexa_business_documents') is null then 'not_installed' else 'already_installed' end,
  null::text

union all

select
  'gate35_state',
  'onexa_inventory_balances',
  case when to_regclass('public.onexa_inventory_balances') is null then 'not_installed' else 'already_installed' end,
  null::text
order by check_type, object_name;

-- Show the actual B4 overload(s). Copy this result if the expected signature
-- above is not ready; Gate 35 must then be adapted before execution.
select
  procedure.oid::regprocedure::text as function_signature,
  pg_get_function_result(procedure.oid) as return_type,
  procedure.prosecdef as security_definer,
  procedure.proconfig as function_settings,
  has_function_privilege('authenticated', procedure.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc procedure
join pg_namespace namespace on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.proname in ('onexa_post_journal', 'onexa_reverse_journal')
order by procedure.proname, procedure.oid::regprocedure::text;

-- Confirm the columns required by Gate 34 exist in the B1 foundation.
with required_columns(table_name, column_name) as (
  values
    ('onexa_legal_entities'::text, 'id'::text),
    ('onexa_legal_entities', 'tenant_id'),
    ('onexa_legal_entities', 'code'),
    ('onexa_legal_entities', 'is_active'),
    ('onexa_branches', 'id'),
    ('onexa_branches', 'tenant_id'),
    ('onexa_branches', 'legal_entity_id'),
    ('onexa_branches', 'is_active'),
    ('onexa_module_entitlements', 'tenant_id'),
    ('onexa_module_entitlements', 'module_key'),
    ('onexa_module_entitlements', 'is_enabled')
)
select
  required.table_name,
  required.column_name,
  case when columns.column_name is not null then 'ready' else 'missing' end as status,
  columns.data_type
from required_columns required
left join information_schema.columns columns
  on columns.table_schema = 'public'
 and columns.table_name = required.table_name
 and columns.column_name = required.column_name
order by required.table_name, required.column_name;

-- Read-only workspace context needed later for account-role mapping.
select
  entity.tenant_id,
  entity.id as legal_entity_id,
  entity.code as legal_entity_code,
  entity.name_ar,
  entity.is_active
from public.onexa_legal_entities entity
where entity.is_active = true
order by entity.tenant_id, entity.code;
