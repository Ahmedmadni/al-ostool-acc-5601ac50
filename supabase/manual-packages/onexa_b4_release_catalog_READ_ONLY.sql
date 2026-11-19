-- ONEXA B4/ Gate58 proposed release catalog preflight.
-- STRICTLY SELECT-ONLY: pg_catalog metadata & privilege checks only.
-- This is a technical inventory, NOT authorization to modify production SQL.
-- Join with 17-check ledger integrity report, Staging E2E approvals and
-- documented restore rehearsal. "READY" here cannot certify live activation.
with installed as (
 select
   pg_get_functiondef(to_regprocedure(
     'onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)')::oid
   ) as b4_post,
   pg_get_functiondef(to_regprocedure(
     'onexa_private.reverse_journal(uuid,date,text,text)')::oid
   ) as b4_reverse,
   pg_get_functiondef(to_regprocedure(
     'public.onexa_post_manual_journal(uuid)')::oid
   ) as g58_post,
   pg_get_functiondef(to_regprocedure(
     'public.onexa_reverse_manual_journal(uuid,date,text,text)')::oid
   ) as g58_reverse,
   (select pg_get_constraintdef(c.oid,true)
    from pg_constraint c
    where c.conrelid=to_regclass('public.onexa_journal_headers')
      and c.conname='onexa_journal_headers_source_document_type_check'
      and c.contype='c') as source_types_check,
   (select pg_get_constraintdef(c.oid,true)
    from pg_constraint c
    where c.conrelid=to_regclass('public.onexa_journal_headers')
      and c.conname='onexa_journal_headers_check'
      and c.contype='c') as header_balance_check
),
checks(gate_code, is_ready) as (
 select 'GL_MANUAL_SOURCE_ALLOWED',
    source_types_check like '%''manual_journal''%' from installed
 union all
 select 'GL_HEADER_EXACTLY_BALANCED',
    header_balance_check = 'CHECK (total_debit = total_credit)' from installed
 union all
 select 'B4_STRICT_MONEY_CHECKS',
    b4_post like '%ONEXA_B4_STORAGE_PRECISION_INVALID%'
     and b4_post like '%ONEXA_B4_SAR_HALALA_PRECISION_INVALID%'
     and b4_post like '%v_debit <> v_credit%' from installed
 union all
 select 'B4_POST_RETRY_CONTENT_GUARD',
    b4_post like '%ONEXA_B4_POSTING_PAYLOAD_CONFLICT%' from installed
 union all
 select 'B4_REVERSE_RETRY_CONTENT_GUARD',
    b4_reverse like '%ONEXA_B4_REVERSAL_PAYLOAD_CONFLICT%'
      and b4_reverse like '%ONEXA_B4_REVERSAL_RECEIPT_INVALID%' from installed
 union all
 select 'G58_POST_REAL_GL_RECEIPT_VALIDATION',
    g58_post like '%ONEXA_MANUAL_JOURNAL_B4_POSTING_CONTRACT_MISMATCH%' from installed
 union all
 select 'G58_REVERSE_REPLAY_GL_VALIDATION',
    g58_reverse like '%ONEXA_MANUAL_JOURNAL_REVERSAL_REPLAY_CONFLICT%' from installed
 union all
 select 'G58_AMENDMENT_FUNCTION_INSTALLED',
    to_regprocedure('public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)') is not null
 union all
 select 'G58_TABLE_RLS_ENABLED',
    coalesce((select relrowsecurity from pg_class
       where oid=to_regclass('public.onexa_manual_journals')),false)
    and coalesce((select relrowsecurity from pg_class
       where oid=to_regclass('public.onexa_manual_journal_lines')),false)
    and coalesce((select relrowsecurity from pg_class
       where oid=to_regclass('public.onexa_manual_journal_events')),false)
 union all
 select 'B4_PRIVATE_POST_NOT_DIRECTLY_EXECUTABLE',
    not coalesce(has_function_privilege('authenticated',
      to_regprocedure(
        'onexa_private.post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'
      ),'EXECUTE'),false)
 union all
 select 'B4_PRIVATE_REVERSE_NOT_DIRECTLY_EXECUTABLE',
    not coalesce(has_function_privilege('authenticated',
      to_regprocedure('onexa_private.reverse_journal(uuid,date,text,text)')
      ,'EXECUTE'),false)
)
select gate_code,
  case when is_ready then 'READY' else 'HOLD' end as catalog_status
from checks order by gate_code;
