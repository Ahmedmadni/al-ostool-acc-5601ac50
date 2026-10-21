# ONEXA — Hosted Staging identity gate

## Verified repository configuration

The checked-in `supabase/config.toml` identifies project `drjmktsbllawmouiskrg`.

## Connected organization discovery (2026-10-21)

The currently connected Supabase account lists two **inactive** projects, neither matching the checked-in project identifier. Their names do not clearly identify ONEXA. Treat both as **unverified/unrelated** until ownership and purpose are established. Never repurpose or restore them automatically.

## Required next action

Choose the intended Supabase organization for a **new, dedicated ONEXA Staging project**. Before creating it, check the current project cost and obtain any required approval for charges. Choose a geographically appropriate supported region with explicit confirmation. Do not create a branch on a production project as a substitute for independent Staging.

## Acceptance tests (after creation)

1. Confirm production and Staging project references and URLs differ.
2. Create synthetic tenants only, with separate test identities, and verify anonymous access denial and cross-tenant RLS isolation.
3. Rehearse versioned migration ordering and reversible deployment only on Staging.
4. Verify documented chart-of-accounts posting mappings, journal integrity, posting approval and reversal behavior.
5. Demonstrate backup/restore on the separate test environment.
6. Keep finance-posting feature switches and any production database writes disabled until explicitly authorized.

The existing offline manifest audit and health probe are **not** evidence that a hosted Staging project has been provisioned or verified.

## Security boundary

No Supabase project restoration, production query, production migration, deployment, data copy, secret retrieval or feature-flag change is authorized by this runbook.
