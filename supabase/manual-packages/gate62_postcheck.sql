select check_name, status
from (values
  ('workflows_table', case when to_regclass('public.onexa_approval_workflows') is not null then 'READY' else 'MISSING' end),
  ('steps_table', case when to_regclass('public.onexa_approval_workflow_steps') is not null then 'READY' else 'MISSING' end),
  ('audit_table', case when to_regclass('public.onexa_approval_workflow_audit') is not null then 'READY' else 'MISSING' end),
  ('save_rpc', case when to_regprocedure('public.onexa_save_approval_workflow(jsonb)') is not null then 'READY' else 'MISSING' end),
  ('separation_policy', case when to_regprocedure('public.onexa_approval_separation_required(text,text)') is not null then 'READY' else 'MISSING' end)
) checks(check_name,status)
order by check_name;
