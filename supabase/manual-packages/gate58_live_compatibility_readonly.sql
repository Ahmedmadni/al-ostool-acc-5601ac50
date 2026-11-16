-- ONEXA G58 LIVE CATALOG PARITY — STRICT SELECT ONLY.
-- Does not read customer journal data, change roles, change flags or create rows.
-- Run with authorized catalog access; no guarantee of readiness from presence alone.
with checks(label,installed) as (
  values
  ('g58_create_rpc', to_regprocedure('public.onexa_create_manual_journal(uuid,uuid,date,text,text,text,text,jsonb)') is not null),
  ('g58_submit_approval_rpc', to_regprocedure('public.onexa_transition_manual_journal(uuid,text,text)') is not null),
  ('g58_post_rpc', to_regprocedure('public.onexa_post_manual_journal(uuid)') is not null),
  ('g58_reverse_rpc', to_regprocedure('public.onexa_reverse_manual_journal(uuid,date,text,text)') is not null),
  ('b4_post_rpc', to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is not null),
  ('b4_reverse_rpc', to_regprocedure('public.onexa_reverse_journal(uuid,date,text,text)') is not null),
  ('g58_reconciliation_view', to_regclass('public.onexa_manual_journal_reconciliation') is not null),
  ('g58_manual_journals', to_regclass('public.onexa_manual_journals') is not null),
  ('g58_manual_journal_lines', to_regclass('public.onexa_manual_journal_lines') is not null),
  ('g58_manual_journal_events', to_regclass('public.onexa_manual_journal_events') is not null)
)
select label, case when installed then 'PRESENT' else 'MISSING' end as catalog_state
from checks order by label;

with create_fn as (
  select to_regprocedure('public.onexa_create_manual_journal(uuid,uuid,date,text,text,text,text,jsonb)') as oid
)
select
  oid is not null as create_rpc_present,
  case when oid is null then false else
    pg_get_functiondef(oid::oid) like '%or debit is null or credit is null%'
  end as rejects_missing_amount_side,
  case when oid is null then false else
    pg_get_functiondef(oid::oid) like '%_period_code <> to_char(_accounting_date,%'
  end as rejects_date_period_mismatch,
  case when oid is null then null else md5(pg_get_functiondef(oid::oid)) end as current_definition_md5
from create_fn;

select
  c.relname as table_name, c.relrowsecurity as rls_enabled,
  (select count(*) from pg_policies p where p.schemaname='public'
    and p.tablename=c.relname and p.cmd in ('SELECT','ALL')) as readable_policies
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
  and c.relname in ('onexa_manual_journals','onexa_manual_journal_lines','onexa_manual_journal_events')
order by c.relname;

select
  p.proname as function_name,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
  not has_function_privilege('anon',p.oid,'EXECUTE') as anon_cannot_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
where p.proname in ('onexa_create_manual_journal','onexa_transition_manual_journal',
  'onexa_post_manual_journal','onexa_reverse_manual_journal')
order by p.proname;
