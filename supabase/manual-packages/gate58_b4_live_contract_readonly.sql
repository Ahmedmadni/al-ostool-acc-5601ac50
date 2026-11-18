-- Gate 58 / B4 installed source-contract inspection.
-- STRICT SELECT-ONLY. Reads pg_catalog definitions, no journal contents.
-- Does not provision, post, reverse, mutate tenant data or grant rights.
with expected(schema_name,function_name,identity_arguments,observed_md5) as (
 values
 ('public','onexa_post_journal','uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb',
  '0f8adeaf5c85cd470f1c1a29b6545376'),
 ('public','onexa_reverse_journal','uuid,date,text,text',
  'ac77042a26c0c954a7f26402a583f52e'),
 ('onexa_private','post_journal','uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb',
  '5ac58a780bbed49e8ba31b6f46c39f48'),
 ('onexa_private','reverse_journal','uuid,date,text,text',
  'f51a890027057a0e838c13cbfd6ddb61')
), catalog as (
 select e.*,
   to_regprocedure(format('%I.%I(%s)',
     e.schema_name,e.function_name,e.identity_arguments)) as function_oid
 from expected e
), definitions as (
 select *,
   case when function_oid is not null
     then pg_get_functiondef(function_oid::oid)
     else null end as ddl
 from catalog
)
select schema_name,function_name,function_oid is not null as installed,
 md5(ddl) as installed_md5,
 observed_md5 as catalog_md5_from_2026_11_18,
 md5(ddl) = observed_md5 as matches_verified_snapshot,
 case when function_name = 'post_journal' and schema_name = 'onexa_private'
   then ddl like '%onexa_fiscal_periods%' and ddl like '%p.status = ''open''%'
   else null end as private_post_requires_open_period,
 case when function_name = 'reverse_journal' and schema_name = 'onexa_private'
   then ddl like '%onexa_private.post_journal(%'
   else null end as reversal_routes_through_period_guard,
 case when function_name = 'post_journal' and schema_name = 'onexa_private'
   then ddl like '%abs(v_debit - v_credit) > 0.005%'
   else null end as current_core_has_half_cent_tolerance,
 case when function_name = 'post_journal' and schema_name = 'onexa_private'
   then ddl like '%onexa_posting_registry%'
   else null end as private_post_uses_idempotency_registry
from definitions
order by schema_name,function_name;

select
 to_regclass('public.onexa_fiscal_periods') is not null as fiscal_period_table_present,
 to_regclass('public.onexa_posting_registry') is not null as posting_registry_present,
 to_regclass('public.onexa_journal_headers') is not null as ledger_headers_present,
 to_regclass('public.onexa_journal_lines') is not null as ledger_lines_present,
 to_regclass('public.onexa_workspace_audit_events') is not null as workspace_audit_present,
 to_regprocedure('public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)') is not null
   as gate58_amendment_installed,
 to_regprocedure('public.onexa_post_manual_journal(uuid)') is not null
   as gate58_post_installed,
 to_regprocedure('public.onexa_reverse_manual_journal(uuid,date,text,text)') is not null
   as gate58_reverse_installed;
