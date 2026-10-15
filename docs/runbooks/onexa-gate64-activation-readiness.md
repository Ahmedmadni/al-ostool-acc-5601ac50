# ONEXA ERP — Gate 64 approval/posting bridge preflight

**State:** NO PRODUCTION SQL migration, approval changes, flags, or business data writes performed by this update.

Gate 64 is **not** a self-contained feature. It replaces seven posting RPC definitions to respect the tenant's approval assignment map, adds audit triggers on posting, and enhances the accounting inbox. Applying it while earlier posting engines are absent or inconsistent is unsafe.

## Live Tenant 001 diagnostic (2026-10-15, read only)

- Available: Gates 35 (sales), 36 (purchase), 39 (customer receipt), Gate 63 approval runtime and mapping helpers.
- Not installed: Gate 40 supplier-payment, Gate 41 bank transfer, Gate 42 project-cost and Gate 43 fleet-trip posting RPCs.
- The read-only `regexp_count` exact-guard diagnostic returned **`ONE_GUARD_PATCHABLE` (legacy=1, policy=0)** for each installed G35/G36/G39 posting function. A read-only simulation of `regexp_replace` found **exactly one policy-aware guard in each resulting function**. No function was modified.
- The existing accounting inbox has 18 expected columns in matching order/types; proposed columns 19–21 are `APPENDABLE`. This is source compatibility evidence, **not** UAT acceptance.
- The other G40–G43 posting definitions cannot be inspected until they are actually installed, so re-run the full inspection immediately before any authorized G64 rollout.
- Code pushed/merged to GitHub **does not install** any of these routines in the Customer Data Plane.

## Required path before Gate 64

1. Identify the correct customer Supabase project, current schema, migration history and restorable backup. Do not use the Control Plane by mistake.
2. Run `supabase/manual-packages/onexa_gate64_readonly_preflight.sql`; do not proceed while any essential function or approval table is MISSING.
3. Apply missing G40, G41, G42, G43 **in separate authorized manual deployments**, with postchecks, tenant/security tests, rollback smoke and finance reconciliation after each.
4. Inspect all seven posting RPCs with **both result sets** from `onexa_gate64_readonly_preflight.sql`. The function patch result must be `ONE_GUARD_PATCHABLE` (exactly one old guard, no policy guard) or `ALREADY_POLICY_AWARE` (exactly one policy guard, no old guard); anything else, including `MISSING` or `GUARD_MISMATCH_REVIEW_REQUIRED`, is a STOP. The inbox compatibility result must contain only `MATCH` and `APPENDABLE`, with no extra columns. A routine signature alone is insufficient. Confirm the proposed `regexp_replace(pg_get_functiondef(...))` behavior in a disposable clone.
5. Confirm each active workflow process has the intended `approve` and optional `post` steps and authorized assignees; verify segregation requirements with two real staff identities.
6. Only then deploy `supabase/manual-packages/gate64_approval_posting_bridge.sql` under an approved change window.
7. Perform `gate64_postcheck.sql` and require all five checks (`approval_post_guard`, `approval_post_finalizer`, `assignment_aware_inbox`, `inbox_security_invoker`, `all_posting_engines_governed`) to be `READY`. Validate that all triggers are enabled on `onexa_business_documents` and that all seven routines have **exactly one** policy-aware separation guard and zero unconditional guards. Test assigned and unassigned posters, creator/poster separation, tenant isolation, failed approvals, idempotent posting, audit trail and GL tie-out.
8. Enable the relevant posting flags **only after** tested end-to-end finance approval. Hold G65/G66/G67 and G68–70 until Gate 64 acceptance.

**Blocked is a correct safety result, not a reason to bypass the posting approval guard.**
