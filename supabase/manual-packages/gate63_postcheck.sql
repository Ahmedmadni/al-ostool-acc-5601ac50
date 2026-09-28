select check_name,status from (values
  ('instances_table',case when to_regclass('public.onexa_approval_instances') is not null then 'READY' else 'MISSING' end),
  ('decisions_table',case when to_regclass('public.onexa_approval_decisions') is not null then 'READY' else 'MISSING' end),
  ('task_inbox',case when to_regclass('public.onexa_approval_task_inbox') is not null then 'READY' else 'MISSING' end),
  ('actor_matcher',case when to_regprocedure('onexa_private.approval_actor_matches_step(uuid,uuid,uuid)') is not null then 'READY' else 'MISSING' end),
  ('transition_runtime',case when to_regprocedure('public.onexa_transition_business_document(uuid,text,text)') is not null then 'READY' else 'MISSING' end)
) checks(check_name,status) order by check_name;
