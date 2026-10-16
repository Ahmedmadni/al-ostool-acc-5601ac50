# Gate 77 — Run the real Gate 42 project-cost engine in an isolated PostgreSQL job

**Source and CI only; no connected customer database changes.** This is an additional job in `.github/workflows/native-tenant-sql-smoke.yml` independent of the earlier Gate76 synthetic job.

Unlike Gate76, this job **does not create mock Gate42 cost center and project posting tables**. Instead, it boots disposable tenant, legal entity, branch, role, customer, contract and document infrastructure, plus a *minimal simulated B4 journal publisher*. It then executes the **actual** `supabase/manual-packages/gate42_project_costs.sql` and seeds synthetic cost centers *after* their real DDL, followed by the native Gate71 → Gate75 SQL.

The actual `public.onexa_post_project_cost(uuid,text)` function creates the original project cost posting and calls a synthetic `onexa_post_journal` B4 contract double (not the actual production ledger). The test verifies that the document transitions to posted, a single corresponding journal and project posting exist, and re-calling Gate42 returns the original journal rather than double posting. The independent approver/technician/finance users and separate tenants exercise Gates71–75, and the test confirms G74 attribution, G75 source evidence reconciliation, cross-tenant denial, reserved-reference bypass denial, and reversal-aware exclusion from cost totals.

**Not yet tested end-to-end:** the real B4 journal internals, Gate63/Gate64 approval workflow, accounting-period RLS/closures, production chart-of-accounts/mapping contents, detailed line posting, fiscal year configuration, existing customer-schema FK/indexes, source invoices or third-party independent source evidence. All parent fixtures use only invented test tenants, fake numbers and synthetic users. The workflow uses a disposable GitHub PostgreSQL container and rolls back data test transactions.

## Before production

A DBA should use an isolated *restore-capable clone of the actual ONEXA schema* and run read-only preflight. Do not apply Gate42/64 or Gate71–75 SQL to the live database. Verify expected base entity/branch membership keys, journal posting function signature, G42 account mappings (`project_wip_or_expense`, `cost_source_or_clearing`), G63/G64 approvals, a genuine two-tenant negative test, and full accounting reconciliation. Require explicit finance approval and a tested backup before any deployment.

**In source control ≠ installed in production. GitHub green ≠ accepted finance UAT.**
