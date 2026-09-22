# ONEXA fixed assets to general-ledger posting

Gate 38 connects the existing tenant-scoped fixed-asset register to controlled
monthly depreciation and the B4 general ledger.

## Boundary with procurement

Gate 36 already debits the fixed-asset cost control account when an approved
purchase-invoice line is classified as `fixed_asset_cost`. Gate 38 does not post
that acquisition value again. This prevents a duplicate asset debit. The
register holds the operational asset record; Gate 38 posts only subsequent
depreciation.

Legacy or opening assets must already be represented in the opening general
ledger before their depreciation is enabled.

## Depreciation contract

The first supported method is straight line without daily proration:

- Monthly depreciation is `(cost - salvage value) / useful life months`.
- The final period is capped at the remaining depreciable value.
- Net book value never falls below salvage value.
- Periods must be posted in chronological order.
- A safe retry returns the original journal instead of duplicating it.
- The asset creator/importer cannot post depreciation for the same asset.

The journal is:

- Debit `depreciation_expense`.
- Credit `accumulated_depreciation`.

Project and department dimensions are preserved from the asset register.

## Register integrity

The migration snapshots existing accumulated depreciation as
`opening_accumulated_depreciation`. Reconciliation then proves:

`register accumulated depreciation = opening accumulated depreciation + Gate 38 postings`

After the first Gate 38 posting, financial fields used by the roll-forward are
immutable through direct updates. The posting function is the only permitted
path for changing accumulated depreciation and net book value.

## Activation

Keep `VITE_ENABLE_ONEXA_ASSET_POSTING` false. Apply the Gate 38 package, run
the read-only postcheck, assign each asset to a legal entity and branch, complete
salvage value/useful life/depreciation start date, install the Al Ostool account
mapping, repeat the postcheck, then run the rollback smoke test. The smoke test
never commits production data.
