-- ONEXA Gate 37: approved payroll -> project/department cost -> liabilities -> GL.
-- Manual review package. Keep VITE_ENABLE_ONEXA_PAYROLL_POSTING disabled until
-- the account mapping, postcheck and rollback-only smoke test all pass.

begin;

do $$
begin
  if to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is null then
    raise exception 'ONEXA_B4_POST_JOURNAL_SIGNATURE_REQUIRED';
  end if;
  if to_regclass('public.hr_payroll_runs') is null
     or to_regclass('public.hr_payroll_lines') is null
     or to_regclass('public.cost_entries') is null then
    raise exception 'ONEXA_PAYROLL_COST_FOUNDATION_REQUIRED';
  end if;
  if to_regprocedure('public.hr_payroll_attendance_is_stale(uuid)') is null
     or to_regprocedure('public.hr_payroll_employer_cost(numeric,numeric,numeric,numeric,numeric,numeric,numeric)') is null then
    raise exception 'ONEXA_GATE8_PAYROLL_COST_LEDGER_REQUIRED';
  end if;
  if to_regclass('public.onexa_account_role_mappings') is null
     or to_regprocedure('onexa_private.has_module_action(uuid,text,text)') is null then
    raise exception 'ONEXA_ACCOUNTING_AUTHORIZATION_FOUNDATION_REQUIRED';
  end if;
end;
$$;

create table if not exists public.onexa_payroll_posting_runs (
  payroll_run_id uuid primary key references public.hr_payroll_runs(id) on delete restrict,
  tenant_id text not null,
  legal_entity_id uuid not null references public.onexa_legal_entities(id),
  branch_id uuid not null references public.onexa_branches(id),
  journal_id uuid not null unique,
  source_revision integer not null default 1 check (source_revision = 1),
  employer_cost numeric(20, 4) not null check (employer_cost >= 0),
  net_pay numeric(20, 4) not null check (net_pay >= 0),
  gosi_payable numeric(20, 4) not null check (gosi_payable >= 0),
  loan_recovery numeric(20, 4) not null check (loan_recovery >= 0),
  cost_ledger_amount numeric(20, 4) not null check (cost_ledger_amount >= 0),
  employee_count integer not null check (employee_count > 0),
  posted_by uuid not null,
  posted_at timestamptz not null default now(),
  constraint onexa_payroll_posting_runs_balanced check (
    abs(employer_cost - (net_pay + gosi_payable + loan_recovery)) <= 0.01
    and abs(employer_cost - cost_ledger_amount) <= 0.01
  )
);

create index if not exists onexa_payroll_posting_runs_journal_idx
  on public.onexa_payroll_posting_runs (tenant_id, legal_entity_id, journal_id);

alter table public.onexa_payroll_posting_runs enable row level security;
drop policy if exists onexa_payroll_posting_runs_select_tenant on public.onexa_payroll_posting_runs;
create policy onexa_payroll_posting_runs_select_tenant
  on public.onexa_payroll_posting_runs for select to authenticated
  using (
    tenant_id = onexa_private.claim_tenant_id()
    and onexa_private.has_module_action(auth.uid(), 'people', 'read')
  );

