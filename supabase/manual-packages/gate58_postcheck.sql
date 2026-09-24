-- ONEXA Gate 58 postcheck. Read-only.
with expected(kind, object_name) as (
  values
    ('table','onexa_manual_journals'),
    ('table','onexa_manual_journal_lines'),
    ('table','onexa_manual_journal_events'),
    ('function','onexa_create_manual_journal'),
    ('function','onexa_transition_manual_journal'),
    ('function','onexa_post_manual_journal'),
    ('function','onexa_reverse_manual_journal'),
    ('view','onexa_manual_journal_reconciliation')
), present as (
  select 'table'::text as kind, c.relname as object_name
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
  union all
  select 'view', c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v'
  union all
  select 'function', p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
)
select expected.kind, expected.object_name,
       case when present.object_name is not null then 'READY' else 'MISSING' end as status
from expected
left join present using (kind, object_name)
order by expected.kind, expected.object_name;

select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('onexa_manual_journals','onexa_manual_journal_lines','onexa_manual_journal_events')
order by c.relname;

select
  routine_name,
  has_function_privilege(
    'authenticated',
    p.oid,
    'EXECUTE'
  ) as authenticated_can_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_cannot_execute
from information_schema.routines r
join pg_proc p on p.proname = r.routine_name
join pg_namespace n on n.oid = p.pronamespace and n.nspname = r.routine_schema
where r.routine_schema = 'public'
  and r.routine_name in (
    'onexa_create_manual_journal',
    'onexa_transition_manual_journal',
    'onexa_post_manual_journal',
    'onexa_reverse_manual_journal'
  )
order by routine_name;
