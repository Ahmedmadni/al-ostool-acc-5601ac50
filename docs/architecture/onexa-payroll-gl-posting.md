# ONEXA payroll to general-ledger posting

Gate 37 completes the controlled accounting handoff from approved payroll to
project/department cost, employee liabilities and the general ledger.

## Posting contract

The payroll run remains the operational source. Gate 8 remains the authoritative
cost-ledger handoff. Gate 37 posts only when every non-zero payroll line has its
immutable cost entry and total employer cost agrees with that ledger.

The accounting equation is:

- Debit `payroll_expense_or_project_cost`, grouped by project and department.
- Credit `employee_payables` for net salaries.
- Credit `gosi_payable` for employee and employer GOSI.
- Credit `employee_loans_receivable` for payroll loan recovery.

Attendance and leave reductions reduce earned payroll cost before posting. A
run whose accounting equation does not reconcile is rejected rather than being
forced into a suspense account.

## Transaction and controls

The posting RPC runs in one PostgreSQL transaction. It obtains an advisory lock,
locks the payroll run and lines, checks the current attendance snapshot, checks
Gate 8 cost rows and validates legal-entity/branch ownership. The preparer cannot
post the same run. A safe retry returns the already-created journal ID.

The function delegates journal creation to the B4 accounting adapter and does
not expose direct writes to the posting-run table. RLS restricts reporting to the
claimed tenant, while both reporting views use `security_invoker`.

## Activation

Keep `VITE_ENABLE_ONEXA_PAYROLL_POSTING` false. Apply the Gate 37 package, run
the read-only postcheck, install the AOA mappings, repeat the postcheck, then run
the rollback smoke test. The smoke test never commits production changes.
