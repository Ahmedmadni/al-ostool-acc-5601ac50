# ONEXA development acceptance — 2026-11-12

## Approved HR hardening: applied

The two changes approved November 8 were applied through
`drizzle/migrations/0002_hr_termination_two_approved_hardening_fixes.sql`.
The clearance RPC now rejects an employee outside the session tenant. Refresh
rejects negative and nonfinite manual leave-day overrides before updating any
settlement components. Existing function privileges were preserved.

Validation used a separate PostgreSQL 17 cluster with Unix socket only and
synthetic fixture data, never hosted customer records:

- Before repair: 30/32 passed; the two approved defects were reproduced.
- Candidate: 32/32 passed.
- Exact final applied migration: 32/32 passed.
- Persisted regression cases in `scripts/sql-fixtures/hr-hardening-regression.sql`
  both passed: -10 leave override rejects with no residual draft; tenant-A
  clearance rejects the known synthetic tenant-B employee.
- Production catalog read confirmed both new guards and authenticated EXECUTE;
  anonymous EXECUTE remains false for both RPCs.

The dependency helpers in the local fixture are simplified; this does not
certify all production role inheritance or full hosted UI acceptance.

## Gate 71: synthetic validation complete, production deferred

Actual Gate 71 SQL compiled in a second independent synthetic PostgreSQL cluster.
Eight readiness checks returned READY; anonymous table/view/RPC access was false,
authenticated reads and RPC access true, authenticated writes false, and no
invalid cross-tenant foreign-key references existed.

All 25 behavioral checks passed, covering no seeded mappings, entitlement without
scope, all three allowed alias/module pairs, bidirectional tenant isolation,
invoker-view filtering, invalid aliases/pairs, missing claim/user/membership,
anonymous denial, write denial, immutable mapping identity, composite tenant/entity
FK rejection, missing facilities permission, and inactive entity/member/scope.

Production catalog-only discovery confirmed Gate 71 remains absent and required
parent columns and helper signatures exist. It does not prove module semantics,
customer-clone equivalence, index-lock duration or restorable production backup.
The Gate 71 runbook explicitly stops without tested clone/backup evidence.
No Gate 71 production migration, provisioning, or feature activation was performed.

## Remaining development sequence

Order remains 71 → 72 → 73 → 42 → 74 → 64 → 75 → B4. Static source-contract
checks for 72, 73, 42, 74, 64, 75 and B2/B3 authorization passed. These are source
checks only; none of these later gates was executed in production or treated
as financially accepted. Their separate execution approvals remain missing.

## Hosted UI acceptance

The available injected session did not contain a usable tenant claim. Browser
navigation to `/hr/termination/new` remained on the loading screen; no save
button was available and no page errors were emitted. Save/readback/print
is not verified. No production test settlements or real journals were created.

## Next blockers

1. Gate 71: tested customer-clone/backup restore evidence and reviewed index-lock
   window; existing production approval does not replace those prerequisites.
2. Later gates: explicit production approval or separately approved independent
   testing execution plan.
3. Full save/readback/print: an independent hosted test environment and a working
   tenant-scoped session; do not insert synthetic settlements into production.