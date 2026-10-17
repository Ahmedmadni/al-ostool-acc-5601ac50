# Gate 79 — Staging readiness / actual ONEXA catalog preflight

**READ ONLY. Not a deployment request, signoff or database modification.**

Run `supabase/manual-packages/gate79_onexa_staging_compatibility_readonly.sql` using authorized ONEXA database catalog read access. Every statement is `SELECT` / `WITH ... SELECT`, and it neither copies customer data nor executes DDL. It compares `pg_catalog` and `information_schema` against **52** specific core, posting, approval and native-maintenance objects. It also checks 35 expected columns and types, active RLS/policy counts on existing tenant tables, the existence (not correctness) of required project-cost mappings, and applicable key constraints. Presence is not proof of a correctly installed or safe module.

## Verified read-only results, 2026-10-17

| Component | Present | Missing | Interpretation |
|---|---:|---:|---|
| ONEXA base objects | 13 | 0 | Only catalog presence, not full tenant UAT |
| B4 journal post function | 1 | 0 | Available, but actual journal integration/restore testing remains |
| Gate 42 cost centers / project postings / RPC | 0 | 3 | Not installed |
| Gate 63 approval tables and functions | 6 | 0 | Present; not proof a real workflow is assigned |
| Gate 64 approval posting + seven engines | 3 | 6 | Missing 3 approval functions and supplier, bank, fleet posting RPCs |
| Gate 71 tenant company scopes | 0 | 2 | Not installed |
| Gate 72 operations sites / assets | 0 | 4 | Not installed |
| Gate 73 native work orders | 0 | 4 | Not installed |
| Gate 74 native maintenance cost attribution | 0 | 5 | Not installed |
| Gate 75 independent unpaid-source review | 0 | 5 | Not installed |
| **Total** | **23** | **29** | **Deployment blocked** |

The 35 inspected base column/type pairs matched. RLS was enabled on the three present inspected tenant-bearing tables (branches, legal entities, business documents), but detailed policy acceptance was **not** assessed. For the single existing legal entity, both finance account-role mappings `project_wip_or_expense` and `cost_source_or_clearing` have **zero active entries**. No accounts, GL journals, mappings, policies, users or business data were created or changed.

The Gate64 source preflight requires all seven posting engines and the Gate63 runtime before installation. Therefore, **do not install Gate64** as if it were an isolated standalone migration. Native Gates 71–75 remain source-only and legacy Gates 13–15 remain blocked on the multi-tenant data plane.

## Supabase staging account discovery, 2026-10-17

The linked Supabase connector lists **one Free-plan organization**, `Ahmedmadni's Org`, and two existing *inactive* projects. The connected projects are not the ONEXA Lovable-hosted production project (not listed in this Supabase connector). Do not claim either inactive project is an ONEXA staging clone, restore it without approval, or attempt to share production Lovable service keys.

**Before creating staging:** ask the user which organization should own the new project, request organization-specific project pricing and obtain explicit acceptance of any nonzero charge. Create an **entirely separate Supabase project**, not a development schema on the production database. Use test tenants / dummy invoices only, never copy auth users, real journal data or private API keys. If no organization has available capacity or connection privileges, stop and provide UI instructions to create a Supabase project manually.

## Deployment acceptance (not automatic)

1. Confirm organization, project costs, intended staging region, ownership/permissions and real isolation.
2. Inspect the **real source-controlled migrations** to derive a safe dependency order; compare actual production schema/type/unique/FK/enum definitions with the staging baseline. Do not infer readiness from only 52 presence checks.
3. Verify scope/role mappings and finance posting dependency activation for Gates42/63/64 and missing posting engines. Verify account mapping with finance; don't invent chart-of-accounts codes.
4. Obtain a tested restorable backup, risk review and staging-only change window before DDL. Create two **fictional** tenants with separate legal entities, branches, users and project codes; no real customer snapshot.
5. Run the G71–75 SQL and Gate76–78 actual PostgreSQL negative tests on this isolated staging instance, validating tenant isolation, approvals, GL source/reversal, duplicate cost prevention and no double posting.
6. Report discrepancies in column types, RLS, composite unique keys, direct grants, Gate64 approval actor separation and original journal behavior. **Do not turn production feature flags on** until signed approvals.

## Latest Lovable repository update

The latest Lovable bot commit `e3562c204c2fdedfbee24bb70c4b4be123bafd52` touched five files: `package.json`, `bun.lock`, `src/integrations/supabase/previewAuthStorage.ts`, `src/integrations/supabase/types.ts` and `src/routeTree.gen.ts`. It is **not accurate** to describe it as changing package files only. The preview auth broker changes require login/logout testing inside a real Lovable preview. Generated files should not be edited manually without ownership of the generator.

GitHub build/typecheck/source assertions provide protection for the current packages but cannot certify preview session behavior or project security on their own.

### Generated types drift from the uninstalled Gate64 view

The regenerated Supabase types correctly describe the **current production** `onexa_accounting_inbox`, which does **not** yet contain `approval_instance_id`, `posting_step_name` or `can_current_user_post`. These three computed columns are projected only by `gate64_approval_posting_bridge.sql`. The source-column checker now requires the exact Gate64 view expressions before treating them as deferred; unknown columns still fail CI. The actual `listAccountingInbox` runtime path reads only currently installed columns and returns `can_current_user_post=false` until the independent, off-by-default `VITE_ENABLE_ONEXA_APPROVAL_POSTING` flag is enabled after Gate64 installation and checks. No Supabase generated types, remote schema or account permissions were artificially modified.
