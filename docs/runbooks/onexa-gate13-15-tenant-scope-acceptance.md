# ONEXA Customer Data Plane — Gate 13 → 14 → 15 readiness and tenant isolation

**Production activation status: BLOCKED.** This package adds a read-only inventory and blocks the unpartitioned legacy foundation on a tenant-aware ONEXA deployment. No production DDL/DML or environment toggles were executed by the code changes.

## Why Gate 15 cannot be applied directly to ONEXA SaaS

The legacy Gate 13 migration creates globally unique `group_companies.code` values (including `RE` and `OM`) and `group_user_module_access` **without `tenant_id`**. Gate 14 `ops_sites` also lacks tenant scoping. Gate 15 RLS and SECURITY DEFINER functions filter by legacy company/role, not an ONEXA tenant key. Even if only one customer exists today, onboarding another workspace into the same Customer Data Plane could make both clients share the same legacy company and property scope. **User/group access is not equivalent to SaaS tenant isolation.**

The updated `20260914120000_gate15_real_estate_preflight.sql` therefore stops on ONEXA data planes until `group_companies`, `group_user_module_access` and `ops_sites` have tenant-scoping foundations. Presence of columns is a preliminary *necessary* check, **not sufficient proof** of safe RLS, foreign keys, company identities, SECURITY DEFINER RPCs, or legacy cost/invoice access. Independent schema/security review and cross-tenant negative tests are required.

The migration preflight also stops if **any** of the 16 Gate 15 markers is already installed. A fully installed Gate 15 should not be replayed any more than a partially installed one.

## Live Customer Data Plane (read-only check, 2026-10-16)

| Area | Observation |
|---|---|
| `onexa_tenants` | Present, one recorded tenant (`tenant-001-al-ostool`) |
| Core customers/vendors/contracts/invoices/costs/fixed assets | Present |
| Gate 13 company, module and user-access tables/RPC | Missing |
| Gate 14 site, asset and work-order tables/RPC | Missing |
| Gate 15 property, lease and schedule tables/RPC | Missing |
| Gate 15 installed core markers | 0 of 16 |
| Tenant columns for the legacy G13/G14 tables | Not present (tables uninstalled) |

See `supabase/manual-packages/onexa_gate13_15_readonly_preflight.sql` for the exact inspection logic. Only SELECT queries are included.

## Safe implementation path

1. Confirm the ONEXA Customer Data Plane, current schema, signed backup/restore test and authorized change window. Keep all flags off.
2. Design a **tenant-partitioned group/company model**; preferably use the existing ONEXA `onexa_legal_entities` and tenant context rather than cloning globally unique `RE`/ `OM` company codes for every future customer. Produce a migration and a compatibility adapter for existing legacy UIs and RPCs.
3. Add tenant predicates to the entire company → site → property → building → unit → lease → schedule/receipt/asset/cost chain, including FK integrity, definer functions, module permissions and RLS. Harden tenant IDs on the referenced `customers`, `vendors`, `invoices` and `cost_entries`; a matching UUID alone is insufficient.
4. Implement tenant isolation tests with **two different actual test tenants** and users; ensure cross-tenant known-UUID access fails for SELECT and all SECURITY DEFINER functions.
5. Only after the design is approved: execute the reviewed Gate 13 bridge, Gate 14 and Gate 15 in dependency order; perform exact schema, postflight RLS/permission, workflow and accounting reconciliation checks after each batch.
6. Activate Gate 64 only after its prerequisite G40–43 engines and guards pass acceptance; Gate 67–70 rent posting/reports then require verified Gate 15, finance mappings and financial UAT.

## UI safety

The real-estate dashboard now mounts its data-query component **inside** `ModuleAccessGuard`, so no query for legacy `re_*` tables runs during the authorization check or after denial. This complements, but never replaces, server-side RLS. Its error message no longer claims every failure is necessarily an uninstalled table: permissions/connectivity can fail as well.

**Stop conditions:** missing tenant-partitioned architecture, a second tenant sharing global company codes, missing Gate13/14 dependencies, any partial migration, weak RLS, missing restorable backup, any failed cross-tenant probe, or finance/operations rejection.

CI confirms source/build/test contracts only. It cannot authorize a SQL change or certify a safe multi-tenant installation.
