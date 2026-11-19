-- Gate 58 / B4 installed source-contract inspection.
-- STRICT SELECT-ONLY. Reads pg_catalog definitions, no journal contents.
-- Does not provision, post, reverse, mutate tenant data or grant rights.
with expected(schema_name,function_name,identity_arguments,observed_md5) as (
 values
 ('public','onexa_post_journal','uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb',
  '0f8adeaf5c85cd470f1c1a29b6545376'),
 ('public','onexa_reverse_journal','uuid,date,text,text',
  'ac77042a26c0c954a7f26402a583f52e'),
 ('public','onexa_post_journal_unchecked','uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb',
  '51db95c8878a9ff78db87cc1cef7ae3d'),
 ('public','onexa_reverse_journal_unchecked','uuid,date,text,text',
  '9f9b4798858ca441280c07de774769f4'),
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
 case when function_oid is null then null else has_function_privilege('authenticated',function_oid,'EXECUTE') end
   as authenticated_can_execute,
 case when function_oid is null then null else has_function_privilege('anon',function_oid,'EXECUTE') end
   as anon_can_execute,
 case when function_oid is null then null else pg_get_userbyid(
   (select proowner from pg_proc where oid=function_oid::oid)) end as owner,
 case when function_oid is null then null else
   (select prosecdef from pg_proc where oid=function_oid::oid) end as is_security_definer,
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
   else null end as private_post_uses_idempotency_registry,
 case when function_name = 'post_journal' and schema_name = 'onexa_private'
   then ddl like '%ONEXA_B4_POSTING_PAYLOAD_CONFLICT%'
   else null end as private_post_checks_retry_payload,
 case when function_name = 'post_journal' and schema_name = 'onexa_private'
   then ddl like '%l.dimensions%' and ddl like '%h.source_snapshot%'
   else null end as private_post_compares_full_ledger_receipt,
 case when function_name = 'reverse_journal' and schema_name = 'onexa_private'
   then ddl like '%ONEXA_B4_REVERSAL_PAYLOAD_CONFLICT%'
   else null end as private_reverse_checks_replay_payload,
 case when function_name = 'reverse_journal' and schema_name = 'onexa_private'
   then ddl like '%ONEXA_B4_REVERSAL_RECEIPT_INVALID%'
   else null end as private_reverse_validates_new_receipt
from definitions
order by schema_name,function_name;

-- Direct private-function execution is a narrower security question than
-- whether PostgREST exposes a schema. Both layers require separate review.
select has_schema_privilege('authenticated','onexa_private','USAGE')
    as authenticated_has_private_schema_usage,
  has_function_privilege('authenticated',
    'onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
    'EXECUTE') as authenticated_can_execute_private_post,
  has_function_privilege('authenticated',
    'onexa_private.reverse_journal(uuid,date,text,text)',
    'EXECUTE') as authenticated_can_execute_private_reverse,
  has_function_privilege('authenticated',
    'public.onexa_post_journal_unchecked(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)',
    'EXECUTE') as authenticated_can_execute_unchecked_post,
  has_function_privilege('authenticated',
    'public.onexa_reverse_journal_unchecked(uuid,date,text,text)',
    'EXECUTE') as authenticated_can_execute_unchecked_reverse;


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
-- Ledger constraints are independent from the post_journal RPC body.
-- Report only definitions and readiness, never read customer journal rows.
with expected(constraint_name) as (
  values ('onexa_journal_headers_source_document_type_check'),
         ('onexa_journal_headers_check')
), observed as (
 select e.constraint_name,pg_get_constraintdef(c.oid,true) as definition
 from expected e
 left join pg_constraint c
   on c.conrelid=to_regclass('public.onexa_journal_headers')
  and c.conname=e.constraint_name
)
select constraint_name,
       definition,
       case when definition is null then 'MISSING'
            when constraint_name='onexa_journal_headers_source_document_type_check'
              and definition like '%''manual_journal''%'
              then 'INCLUDES_MANUAL_JOURNAL'
            when constraint_name='onexa_journal_headers_source_document_type_check'
              then 'MANUAL_JOURNAL_BLOCKED'
            when constraint_name='onexa_journal_headers_check'
              and definition = 'CHECK (total_debit = total_credit)'
              then 'EXACT_BALANCE'
            else 'PERMISSIVE_OR_DRIFTED'
       end as operational_readiness
from observed order by constraint_name;

-- Gate58 reversal RPC has its own safety boundary and may be deployed later
-- than B4. These source-body checks do not inspect customer data.
select
  to_regprocedure('public.onexa_reverse_manual_journal(uuid,date,text,text)')
    is not null as manual_reverse_rpc_installed,
  case when to_regprocedure('public.onexa_reverse_manual_journal(uuid,date,text,text)') is null
    then null
    else pg_get_functiondef(
      to_regprocedure('public.onexa_reverse_manual_journal(uuid,date,text,text)')::oid
    ) like '%ONEXA_MANUAL_JOURNAL_REVERSAL_REPLAY_CONFLICT%'
  end as manual_reverse_checks_replay_payload;
