# Gate 42 — Project cost accrual and B4 journal integrity

**Current state (Customer Data Plane, Tenant 001): NOT DEPLOYED / NOT ACTIVATED.** Existing GitHub SQL is a manual package, not proof that its objects exist in the connected database.

## What the posting represents

This module creates an **accrued, unpaid direct project cost** not already recognized in purchases, payroll, inventory or maintenance. It debits reviewed project WIP/expense and credits a genuine cost-source/clearing **liability**. The original external reference remains unique for audit, including after a reversal: do not recycle it and do not treat a reversal as permission to book the same invoice twice.

## Source and GL contract

- An approved native `project_cost` document can post only with the correct tenant, legal entity, branch, scoped active project/cost center, source kind `unpaid_direct_cost`, posting permissions, an authorized actor different from creator and an open accounting period.
- The reconciliation view requires a matching `onexa_project_cost_postings` row, original B4 journal in state `posted` with no `reversal_journal_id`, journal source type/ID, debit/credit totals and currency matching the source cost, and the project cost center in the document's entity and branch.
- A reversed or missing original journal yields `journal_reversed_or_missing`, not `reconciled`. Repeating a request to post the same already-posted document fails closed with `ONEXA_PROJECT_COST_JOURNAL_REVERSED_OR_MISSING` after reversal.
- GL category rules: `project_wip_or_expense` is an active detail assets/expenses/cost-of-revenue account; `cost_source_or_clearing` is an active detail liabilities account. Accounts must be different.
- The posting report is `security_invoker=true`, with tenant-scoped source document, cost center and journal visibility under RLS. No direct business-user writes to GL tables.

## Live read-only finding — 2026-10-15

A query against the Lovable-connected Tenant 001 AOA database returned **zero mappings** for `project_wip_or_expense` and `cost_source_or_clearing`. These are missing prerequisites, not placeholders to guess from an account numbering convention.

## Safe acceptance sequence

1. Confirm the exact customer database, backup/restore proof, approved change window and the existing `onexa_post_journal` RPC/permissions. Run `onexa_erp_capability_inventory_readonly.sql` and `onexa_gate40_43_readonly_preflight.sql`.
2. Have Finance review `gate42_aoa_project_cost_mapping.sql`: replace all `REPLACE_...` values using the **actual** chart of accounts and a real AOA project/cost center. Confirm this cost is not already recorded in other operational modules. Do not apply placeholder SQL.
3. Check if any part of Gate 42 exists before DDL. Only when authorized, apply `gate42_project_costs.sql` manually; never blindly rerun a partially installed package.
4. Run `gate42_postcheck.sql`; it must report all objects present, appropriate RLS, denied anonymous execute, `MAPPING_REQUIRED` count zero, and no unreconciled posted project costs.
5. With distinct creator/approver/poster users, execute the rollback-only `gate42_project_cost_smoke_test_rollback.sql`, ensuring journal posting, source lineage, idempotency and cross-tenant negative tests pass.
6. In a disposable database copy, reverse a posted project's original journal. Verify `journal_reversed_or_missing` and rejection of a re-post retry; inspect the trial balance and cost-center expense after reversal.
7. Enable `VITE_ENABLE_ONEXA_PROJECT_COST_POSTING=true` **only after** the SQL package, account mapping, smoke tests, GL tie-out and finance approval all pass.

**No production SQL changes or feature toggles are made by this repository change.** GitHub CI is code/build verification, not a replacement for SQL acceptance.
