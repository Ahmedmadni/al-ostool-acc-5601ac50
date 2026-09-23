# Gate 42: direct project cost accrual to B4

This vertical slice records a new, unpaid direct cost incurred for a project.
The source is an ONEXA `project_cost` business document owned by Projects;
it does not consume or copy a historical `cost_entries`, payroll run, purchase
invoice, or inventory issue. Those sources already have their own accounting
flows and must not be entered again here.

The project and cost center are selected from manually confirmed, tenant,
legal entity and branch scoped `onexa_project_cost_centers`. A separate source
reference must be unique across posted project costs of one tenant/entity.
It is an operational duplicate guard, not a substitute for checking whether
the same invoice or wage was posted through another module. The approver and
poster must differ from the document creator.

After approval, `onexa_post_project_cost` checks the document, dimensions,
account mappings, source reference, tenant scope, permissions and fiscal
period, then calls B4 `onexa_post_journal` once in the same transaction:

| Debit | Credit | Amount |
| --- | --- | ---: |
| Confirmed project WIP or direct expense | | Recognized cost |
| | Confirmed unpaid cost accrual / clearing liability | Recognized cost |

No VAT or cash settlement is recognized here. Settling the accrued liability
needs a separate approved payment/clearing flow; Gate 42 does not implement
that settlement. The journal keeps project and cost center dimensions.
Posted documents are immutable. Corrections require B4 reversal and a new
source revision; this stage provides no reversal UI.

`onexa_project_cost_reconciliation` is a security-invoker view. Client writes
to posting/center tables are denied. The UI and service are fail closed behind
`VITE_ENABLE_ONEXA_POSTING` and `VITE_ENABLE_ONEXA_PROJECT_COST_POSTING`.
The SQL package remains manual and unapplied until the planned rollout.
