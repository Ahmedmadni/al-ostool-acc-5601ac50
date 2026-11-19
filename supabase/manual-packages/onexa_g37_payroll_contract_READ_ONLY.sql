-- ONEXA Gate37 approved/paid -> strict B4 accounting readiness.
-- STRICTLY SELECT ONLY from pg_catalog/information_schema. It never reads
-- payrolls, employees, original GL lines, tenant rows or financial balances.
-- All checks require independently restored Staging E2E for actual release.
with observed as (
 select
   pg_get_functiondef(
     to_regprocedure('public.onexa_post_payroll_run(uuid,uuid,uuid,text)')::oid
   ) as sql_def,
   (select pg_get_constraintdef(oid,true) from pg_constraint
    where conrelid=to_regclass('public.onexa_payroll_posting_runs')
      and conname='onexa_payroll_posting_runs_balanced') as balance_def
), checks(check_code,installed) as (
 select 'PAYROLL_RPC_INSTALLED', sql_def is not null from observed
 union all
 select 'PAYROLL_CANONICAL_B4_APPROVED',
    sql_def like '%_source_status => ''approved''%' from observed
 union all
 select 'PAYROLL_POSTS_PAID_AFTER_APPROVAL',
    sql_def like '%_run.status::text not in (''approved'', ''paid'')%' from observed
 union all
 select 'PAYROLL_TENANT_RUN_SCOPED',
    sql_def like '%where id = _payroll_run_id and tenant_id = _tenant_id for update%' from observed
 union all
 select 'PAYROLL_TENANT_LINES_SCOPED',
    sql_def like '%ONEXA_PAYROLL_SOURCE_TENANT_MISMATCH%' from observed
 union all
 select 'PAYROLL_TENANT_EMPLOYEE_SCOPED',
    sql_def like '%ONEXA_PAYROLL_EMPLOYEE_TENANT_MISMATCH%' from observed
 union all
 select 'PAYROLL_TENANT_PROJECT_SCOPED',
    sql_def like '%ONEXA_PAYROLL_PROJECT_TENANT_MISMATCH%' from observed
 union all
 select 'PAYROLL_TENANT_COST_SCOPED',
    sql_def like '%and cost.tenant_id = _tenant_id%' from observed
 union all
 select 'PAYROLL_RETRY_PAYLOAD_VERIFIED',
    sql_def like '%ONEXA_PAYROLL_POSTING_RETRY_CONFLICT%'
      and sql_def like '%h.source_snapshot = _expected_snapshot%' from observed
 union all
 select 'PAYROLL_RETRY_LEDGER_LINES_VERIFIED',
    sql_def like '%= _journal_lines%'
      and sql_def like '%order by l.line_number%' from observed
 union all
 select 'PAYROLL_EXACT_FINANCIAL_EQUATION',
    sql_def like '%_employer_cost <> (_net_pay + _gosi_payable + _loan_recovery)%'
      and sql_def like '%_cost_ledger_amount <> _employer_cost%' from observed
 union all
 select 'PAYROLL_NO_001_TOLERANCE',
    sql_def is not null and sql_def not like '%0.01%' from observed
 union all
 select 'PAYROLL_EXACT_BALANCE_CONSTRAINT',
    balance_def is not null and
    balance_def like '%employer_cost = (net_pay + gosi_payable + loan_recovery)%'
    and balance_def like '%employer_cost = cost_ledger_amount%'
    and balance_def not like '%0.01%' from observed
 union all
 select 'PAYROLL_RLS_ENABLED',
    coalesce((select relrowsecurity from pg_class
       where oid=to_regclass('public.onexa_payroll_posting_runs')),false)
 union all
 select 'PAYROLL_SOURCE_TENANT_COLUMNS',
    (select count(*)=5 from information_schema.columns c
      where c.table_schema='public' and c.column_name='tenant_id'
      and c.table_name in ('hr_payroll_runs','hr_payroll_lines',
       'cost_entries','hr_employees','projects'))
)
select check_code, case when installed then 'CATALOG_PRESENT_STAGING_REQUIRED'
                        else 'HOLD' end as catalog_status
from checks order by check_code;
