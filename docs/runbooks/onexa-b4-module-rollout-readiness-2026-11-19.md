# ONEXA phase 11 — Module-level B4 posting readiness and source-to-ledger compatibility

**19 November 2026 — decision: HOLD.** Source-only improvements and SELECT-only hosted metadata inspection. No customer GL rows, invoices, payments or personal data were read or modified.

## Observed production catalog: 14 publishers, only 4 functions installed

The source manifest \`onexa-b4-module-publisher-manifest.json\` maps 14 distinct front-end RPCs to 15 GL source types across Gates 35–43, 58, 65–67. A new pg_catalog-only SELECT \`onexa_b4_module_publishers_READ_ONLY.sql\` compares expected RPCs with the **installed** function definitions, checked public-B4 dispatch, role-check marker, non-null GL result guard, execute privilege and global ledger source-type constraint.

| Finance posting module | Gate | Installed source/catalog result |
| --- | --- | --- |
| Sales invoice | G35 | RPC present, source type allowed, Staging required |
| Purchase invoice | G36 | RPC present, source type allowed, Staging required |
| Customer receipt | G39 | RPC present, source type allowed, Staging required |
| Manual journal | G58 | RPC present, **manual_journal NOT permitted by installed ledger CHECK** |
| Payroll | G37 | RPC missing |
| Asset depreciation | G38 | RPC missing |
| Supplier payment | G40 | RPC missing |
| Bank transfer | G41 | RPC missing |
| Project cost | G42 | RPC missing |
| Fleet trip cost | G43 | RPC missing |
| Inventory receipt / issue | G65 | One publisher handles two source types; RPC missing |
| Maintenance work-order cost | G66 | RPC missing |
| Lease invoice | G67 | RPC missing |
| Lease receipt | G67 | RPC missing |

**Interpretation:** 3 RPC definitions are present without this particular source-type blocker, 1 manual-journal RPC is blocked by GL source constraints, and 10 expected module RPCs are missing. All 14 modules are still **NOT approved for production activation** because the global B4/Gate58 technical readiness check remains only **1/11 READY**. A function definition and even an authenticated EXECUTE grant cannot prove a posted finance transaction or cross-tenant authorization.

Two contract source types, \`fixed_asset_acquisition\` and \`fuel_issue\`, do not have separately established module publisher RPCs in this inventory. Fixed-asset purchases are currently accounted for through purchase-invoice classification (G36) instead of a dedicated acquisition journal. Do not silently count these two as tested standalone modules. The B4 internal \`journal_reversal\` source is a shared reversal path, not a third lease or inventory module.

## Added source-only technical safeguards

- The manifest binds the exact RPC name to the SQL package, client service, flag owner and source type(s); source-level checker verifies each public RPC definition actually calls \`onexa_post_journal\` **inside the function body**, performs module permission validation and refuses missing journal IDs. It verifies all module flags are opt-in via runtime switches and default **blank** in \`.env.example\`. This **does not prove** actual deployment environment variables are off.
- New \`onexa_b4_module_publishers_READ_ONLY.sql\` emits only module/gate/RPC and metadata booleans plus a conservative technical status. It never queries financial rows.
- Repaired legacy \`posting-readiness.ts\` preview, which previously tolerated a debit/credit difference of up to 0.005. The UI now compares integer-valued fixed-scale amounts without auto-rounding, refuses SAR fractional halalas, >4 decimal storage and unsafe JavaScript numbers. The authoritative PostgreSQL backend must revalidate **every GL line**.
- The module-level offline evidence gate \`scripts/onexa-b4-module-evidence-gate.mjs\` consumes the catalog PSV plus an **independently restored Staging** attestation. Every publisher needs a reviewable test reference and 10 finance-specific proofs: approval segregation, account mappings, exact currency, posted GL reconciliation, idempotent retries, revised-source control, contra reversals, closed-period denial, tenant/role denial and module owner approval.
- The test suite injects fake evidence failures and ensures the gate returns HOLD for missing RPC, blocked source type, missing signoff, invalid evidence, enabled flags, wrong environment or malformed catalog. Passing synthetic test evidence is a **parser/unit test**, never a real Staging approval.

## Release order and dependencies

The 11 global technical requirements in \`onexa_b4_release_catalog_READ_ONLY.sql\` and 17 integrity checks in \`onexa_b4_ledger_integrity_READ_ONLY.sql\` remain required **before any module feature flag**. The source B4 review packages (manual_journal allowlist, exact GL balance, strict source money + unchanged retry payload, reversal receipt consistency, private-function least privilege and Gate58 lifecycle/amendment) must be reviewed and tested together. No SQL will be silently auto-applied or source-specific module enabled prematurely.

In independently restored Staging, inventory the current installed functions before each gate's manual SQL package and verify table/mapping dependencies (G36 depends on sales inventory foundation, G39 on sales posting, G40 on purchase posting, G66 on project work orders, G67 on its lease and customer-receipt foundations as defined by its preflight). Validate SQL checksum and rollback documentation and **all** module-specific receipt/reversal scenarios with actual permissions.

After collecting independently reviewed Staging outputs:

    psql -X -At -F '|' -f supabase/manual-packages/onexa_b4_module_publishers_READ_ONLY.sql > module-catalog.psv
    node scripts/onexa-b4-module-evidence-gate.mjs module-catalog.psv module-attestation.json

Module attestation template: \`docs/runbooks/onexa-b4-module-uat-attestation.example.json\`, with all checks false. The exact SQL SELECT query must be executed by an appropriately restricted, read-only Staging identity; do **not** run the command on production. Review the previous phase 10 offline overall Staging gate separately.

The offline module gate can only report **complete evidence for HUMAN review**; it has no DB or deployment permissions. It is not a replacement for real full-module E2E testing. Keep global and per-module flags disabled until finance, security, backup/restore and written change control independently authorize a coordinated production release.

## Remaining qualification risk

- Sales, purchase, receipt and manual module RPCs were inspected by their **catalog definitions**. They have not been accepted in full restored Staging. Modules with absent RPCs cannot be asserted tested from source smoke scripts.
- Cost-accounting variants, multi-currency amounts, VAT/IFRS/ZATCA data and authorization must be checked using independently approved source-ledger reconciliations, not inferred from matching synthetic fixtures.
- Real production runtime flags, effective API schema exposure, accounting account-role mapping for the actual tenant and operational data quality are **not certified** by this source/catalog-only phase.

**Bottom line: GitHub and Lovable source synchronization is not a hosted B4 migration, and current production remains HOLD.**
