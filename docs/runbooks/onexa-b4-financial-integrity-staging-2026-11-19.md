# ONEXA Phase 10 — B4 GL integrity and staged release acceptance

Date: 2026-11-19. **Current release decision: HOLD.** No hosted customer financial data or SQL changed in this phase.

## Verified installed technical catalog — READ ONLY

The connected ONEXA project passed **1 of 11 catalog readiness checks**, with **10 HOLD**:

- READY: row-level security is enabled on all three Gate 58 manual-journal tables.
- HOLD: the GL source type constraint excludes manual_journal; the GL header balance constraint permits abs(debit-credit) <= 0.005; shared B4 exact money and source-payload retry validation is not installed; B4 reversal replay guard is not installed; authenticated still has direct EXECUTE on private B4 SECURITY DEFINER functions; Gate 58 post/reverse receipt controls and amendment RPC are not installed.

This describes function/schema/ACL metadata, NOT a production ledger financial data scan and NOT a complete effective-security assessment.

## New 17-check SELECT-only ledger integrity audit

Operator source: supabase/manual-packages/onexa_b4_ledger_integrity_READ_ONLY.sql

Output is three fields only: issue_code, severity, affected_count. It never returns ledger UUIDs, money figures, customer data or source snapshots.

| Layer | Scope |
| --- | --- |
| Posting registry | Target journal exists, exact source identity, canonical idempotency key, GL receipt registered once, duplicated source-revision detection |
| GL headers and lines | Exact debit/credit equality, at least two lines, exact summed amounts, line debit/credit rules, line tenant match |
| Fiscal periods | Legal-entity, tenant and accounting date agree with the referenced fiscal period (historical closed periods are permitted) |
| Reversal | Original-to-contra links, posted/reversed lifecycle, source reference and revision, currency and mirrored totals, reason/snapshot/memo, correctly ordered contra line amounts, account, descriptions and all dimensions |

HEADER_WITHOUT_REGISTRY has severity REVIEW because historical imported rows could exist. Even REVIEW > 0 blocks the offline release gate until independently reconciled by finance; there is no automatic waiver or repair.

Zero findings are necessary, not sufficient: they cannot prove original document accuracy, financial statement compliance, ZATCA/VAT interpretation or effective authorization. The audit may scan large GL tables. Run it on independently restored Staging under an approved bounded read-only, repeatable-read transaction, **not against a busy production database**.

## Coordinated staged rollout sequence

1. Independently restore and validate a production backup in a physically/logically separate Staging environment. Confirm recovery test, source catalog version and multi-tenant isolation. Keep all finance feature flags OFF.
2. Capture both the operator catalog report (supabase/manual-packages/onexa_b4_release_catalog_READ_ONLY.sql) and the 17-category ledger report. Finance reviews historical issues without rewriting, rounding or auto-balancing financial entries.
3. Compare actual installed function fingerprints and schema definitions against the exact preconditions in each REVIEW_ONLY package. If any fingerprint differs, stop. No migrations are automatically applied by these files.
4. In an approved and rehearsed Staging maintenance window, coordinate these dependent schema/code changes (NOT a pick-and-choose production deployment):
   - gate58_b4_gl_source_type_REVIEW_ONLY.sql adds manual_journal to the GL source allowlist.
   - gate58_b4_gl_exact_balance_REVIEW_ONLY.sql replaces tolerated header imbalance with exact balance, refusing historical discrepancies.
   - gate58_b4_strict_monetary_REVIEW_ONLY.sql contains exact currency/input safeguards and source-idempotency payload integrity.
   - gate58_b4_reversal_idempotency_REVIEW_ONLY.sql verifies unchanged reversal reasons, dates, periods and contra receipt.
   - Separately reviewed Gate58 create/amendment/authorization/post-receipt SQL and gate58_b4_private_grants_REVIEW_ONLY.sql follow their independent MD5 and authorization contracts. Do not execute a patch whose installed source has drifted.
5. Test all active module workflows on realistic independent Staging: manual GL, sales, purchasing, receipts/payments, payroll, inventory, fixed assets, projects, bank/fleet/lease postings; double-entry precision, approval segregation, source revision changes, closed periods, retries, reversals and two-tenant role denials. Verify public checked RPCs still work after restricted private-function EXECUTE is revoked in Staging.
6. Capture the same SELECT-only reports AFTER all staged fixes. Demand **11/11 catalog READY and 17/17 ledger categories with zero findings**, plus finance-approved handling of any legacy import issues.
7. Fill documented staging attestations only with independently verified evidence: tested restore, finance and security approvals, module E2E, source-fingerprint preconditions, historical exceptions, migration order and rollback drill. Feature flags stay OFF.
8. Convene a human financial/security release go/no-go decision. Only a separately approved production change window may install the coordinated changes. Re-run metadata/ledger checks after installation, then consider deliberate feature-flag enablement. A failed dependency means HOLD and no partial activation.

No automated production rollback is supplied. Plan tested backup/restore and a reconciliation-based rollback with finance; NEVER delete, backdate or adjust journal rows to make tests green.

## Offline fail-closed evidence verifier

Source: scripts/onexa-b4-staging-evidence-gate.mjs

It reads three LOCAL files: 11-line catalog PSV, 17-line ledger PSV, and the human staging attestation JSON copied from docs/runbooks/onexa-b4-staging-attestation.example.json (which has every approval initially false).

Example command after collecting evidence in independent Staging:

    node scripts/onexa-b4-staging-evidence-gate.mjs catalog.psv gl-integrity.psv stage-attestation.json

Any missing/duplicate category, schema HOLD, non-zero BLOCK/REVIEW count, invalid input, unverified backup, absent approval or enabled feature flag returns HOLD and a nonzero exit code. With all inputs valid, the result is **EVIDENCE COMPLETE FOR HUMAN REVIEW** — it never authorizes production changes, connects to a database or toggles flags.

## Disposable regression evidence

PostgreSQL CI uses captured real B4 functions and synthetic tenancies. It creates valid original and reversal GL journals and first demands all 17 audit categories read zero. Then, in a single rollback-only transaction, it corrupts GL source/registry keys, source duplicates, amounts, dates, line counts, line tenants, and contra links/reasons/lines. It runs the EXACT SAME SELECT-only report and requires all 17 categories to detect discrepancies, then rolls back and demands zero again.

A separate local Node test exercises the offline gate with fabricated synthetic PASS inputs, and verifies missing approvals, bad environments, nonzero REVIEW findings, missing/invalid fields all produce HOLD. These tests DO NOT establish that an independently restored customer Staging environment has been accepted.

## Known limitations

- Current production private SECURITY DEFINER grants are a real security review concern, but this audit does not prove which PostgREST schemas are exposed.
- Synthetic role/parent tables cannot certify the real Staging authorization and source-module implementations.
- Historical source systems might have legitimate imported journals not using the B4 registry; these require a documented finance reconciliation, not a silent exception.
- Source sync with Lovable never installs hosted B4 SQL or authorizes a change to real customer books.