create or replace view public.onexa_payroll_accounting_reconciliation
with (security_invoker = true)
as
with payroll as (
  select
    run.id as payroll_run_id, run.run_no, run.period_year, run.period_month,
    run.status::text as payroll_status, run.attendance_period_id,
    count(line.id)::integer as employees_count,
    coalesce(sum(public.hr_payroll_employer_cost(
      line.gross_salary, line.overtime, line.unpaid_leave_deduction,
      line.sick_leave_deduction, line.absence_deduction,
      line.late_deduction, line.gosi_employer
    )), 0) as employer_cost,
    coalesce(sum(line.net_salary), 0) as net_pay,
    coalesce(sum(line.gosi_employee + line.gosi_employer), 0) as gosi_payable,
    coalesce(sum(line.loan_deduction), 0) as loan_recovery,
    count(line.id) filter (where public.hr_payroll_employer_cost(
      line.gross_salary, line.overtime, line.unpaid_leave_deduction,
      line.sick_leave_deduction, line.absence_deduction,
      line.late_deduction, line.gosi_employer
    ) <> 0)::integer as expected_cost_line_count,
    count(line.cost_entry_id)::integer as cost_line_count,
    coalesce(sum(cost.amount), 0) as cost_ledger_amount
  from public.hr_payroll_runs run
  left join public.hr_payroll_lines line on line.run_id = run.id
  left join public.cost_entries cost on cost.id = line.cost_entry_id
    and coalesce(cost.meta->>'source', '') = 'hr_payroll'
    and cost.meta->>'payroll_line_id' = line.id::text
  group by run.id, run.run_no, run.period_year, run.period_month,
    run.status, run.attendance_period_id
)
select
  payroll.*,
  posting.legal_entity_id,
  posting.branch_id,
  posting.journal_id as posted_journal_id,
  case
    when payroll.payroll_status not in ('approved', 'paid') then 'not_approved'
    when public.hr_payroll_attendance_is_stale(payroll.payroll_run_id) then 'attendance_stale'
    when payroll.cost_line_count <> payroll.expected_cost_line_count then 'cost_sync_pending'
    when abs(payroll.cost_ledger_amount - payroll.employer_cost) > 0.01 then 'cost_value_mismatch'
    when posting.payroll_run_id is null then 'not_posted'
    when posting.journal_id is null then 'journal_missing'
    when abs(posting.employer_cost - (posting.net_pay + posting.gosi_payable + posting.loan_recovery)) > 0.01
      then 'journal_unbalanced'
    else 'reconciled'
  end as reconciliation_status
from payroll
left join public.onexa_payroll_posting_runs posting
  on posting.payroll_run_id = payroll.payroll_run_id;

create or replace view public.onexa_payroll_posting_configuration_gaps
with (security_invoker = true)
as
with required_roles(account_role) as (
  values
    ('payroll_expense_or_project_cost'::text),
    ('employee_payables'::text),
    ('gosi_payable'::text),
    ('employee_loans_receivable'::text)
)
select entity.tenant_id, entity.id as legal_entity_id,
  entity.code as legal_entity_code, required.account_role
from public.onexa_legal_entities entity
cross join required_roles required
left join public.onexa_account_role_mappings mapping
  on mapping.tenant_id = entity.tenant_id
 and mapping.legal_entity_id = entity.id
 and mapping.account_role = required.account_role
 and mapping.is_active = true
where entity.is_active = true and mapping.id is null;

