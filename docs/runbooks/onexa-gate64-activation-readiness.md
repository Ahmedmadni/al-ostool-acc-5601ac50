# ONEXA ERP — Gate 64 approval/posting bridge preflight

**State:** NO PRODUCTION SQL migration, approval changes, flags, or business data writes performed by this update.

Gate 64 is **not** a self-contained feature. It replaces seven posting RPC definitions to respect the tenant's approval assignment map, adds audit triggers on posting, and enhances the accounting inbox. Applying it while earlier posting engines are absent or inconsistent is unsafe.

## Live Tenant 001 diagnostic (2026-10-15, read only)

- Available: Gates 35 (sales), 36 (purchase), 39 (customer receipt), Gate 63 approval runtime and mapping helpers.
- Not installed: Gate 40 supplier-payment, Gate 41 bank transfer, Gate 42 project-cost and Gate 43 fleet-trip posting RPCs.
- The installed G35/G36/G39 posting functions are not yet policy-aware according to the `pg_get_functiondef` marker diagnostic; those definitions need an explicit manual review before running Gate 64.
- Code pushed/merged to GitHub **does not install** any of these routines in the Customer Data Plane.

## Required path before Gate 64

1. Identify the correct customer Supabase project, current schema, migration history and restorable backup. Do not use the Control Plane by mistake.
2. Run `supabase/manual-packages/onexa_gate64_readonly_preflight.sql`; do not proceed while any essential function or approval table is MISSING.
3. Apply missing G40, G41, G42, G43 **in separate authorized manual deployments**, with postchecks, tenant/security tests, rollback smoke and finance reconciliation after each.
4. Inspect the exact SQL definitions of all seven installed posting RPCs. Gate 64 uses `regexp_replace(pg_get_functiondef(...))`; a function signature being PRESENT is not proof the patch will match. Compare against the expected creator/poster guard and do a dry run in a disposable clone.
5. Confirm each active workflow process has the intended `approve` and optional `post` steps and authorized assignees; verify segregation requirements with two real staff identities.
6. Only then deploy `supabase/manual-packages/gate64_approval_posting_bridge.sql` under an approved change window.
7. Perform Gate 64 postcheck, UI authorization tests, idempotent posting, rejection of an unassigned poster, wrong-tenant access, audit trail and GL tie-out.
8. Enable the relevant posting flags **only after** tested end-to-end finance approval. Hold G65/G66/G67 and G68–70 until Gate 64 acceptance.

**Blocked is a correct safety result, not a reason to bypass the posting approval guard.**
