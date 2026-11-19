-- Gate37 integration parents in disposable ONEXA B4 real SQL job ONLY.
-- Synthetic HR tables and FAKE Gate7/8 helpers are for compilation and
-- boundary checks: they DO NOT simulate a real attendance/cost migration.
do $preflight$
begin
 if current_database()<>'onexa_gate_test'
    or to_regclass('public.fixture_module_grants') is null
    or to_regclass('public.onexa_journal_lines') is null
    or to_regclass('public.onexa_fiscal_periods') is null then
  raise exception 'ONEXA_GATE37_HR_FIXTURE_DISPOSABLE_ONLY';
 end if;
end $preflight$;

create table public.hr_payroll_runs(
  id uuid primary key,tenant_id text not null,run_no text not null,
  status text not null,period_year integer not null,period_month integer not null,
  attendance_period_id uuid,created_by uuid not null
);
create table public.hr_employees(
  id uuid primary key,tenant_id text not null,department_id uuid
);
create table public.projects(
  id uuid primary key,tenant_id text not null
);
create table public.cost_entries(
  id uuid primary key,tenant_id text not null,project_id uuid,
  meta jsonb not null default '{}'::jsonb,amount numeric(20,4) not null
);
create table public.hr_payroll_lines(
  id uuid primary key,run_id uuid not null references public.hr_payroll_runs(id),
  tenant_id text not null,employee_id uuid not null references public.hr_employees(id),
  project_id uuid,cost_entry_id uuid,
  gross_salary numeric(20,4) not null,overtime numeric(20,4) not null,
  unpaid_leave_deduction numeric(20,4) not null,
  sick_leave_deduction numeric(20,4) not null,
  absence_deduction numeric(20,4) not null,
  late_deduction numeric(20,4) not null,
  gosi_employer numeric(20,4) not null,
  net_salary numeric(20,4) not null,
  gosi_employee numeric(20,4) not null,
  loan_deduction numeric(20,4) not null
);

-- Minimal FAKE payroll approval/cost calculations; real Gate7/8 must be
-- restored and independently qualified, never replaced with these stubs.
create function public.hr_payroll_attendance_is_stale(uuid)
returns boolean language sql stable as $$ select false $$;
create function public.hr_payroll_employer_cost(
 numeric,numeric,numeric,numeric,numeric,numeric,numeric)
returns numeric language sql immutable as $$
 select round(coalesce($1,0)+coalesce($2,0)-coalesce($3,0)
 -coalesce($4,0)-coalesce($5,0)-coalesce($6,0)+coalesce($7,0),2)
$$;

insert into public.fixture_module_grants(tenant_id,user_id,module_key,action)
select m.tenant_id,m.user_id,'people',a.action
from public.onexa_workspace_memberships m
cross join (values ('read'),('post')) a(action)
on conflict do nothing;

insert into public.onexa_account_role_mappings(
 tenant_id,legal_entity_id,account_role,account_code,is_active)
select 'tenant-smoke-A','a0000000-0000-4000-8000-000000000001'::uuid,
  role,account,true
from (values
 ('payroll_expense_or_project_cost','5200'),('employee_payables','2100'),
 ('gosi_payable','2100'),('employee_loans_receivable','5200')
) x(role,account);

insert into public.hr_payroll_runs(
 id,tenant_id,run_no,status,period_year,period_month,created_by)
values('a0000000-0000-4000-8000-000000009037','tenant-smoke-A',
 'SIM-PAY-2026-11','paid',2026,11,'a0000000-0000-4000-8000-000000000012');

insert into public.hr_employees(id,tenant_id,department_id)
values('a0000000-0000-4000-8000-000000009038','tenant-smoke-A',null);
insert into public.projects(id,tenant_id)
values('a0000000-0000-4000-8000-000000009039','tenant-smoke-A');

insert into public.cost_entries(id,tenant_id,project_id,meta,amount)
values(
 'a0000000-0000-4000-8000-000000009041','tenant-smoke-A',
 'a0000000-0000-4000-8000-000000009039',
 '{"source":"hr_payroll","payroll_line_id":"a0000000-0000-4000-8000-000000009040"}'::jsonb,
 1000.00
);
insert into public.hr_payroll_lines(
 id,run_id,tenant_id,employee_id,project_id,cost_entry_id,
 gross_salary,overtime,unpaid_leave_deduction,sick_leave_deduction,
 absence_deduction,late_deduction,gosi_employer,
 net_salary,gosi_employee,loan_deduction
) values(
 'a0000000-0000-4000-8000-000000009040',
 'a0000000-0000-4000-8000-000000009037','tenant-smoke-A',
 'a0000000-0000-4000-8000-000000009038',
 'a0000000-0000-4000-8000-000000009039',
 'a0000000-0000-4000-8000-000000009041',
 1000,0,0,0,0,0,0,1000,0,0
);
