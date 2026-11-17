# ONEXA — Phase 3: exact journal money and reversal reconciliation (2026-11-17)

## Problem identified in authoritative source and hosted catalog

The Gate 58 create-RPC allowed `abs(total_debit - total_credit) <= 0.005`, meaning an unbalanced journal could be accepted if the difference was small. The legacy reconciliation view used the same 0.005 tolerance, and a `reversed` manual journal could be shown as reconciled when `reversal_journal_id` was non-null even if the reversal header was missing or did not actually offset the original.

Read-only catalog inspection on 2026-11-17 confirmed:
- Installed Gate 58 create RPC MD5 `0a8e73d608b3642837209b5334c7477a`, unchanged from phase 2.
- Installed reconciliation view MD5 `bd0ad9c8eeec4f6567d1bb0f6d776aa7`; `security_invoker=true`, and its definition still includes the 0.005 amount tolerance.
- These fingerprints are inspection preconditions only. **Neither live object has been patched.**

## Changes delivered in repository source

- **Exact journal balance**: Require `total_debit = total_credit` without the old 0.005 tolerance. Browser-side exact validation does not replace the authoritative RPC.
- **No silent input rounding**: Reject input lines that exceed four decimal places (the underlying `numeric(20,4)` storage); additionally reject more than two decimal places for SAR amounts. Other currency-specific precision must still be confirmed at the finance integration layer; this change does not purport to implement all ISO currency rules.
- **Exact source-ledger reconciliation**: Compare original debit, credit and legal entity without amount tolerance. The reversal record must exist in the same tenant and must link to the original journal, use the same legal entity and exactly offset original debit/credit.
- **Executable disposable tests**: Run real Gate 58 RPCs and the real reconciliation view with *synthetic* data and a fake B4 posting adapter. Negative tests cover 0.004 imbalance, >4-digit storage precision, fractional SAR halalas, 0.004 source-ledger variance, missing reversal, wrong reversal origin and incorrect reversal totals.
- **Guarded review-only SQL packages**: Keep the existing create-RPC review patch synchronised with source and add a separate reconciliation-view review patch requiring the exact observed live view MD5 and `security_invoker` metadata. Neither is auto-deployed.
- **Source-contract checks**: Require exact match between each guarded patch and the authoritative SQL body, and make each precision and reversal negative test mandatory in CI.

## What still prevents hosted activation

1. Independently provision and identify an ONEXA-only Staging environment (not an arbitrary inactive project), with separate ref, roles and synthetic tenants.
2. Rehearse an independently verified restorable backup. Inspect existing historical journal discrepancies in approved, read-only aggregate reporting before changing production constraints or viewing sensitive details.
3. Run both review-only patch packages against **Staging** only after checking the appropriate expected definition fingerprints; a mismatch is a mandatory STOP, not an invitation to bypass the guard.
4. Exercise the actual B4 publisher (not the CI stub), closed accounting periods, multi-currency precision, VAT context, branch/legal-entity mapping, approval-role separation, retry/concurrency, and reversal with real GL ties.
5. Run browser UAT of save, readback, approve, post, reverse and print for two authorized user roles and one denied role; prove cross-tenant RLS isolation.
6. Obtain explicit finance/security acceptance and a controlled production change window before considering any hosted SQL replacement or switching `VITE_ENABLE_ONEXA_POSTING` / `VITE_ENABLE_ONEXA_MANUAL_JOURNALS` to true.

**Release decision: HOLD.** Merge success is not hosted installation. No production SQL, financial data, roles, flags, or tenant resources changed in this increment.