create or replace function public.onexa_post_payroll_run(
  _payroll_run_id uuid,
  _legal_entity_id uuid,
  _branch_id uuid,
  _period_code text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _run public.hr_payroll_runs%rowtype;
  _group record;
  _payroll_expense text;
  _employee_payables text;
  _gosi_payable_account text;
  _employee_loans text;
  _employer_cost numeric(20,4);
  _net_pay numeric(20,4);
  _gosi_payable numeric(20,4);
  _loan_recovery numeric(20,4);
  _cost_ledger_amount numeric(20,4);
  _employee_count integer;
  _expected_cost_count integer;
  _actual_cost_count integer;
  _accounting_date date;
  _journal_lines jsonb := '[]'::jsonb;
  _journal_id uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'people', 'post') then
    raise exception 'ONEXA_PAYROLL_POST_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_period_code), '') is null then
    raise exception 'ONEXA_FISCAL_PERIOD_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(_tenant_id || ':payroll:' || _payroll_run_id::text, 0));

  select * into _run from public.hr_payroll_runs
  where id = _payroll_run_id for update;
  if not found then raise exception 'ONEXA_PAYROLL_RUN_NOT_FOUND'; end if;

  select journal_id into _journal_id
  from public.onexa_payroll_posting_runs
  where payroll_run_id = _payroll_run_id and tenant_id = _tenant_id;
  if found then return _journal_id; end if;

  if _run.status::text not in ('approved', 'paid') then
    raise exception 'ONEXA_PAYROLL_RUN_MUST_BE_APPROVED';
  end if;
  if _actor = _run.created_by then
    raise exception 'ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR';
  end if;
  if public.hr_payroll_attendance_is_stale(_payroll_run_id) then
    raise exception 'ONEXA_PAYROLL_ATTENDANCE_SNAPSHOT_STALE';
  end if;
  if not exists (
    select 1 from public.onexa_legal_entities
    where id = _legal_entity_id and tenant_id = _tenant_id and is_active = true
  ) then raise exception 'ONEXA_LEGAL_ENTITY_NOT_FOUND'; end if;
  if not exists (
    select 1 from public.onexa_branches
    where id = _branch_id and legal_entity_id = _legal_entity_id
      and tenant_id = _tenant_id and is_active = true
  ) then raise exception 'ONEXA_BRANCH_NOT_FOUND'; end if;

  perform 1 from public.hr_payroll_lines
  where run_id = _payroll_run_id order by id for update;
  if not found then raise exception 'ONEXA_PAYROLL_LINES_REQUIRED'; end if;

  select
    count(*)::integer,
    coalesce(sum(public.hr_payroll_employer_cost(
      line.gross_salary, line.overtime, line.unpaid_leave_deduction,
      line.sick_leave_deduction, line.absence_deduction,
      line.late_deduction, line.gosi_employer
    )), 0),
    coalesce(sum(line.net_salary), 0),
    coalesce(sum(line.gosi_employee + line.gosi_employer), 0),
    coalesce(sum(line.loan_deduction), 0),
    count(*) filter (where public.hr_payroll_employer_cost(
      line.gross_salary, line.overtime, line.unpaid_leave_deduction,
      line.sick_leave_deduction, line.absence_deduction,
      line.late_deduction, line.gosi_employer
    ) <> 0)::integer,
    count(line.cost_entry_id)::integer,
    coalesce(sum(cost.amount), 0)
  into _employee_count, _employer_cost, _net_pay, _gosi_payable,
    _loan_recovery, _expected_cost_count, _actual_cost_count, _cost_ledger_amount
  from public.hr_payroll_lines line
  left join public.cost_entries cost on cost.id = line.cost_entry_id
    and coalesce(cost.meta->>'source', '') = 'hr_payroll'
    and cost.meta->>'payroll_line_id' = line.id::text
  where line.run_id = _payroll_run_id;

  if _actual_cost_count <> _expected_cost_count then
    raise exception 'ONEXA_PAYROLL_COST_SYNC_REQUIRED';
  end if;
  if abs(_cost_ledger_amount - _employer_cost) > 0.01 then
    raise exception 'ONEXA_PAYROLL_COST_LEDGER_MISMATCH';
  end if;
  if abs(_employer_cost - (_net_pay + _gosi_payable + _loan_recovery)) > 0.01 then
    raise exception 'ONEXA_PAYROLL_ACCOUNTING_EQUATION_MISMATCH';
  end if;

  select account_code into _payroll_expense from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id
    and account_role = 'payroll_expense_or_project_cost' and is_active = true;
  select account_code into _employee_payables from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id
    and account_role = 'employee_payables' and is_active = true;
  select account_code into _gosi_payable_account from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id
    and account_role = 'gosi_payable' and is_active = true;
  select account_code into _employee_loans from public.onexa_account_role_mappings
  where tenant_id = _tenant_id and legal_entity_id = _legal_entity_id
    and account_role = 'employee_loans_receivable' and is_active = true;
  if _payroll_expense is null or _employee_payables is null
     or _gosi_payable_account is null or _employee_loans is null then
    raise exception 'ONEXA_PAYROLL_ACCOUNT_MAPPING_REQUIRED';
  end if;

  for _group in
    select line.project_id, employee.department_id,
      sum(public.hr_payroll_employer_cost(
        line.gross_salary, line.overtime, line.unpaid_leave_deduction,
        line.sick_leave_deduction, line.absence_deduction,
        line.late_deduction, line.gosi_employer
      )) as amount
    from public.hr_payroll_lines line
    join public.hr_employees employee on employee.id = line.employee_id
    where line.run_id = _payroll_run_id
    group by line.project_id, employee.department_id
    order by line.project_id nulls last, employee.department_id nulls last
  loop
    if _group.amount <> 0 then
      _journal_lines := _journal_lines || jsonb_build_array(jsonb_build_object(
        'account_code', _payroll_expense, 'debit', _group.amount, 'credit', 0,
        'description', 'Payroll cost - ' || _run.run_no,
        'dimensions', jsonb_strip_nulls(jsonb_build_object(
          'legalEntity', _legal_entity_id, 'branch', _branch_id,
          'project', _group.project_id, 'department', _group.department_id
        ))
      ));
    end if;
  end loop;

  if _net_pay > 0 then
    _journal_lines := _journal_lines || jsonb_build_array(
      jsonb_build_object('account_code', _employee_payables, 'debit', 0, 'credit', _net_pay,
      'description', 'Employee payables - ' || _run.run_no,
      'dimensions', jsonb_build_object('legalEntity', _legal_entity_id, 'branch', _branch_id)));
  end if;
  if _gosi_payable > 0 then
    _journal_lines := _journal_lines || jsonb_build_array(
      jsonb_build_object('account_code', _gosi_payable_account, 'debit', 0, 'credit', _gosi_payable,
      'description', 'GOSI payable - ' || _run.run_no,
      'dimensions', jsonb_build_object('legalEntity', _legal_entity_id, 'branch', _branch_id)));
  end if;
  if _loan_recovery > 0 then
    _journal_lines := _journal_lines || jsonb_build_array(
      jsonb_build_object('account_code', _employee_loans, 'debit', 0, 'credit', _loan_recovery,
      'description', 'Employee loan recovery - ' || _run.run_no,
      'dimensions', jsonb_build_object('legalEntity', _legal_entity_id, 'branch', _branch_id)));
  end if;

  _accounting_date := (make_date(_run.period_year, _run.period_month, 1)
    + interval '1 month - 1 day')::date;

  select public.onexa_post_journal(
    _legal_entity_id => _legal_entity_id,
    _source_document_type => 'payroll_run',
    _source_document_id => _run.id::text,
    _source_revision => 1,
    _source_status => _run.status::text,
    _source_snapshot => jsonb_build_object(
      'run_no', _run.run_no, 'period_year', _run.period_year,
      'period_month', _run.period_month, 'attendance_period_id', _run.attendance_period_id,
      'employer_cost', _employer_cost, 'net_pay', _net_pay,
      'gosi_payable', _gosi_payable, 'loan_recovery', _loan_recovery,
      'posting_contract_version', 'payroll-v1'
    ),
    _accounting_date => _accounting_date,
    _period_code => btrim(_period_code),
    _currency => 'SAR',
    _memo => 'Payroll ' || _run.run_no,
    _lines => _journal_lines
  )::uuid into _journal_id;
  if _journal_id is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  insert into public.onexa_payroll_posting_runs (
    payroll_run_id, tenant_id, legal_entity_id, branch_id, journal_id,
    employer_cost, net_pay, gosi_payable, loan_recovery, cost_ledger_amount,
    employee_count, posted_by
  ) values (
    _run.id, _tenant_id, _legal_entity_id, _branch_id, _journal_id,
    _employer_cost, _net_pay, _gosi_payable, _loan_recovery,
    _cost_ledger_amount, _employee_count, _actor
  );
  return _journal_id;
end;
$$;

revoke all on table public.onexa_payroll_posting_runs from anon, authenticated;
grant select on table public.onexa_payroll_posting_runs to authenticated;
grant select on table public.onexa_payroll_accounting_reconciliation to authenticated;
grant select on table public.onexa_payroll_posting_configuration_gaps to authenticated;
revoke all on function public.onexa_post_payroll_run(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.onexa_post_payroll_run(uuid, uuid, uuid, text) to authenticated;

commit;
