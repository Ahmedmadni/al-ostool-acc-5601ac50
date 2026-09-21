# Tenant 001 — Al-Ostool activation runbook

Status: production rollout in progress. The workspace, accounting foundation, owner activation, user mappings, and 2026 fiscal periods were reported verified on 19–20 September 2026. Restrictive tenant-boundary hardening and the final acceptance package remain pending before runtime enforcement is enabled.

Al-Ostool is represented only as the first ONEXA customer workspace. It is not a product identity, global default, or authorization bypass. The authoritative application manifest is `src/data/tenant-seeds/al-ostool.ts`.

## Prepared workspace

- Tenant ID: `tenant-001-al-ostool`
- Tenant number: `001`
- Slug: `al-ostool-alaali`
- Target plan: `enterprise`
- Locale and timezone: `ar-SA`, `Asia/Riyadh`
- Default legal entity: `AOA`
- Default branch: `RUH-HQ`
- Base currency: `SAR`
- Enabled modules: all ONEXA modules
- User assignments: intentionally empty

No commercial registration, VAT registration, bank account, person, email, credential, opening balance, or production secret has been invented or embedded in the seed.

## Confirmed production values

- Workspace owner: Ahmed Elmadni (`workspace_owner` / `admin`).
- Legal entity Arabic name: `شركة الأسطول الآلي للمقاولات`.
- Legal entity code: `AOA`.
- Fiscal-year start: 1 January.
- Commercial-registration and VAT-registration numbers: intentionally deferred; both remain null.
- All nine ONEXA modules are enabled for the enterprise subscription.
- Six existing authenticated users are active members of Tenant 001.
- Twelve monthly fiscal periods for 2026 were created and reported open.

## Remaining confirmations before final enforcement

1. Verify the English legal name before it is used on external documents.
2. Add and verify the commercial-registration and VAT-registration numbers when supplied; do not invent placeholders.
3. Confirm the opening-balance cut-off date.
4. Verify the default branch mapping to `RUH-HQ`.
5. Classify legacy `OM` records under Projects / Maintenance & Operations.
6. Classify legacy `RE` records under Facilities & Real Estate.
7. Decide the destination of any legacy `IT` records instead of creating a fictitious legal entity.
8. Sign out and sign in as the owner, then confirm the refreshed JWT shows Tenant 001 instead of Legacy.
9. Execute and verify the restrictive tenant boundary, role-helper hardening, and final acceptance packages (B2, B3, and B9).

## Production execution record

| Package | Reported state | Evidence received |
| --- | --- | --- |
| B0 preflight | Complete | Baseline row counts and balanced trial balance |
| B1 workspace foundation | Complete | Workspace tables exist with RLS enabled |
| B4 accounting foundation | Complete | Ledger tables and hardened posting/reversal functions exist |
| B5 legal entity | Complete | `AOA`, January fiscal start, CR/VAT null |
| B6 owner activation | Complete | Owner claims and membership active |
| B7 user mapping | Complete | Six users mapped; nine modules enabled |
| B8 fiscal periods | Complete | January–December 2026 created as open |
| B2 tenant boundary | Pending | Must pass cross-tenant isolation checks |
| B3 role helpers | Pending | Must pass privilege and search-path checks |
| B9 final acceptance | Pending | Required before runtime switches are enabled |

## Final activation sequence

1. Take a fresh verified backup/export immediately before B2/B3/B9.
2. Sign out and sign in as the owner so server-controlled `app_metadata` is reflected in the JWT.
3. Confirm the application displays Tenant 001 and the enterprise plan instead of Legacy.
4. Apply B2 and B3 from the reviewed manual package in Supabase SQL Editor.
5. Run B9 acceptance queries, security advisors, and performance advisors; resolve every high-severity finding.
6. Reconcile row counts, debit/credit totals, receivables, payables, inventory value, payroll liabilities and fixed-asset balances.
7. Enable provisioning and run invitation seat-limit acceptance tests.
8. Enable posting and run one controlled posting plus linked reversal test.
9. Enable tenancy enforcement for the owner first, then the remaining internal users.
10. Sign off only after isolation and financial reconciliation tests pass.

## Mandatory isolation tests

- A user without valid Tenant 001 membership cannot open any authenticated route.
- A user cannot read, insert, update, delete or invoke RPCs against another tenant.
- Workspace administrators cannot enable modules outside the subscription.
- Updates have both `USING` and `WITH CHECK` ownership predicates.
- Every exposed table has RLS and explicit grants.
- Views use invoker security or are kept outside exposed schemas.
- No browser bundle contains a service-role or secret key.
- Missing or stale tenant claims fail closed after enforcement is enabled.

## Financial acceptance tests

- Opening trial balance remains balanced by legal entity and branch.
- Posted journals are immutable and corrections use linked reversals.
- Each source document posts once for each revision.
- Customer and vendor aging reconcile to control accounts.
- Inventory valuation reconciles to inventory ledger accounts.
- Payroll, project cost, maintenance, fixed assets, VAT and cash reports trace back to source documents.

## Rollback conditions

Rollback before reopening writes if tenant isolation fails, control totals differ, journals become unbalanced, required identifiers are missing, or any high-severity advisor issue remains unresolved. Restore the verified backup, keep `VITE_ENFORCE_ONEXA_TENANCY` disabled, document the failed check, and correct the migration package before retrying.
