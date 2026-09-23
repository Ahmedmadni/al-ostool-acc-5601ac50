# Gate 43: fleet trip direct cost accrual to B4

A completed tenant-owned `fleet_trips` row is mapped manually to one ONEXA
legal entity, branch and fleet cost center. Mapping also locks the vehicle
identity. This stage posts a new, unpaid charge attributable to that trip;
it does not post `fuel_cost`, `other_costs`, or legacy `fleet_fuel` rows.
Existing fuel, maintenance, supplier invoices, payroll and project costs must
not be entered again as trip charges.

The `fleet_trip_cost` document is owned by Logistics, linked to a confirmed
trip scope and has a unique external source reference across posted fleet
charges of one tenant/entity. After approval by a user other than its creator,
an authorized poster calls `onexa_post_fleet_trip_cost`, which validates the
live completed trip and its tenant/vehicle, amount, dimensions, account roles,
period and permissions. It calls B4 `onexa_post_journal` atomically:

| Debit | Credit | Amount |
| --- | --- | ---: |
| Confirmed logistics expense or project WIP | | New trip charge |
| | Confirmed unpaid accrual liability | New trip charge |

The posting registry enforces a unique journal and source reference and
supports safe retry. `onexa_fleet_trip_cost_reconciliation` is a security
invoker view; posting tables have tenant RLS, no authenticated writes, and
immutability after posting. A linked reversal and new revision are required
for corrections. Payment or clearing of the liability is outside Gate 43.

The role name `cash_ap_or_clearing` is inherited from the contract; this
implementation only accepts a **liability** account for it. Operational
source overlap still requires accounting review: identical costs entered in
another module cannot be inferred from free-text references alone.

Feature flags `VITE_ENABLE_ONEXA_POSTING` and
`VITE_ENABLE_ONEXA_FLEET_TRIP_COST_POSTING` remain disabled pending manual SQL,
confirmed mappings, postcheck and rollback smoke verification.
