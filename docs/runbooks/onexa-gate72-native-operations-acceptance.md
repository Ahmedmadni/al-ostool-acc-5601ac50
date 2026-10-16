# Gate 72 — Native ONEXA operations sites and assets

**Status: SOURCE ONLY — NOT INSTALLED ON CUSTOMER PRODUCTION.** This is a new, tenant-native foundation. It is not the old Gate 14 `ops_*` schema and does not post maintenance work orders, materials or costs.

## Scope

Gate 72 adds `onexa_operations_sites` and `onexa_operations_assets`, each scoped to the exact ONEXA tenant, legal entity and active branch. Sites must also reference one explicitly approved active Gate 71 `OM → projects` company-module alias for the same tenant/entity. Assets must reference a site **of the same tenant, entity and branch**.

The constraints are real composite foreign keys, not merely application-side filters. Both tables have tenant-qualified SELECT RLS policies requiring active workspace membership, `projects.read`, the valid OM module alias, and active company/branch/site records. Anonymous reads are revoked; authenticated users have SELECT only. All mutations are through verified SECURITY DEFINER creation RPCs or separately authorized service-role provisioning. Creator RPCs require `projects.create`, module/alias authorization, current tenant claim, active legal entity and branch, and valid scoped parent. Immutable-identity triggers disallow reassigning records to another tenant/entity/branch/parent.

## Connected production evidence (2026-10-16, SELECT only)

The existing ONEXA `onexa_branches`, `onexa_legal_entities` and `onexa_tenants` have verified tenant/entity IDs. Existing canonical RBAC functions have been inspected. Gate 71 is currently merged into source but **not installed**. No Gate 72 objects or records are installed or seeded.

## Explicit deployment order

1. Verify a tested backup/restore and disposable Customer Data Plane clone. **First install and accept Gate 71** there. No legacy Gate 13 or 14 migration is permitted.
2. Verify exact existing branch identity, tenant memberships, RBAC and Gate71 mapping. The code adds unique composite indexes to the existing `onexa_branches` and Gate71 table; inspect for conflicts and index-build lock impact beforehand.
3. Apply `gate72_onexa_native_operations_sites_assets.sql` only in that disposable clone, after checking for partial installs. It does not seed any site or asset.
4. Run `gate72_postcheck.sql`. Require every object/constraint/trigger/RLS gate READY; anonymous SELECT/EXECUTE false; authenticated INSERT/UPDATE/DELETE false; no invalid parent joins.
5. Provision two independent TEST tenants, two legal entities and valid branches plus OM scopes in the clone, with independent authorized users. Verify known-ID access across tenant or legal-entity boundary fails for both RLS SELECT and every creation RPC. Verify branch mismatch and site mismatch are rejected by the composite FK even for a privileged provisioning identity. Verify deactivated site, scope, branch and entity no longer expose assets.
6. Audit every canonical `projects.read` and `projects.create` role. No user may select another client's assets or create one against an outside site or branch. Failed creation must leave no rows.
7. After a documented, finance/operations/security-approved deployment window, consider production SQL. Keep old Gate14/Gate15 and all lease/maintenance posting feature flags **OFF**. Independently rebuild tenant-native work-order, acceptance, cost, property and lease entities next.

## Stop conditions

Missing Gate71, partial Gate72, missing tenant/branch/scope, permissions failures, any cross-tenant positive access, any orphan or mismatched FK, production backup unavailable, or absent acceptance evidence.

**GitHub CI validates source only**, not live PostgreSQL DDL execution or real-world operational acceptance.
