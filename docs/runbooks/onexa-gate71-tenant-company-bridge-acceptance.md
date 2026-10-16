# Gate 71 — ONEXA tenant-native company/module bridge (code delivery)

**Status:** proposed tenant-safe foundation in source control. **NOT installed, NOT accepted for production**, and no legacy Gate 13/14/15 migrations have been executed. It does not provide a complete real-estate or maintenance module.

## What is implemented

`gate71_onexa_tenant_company_module_scopes.sql` creates an opt-in alias mapping within the *existing* ONEXA tenant/legal-entity model. The only supported pairs are legacy `CORE → finance`, `OM → projects`, `RE → facilities`. Every alias belongs to a tenant and an existing legal entity; there is no automatic `CORE`, `OM`, `RE`, customer, company or second-tenant seed.

The `(tenant_id, legal_entity_id)` **composite foreign key** (via a corresponding unique index on the existing legal-entity registry) rejects cross-tenant references, including privileged admin mistakes. Uniqueness of `(tenant_id, legacy_company_code)` scopes each alias within one tenant and forbids an ambiguous active company mapping. The code/tenant/entity/module identity cannot be changed after creation; revoking access or changing an alias requires an explicit controlled provisioning action.

Row-level security allows an authenticated caller to SELECT only an active legal entity mapping of their **current claim tenant**, when they are an active member and have the canonical ONEXA module `read` permission. Authenticated users cannot INSERT/UPDATE/DELETE these mappings. The compatibility RPC `onexa_has_company_module_access(text,text)` checks all of those conditions *again* inside a SECURITY DEFINER function, including exact legacy-name-to-native-module pairs, before returning true. The `onexa_active_company_module_scopes` view is SECURITY INVOKER. Anon access is revoked.

`ModuleAccessGuard` can additionally check the new RPC in tenant mode, but **only** when `VITE_ENABLE_ONEXA_TENANT_COMPANY_SCOPES=true`. The default is off, so current tenant UI access is unchanged until a verified rollout. After enabling, a network error, missing RPC, no configured scope, inactive membership, missing permission or unauthorized tenant **denies** access. This is a UI defense, not a substitute for RLS.

## Architecture boundary / non-goals

Legacy Gate 13 uses global unique codes and no ONEXA tenant ID. Gate 14 creates `ops_*` objects under a global group-company UUID, and Gate 15 creates `re_*` objects the same way. **Gate 71 does not retrofit their schemas or authorization**. Therefore:

- The historical Gate 13 migration rejects installation on ONEXA Customer Data Planes.
- Gate 14 rejects installation both in its preflight and its SQL foundation, so an operator cannot bypass the first gate by applying the second file.
- Gate 15 continues to reject unsafe or previously-applied tenant-unaware installs (prior PR #60).
- The production migration manifest explicitly marks batches `03_holding`, `04_maintenance`, `05_real_estate` **BLOCKED_UNPARTITIONED_LEGACY_SCHEMA** for ONEXA SaaS. Do not run them despite their presence in source control.

The bridge does **not** authorize creating `ops_work_orders`, `re_tenant_leases`, billing schedules, customer invoices, asset links or maintenance costs. Future native tenant-aware G14/G15 schemas require tenant FK chains, matching source customer/contract tenant IDs, module checks on every definer RPC, negative-access tests and actual UAT.

## Actual connected database evidence (2026-10-16, SELECT only)

`onexa_tenants`, `onexa_legal_entities`, `onexa_workspace_memberships`, and ONEXA private tenant/membership/module-action functions are installed. `onexa_legal_entities` has `tenant_id`, `id`, `is_active`, and tenant-qualified RLS. There is currently **one** observed tenant (`tenant-001-al-ostool`), not a test of multi-tenant isolation. The legacy G13–G15 tables remain **absent**. No Gate 71 objects or alias mappings have been installed.

## Staging and manually approved rollout

1. Review the exact SQL and take a **tested restorable backup** of a staging/customer clone. Verify index creation impact, module names, and workspace/JWT authorization.
2. Apply the *new* `gate71_onexa_tenant_company_module_scopes.sql` **only** in a disposable clone first. Do not run legacy Gates 13–15. Do not replay if any Gate 71 object already exists; inspect migration state first.
3. Run `gate71_postcheck.sql`; require ready objects, enabled identity trigger, validated composite FK, RLS, invoker view, anon permissions false, authenticated scope-writes false, and zero invalid cross-tenant rows.
4. Provision two independent **test tenants and test users in the disposable clone** only, using approved workspace membership and module role setup. Assign each test tenant's `RE` alias to a legal entity **of that tenant**, then test access from each tenant with the other's known alias ID/legal-entity ID. Cross-tenant reads, RPC results, inserts, and alias tampering must all fail. No real customer/user/tenant IDs may be copied to the test tenant.
5. Prove a caller without `facilities.read` cannot access `RE`, and that a user with the entitlement but without an explicit scope cannot access it. Exercise `CORE`, `OM`, `RE` and invalid aliases.
6. Check active `ONEXA` single-tenant business is unaffected with the feature flag blank. After release approval and a successful staged test, apply the controlled schema migration and **explicitly approved scope mappings** in production, with a backup and rollback plan.
7. Only after production postchecks and security/finance sign-off, consider enabling `VITE_ENABLE_ONEXA_TENANT_COMPANY_SCOPES`. This flag can deny all module routes if no mappings have been provisioned. Native G14/G15 functionality still requires separate schema/UX and acceptance work.

**STOP:** no tested clone/backup, partial migration, cross-tenant leakage, ambiguous alias, missing canonical RBAC, unauthorized scope insert, missing active legal entity, CI failures or non-reconciled finance state.

This is a preparatory security foundation, **not** completion of the ERP/real-estate launch.
