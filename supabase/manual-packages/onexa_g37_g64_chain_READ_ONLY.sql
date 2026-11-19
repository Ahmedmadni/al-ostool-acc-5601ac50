-- ONEXA Payroll Gate7/8/37 + Approval Gate64 prerequisite catalogue.
-- SELECT ONLY over pg_catalog and information_schema. No finance data rows.
-- Never use the presence of functions as financial release approval.
with required(stage,check_code,kind,object_ref,extra) as (
  values
    ('G7_PRE','attendance_periods','relation','public.hr_attendance_periods',''),
    ('G7_PRE','attendance_days','relation','public.hr_attendance_days',''),
    ('G7_PRE','payroll_runs','relation','public.hr_payroll_runs',''),
    ('G7_PRE','payroll_lines','relation','public.hr_payroll_lines',''),
    ('G7_PRE','cost_entries','relation','public.cost_entries',''),
    ('G7_PRE','cost_periods','relation','public.cost_periods',''),
    ('G7_PRE','lock_attendance','function','public.hr_attendance_lock_periods(date,date)',''),
    ('G7_PRE','apply_attendance','function','public.hr_apply_attendance_to_payroll(uuid)',''),
    ('G7_PRE','sync_costs','function','public.hr_sync_payroll_cost_entries(uuid)',''),
    ('G7_INST','snapshot_hash','function','public.hr_attendance_payroll_snapshot_hash(uuid)',''),
    ('G7_INST','stale_attendance','function','public.hr_payroll_attendance_is_stale(uuid)',''),
    ('G7_INST','apply_attendance_core','function','public.hr_apply_attendance_to_payroll_gate7_core(uuid)',''),
    ('G7_INST','cost_sync_core','function','public.hr_sync_payroll_cost_entries_gate7_core(uuid)',''),
    ('G7_INST','payroll_status_guard_fn','function','public.hr_payroll_attendance_status_guard()',''),
    ('G7_INST','payroll_line_guard_fn','function','public.hr_payroll_line_gate7_guard()',''),
    ('G7_INST','cost_source_unique','relation','public.uq_cost_entries_hr_payroll_line_source',''),
    ('G7_INST','attendance_snapshot_column','column','public.hr_payroll_runs','attendance_snapshot_hash'),
    ('G7_INST','payroll_status_trigger','trigger','public.hr_payroll_runs','trg_hr_payroll_runs_attendance_status_guard'),
    ('G7_INST','payroll_line_trigger','trigger','public.hr_payroll_lines','trg_hr_payroll_lines_gate7_guard'),
    ('G8_PRE','cost_period_status_fn','function','public.cost_period_set_status(text,boolean,text)',''),
    ('G8_INST','employer_cost_fn','function','public.hr_payroll_employer_cost(numeric,numeric,numeric,numeric,numeric,numeric,numeric)',''),
    ('G37_INST','payroll_journal_rpc','function','public.onexa_post_payroll_run(uuid,uuid,uuid,text)',''),
    ('G37_INST','payroll_postings','relation','public.onexa_payroll_posting_runs',''),
    ('G37_INST','payroll_reconciliation','relation','public.onexa_payroll_accounting_reconciliation',''),
    ('G64_PRE','approval_instances','relation','public.onexa_approval_instances',''),
    ('G64_PRE','approval_decisions','relation','public.onexa_approval_decisions',''),
    ('G64_PRE','approval_assignment_fn','function','onexa_private.approval_actor_matches_step(uuid,uuid,uuid)',''),
    ('G64_PRE','approval_segregation_fn','function','public.onexa_approval_separation_required(text,text)',''),
    ('G64_PRE','sales_rpc','function','public.onexa_post_sales_invoice(uuid,text)',''),
    ('G64_PRE','purchase_rpc','function','public.onexa_post_purchase_invoice(uuid,text)',''),
    ('G64_PRE','customer_receipt_rpc','function','public.onexa_post_customer_receipt(uuid,text)',''),
    ('G64_PRE','supplier_payment_rpc','function','public.onexa_post_supplier_payment(uuid,text)',''),
    ('G64_PRE','bank_transfer_rpc','function','public.onexa_post_bank_transfer(uuid,text)',''),
    ('G64_PRE','project_cost_rpc','function','public.onexa_post_project_cost(uuid,text)',''),
    ('G64_PRE','fleet_trip_rpc','function','public.onexa_post_fleet_trip_cost(uuid,text)','')
),
observed as (
 select r.*,
   case
     when kind='relation' then to_regclass(object_ref) is not null
     when kind='function' then to_regprocedure(object_ref) is not null
     when kind='column' then exists (
       select 1 from information_schema.columns c
       where c.table_schema=split_part(object_ref,'.',1)
         and c.table_name=split_part(object_ref,'.',2)
         and c.column_name=extra
     )
     when kind='trigger' then exists (
       select 1 from pg_trigger t
       where t.tgrelid=to_regclass(object_ref)
         and t.tgname=extra and not t.tgisinternal and t.tgenabled<>'D'
     )
     else false
   end as present
 from required r
)
select stage,check_code,kind,object_ref,extra,present,
  case when present then 'PRESENT_NOT_FINANCE_APPROVED'
       else 'MISSING_HOLD' end as catalog_status
from observed order by stage,check_code;
