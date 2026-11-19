# ONEXA — Phase 8: B4 posting idempotency must verify approved accounting payload (2026-11-19)

## Observed hosted behavior (read-only)

The connected ONEXA `onexa_private.post_journal` function still matches the original MD5 `5ac58a780bbed49e8ba31b6f46c39f48`. In its existing implementation the unique posting key combines tenant, legal entity, source type, source document ID and source revision. Under a transaction-scoped advisory lock, an existing posting registry entry causes an immediate return of the previous GL journal UUID **without comparing the new approved source contents**.

This correctly avoids duplicate rows, but does **not** establish that a retry is the same accounting transaction. A caller accidentally or improperly reusing the same revision with a changed amount, account, memo, date, currency, cost centre, dimensions or snapshot can receive a false success response referring to stale GL data.

This is a confirmed source-code issue. The legacy behavior is reproduced in disposable PostgreSQL with the captured real B4 functions and synthetic finance data, without issuing financial transactions against production.

## Source-only improvement

The existing guarded `gate58_b4_strict_monetary_REVIEW_ONLY.sql` candidate and its exact disposable test fixture have been updated together. No hosted function is modified.

In `onexa_private.post_journal`, after the existing advisory lock and lookup, if the key already exists the proposed function verifies **both** the registry and the stored accounting receipt:

- Tenant, legal entity, source type/ID/revision, accounting date, fiscal period and currency are unchanged.
- Approved source snapshot (JSONB), memo and exact debit/credit totals equal the stored header. Null memo is compared null-safely.
- Every GL line agrees with the supplied source by **ordinal line order**, account code, debit, credit, normalized description and full dimensions (including projects and cost centres).
- The original GL header still exists in the same tenant and is `posted` or `reversed`. A reversed GL entry remains the historical posting receipt, not permission to create a second journal.
- Exact duplicate source payloads return the **same** UUID. Numeric formatting such as `80.25` vs `80.2500`, or reordered JSON object keys, is treated as equivalent by PostgreSQL's JSONB numeric/object semantics.
- Changed payload or corrupted stored header/lines raises `ONEXA_B4_POSTING_PAYLOAD_CONFLICT`, before any new journal or event is created.

This does not attempt to authorize edits to an already-posted source. If a financial document legitimately changes, the owning module must use a governed new revision and, where required, an approved reversal/correction rather than silently reusing the original idempotency key.

## Executable acceptance evidence

The extended `B4 Shared GL Foundation Integrity` CI workflow runs only against `onexa_gate_test`, with synthetic tenants and captured real B4 wrapper functions.

1. `gate58-b4-idempotency-legacy-smoke.sql`: demonstrates the current B4 returns the old UUID even when the second same-key source has different totals/snapshot/memo, and rolls back.
2. `gate58-b4-idempotency-strict-smoke.sql`: verifies successful exact retry, semantically equivalent numeric/JSON formatting, ten kinds of changed inputs, corrupted header or GL line receipt refusal, reversed-status historical retry and no duplicate registry, lines or posted audit events; fully rolls back.
3. `gate58-b4-idempotency-concurrency.sh`: opens **two separate PostgreSQL sessions** using one identical source key but different amounts. The first transaction holds the advisory lock while the second queues. It verifies only one approved journal/header/two GL lines/one audit event are stored and the competing request receives the exact payload-conflict error. All records are **synthetic in the disposable CI container**.

The contract checker also requires byte-identical strict publisher bodies between review-only SQL and disposable integration fixture and confirms the GitHub workflow runs every test. The read-only hosted B4 audit now reports whether the payload guard exists, without accessing actual journal records.

## Deployment and financial acceptance

**HOLD: source-only.** The existing review-only strict-monetary package still requires the currently deployed B4 checksum and the broader phase-seven schema changes. It must not be executed against the connected customer project without **independent restored Staging, actual workflow payload compatibility tests for all modules, financial/security authorization and a tested rollback plan**.

Particular questions for finance owners:
- Do any modules change source snapshot generation timestamps, memo, dimensions or line order between an initial approved post and a retry? Such retries must now fail explicitly; this is intentional fail-closed behavior but requires source stability.
- Are all modules incrementing revision on approved accounting changes, and do they require an offsetting reversal before posting a new revision?
- What is the allowed currency-specific precision and source rounding policy beyond SAR?
- What happens if a reversal is retried with a different reason/date? **The shared B4 reversal early-return path is a separate remaining issue** and is not remediated by this posting-key change.
- Can genuine tenant security claims and module role grants be verified in Staging, not only in synthetic CI?

Do not present GitHub sync as an installed B4 migration. Any use of the live database remains SELECT-only until the approved staged release process.
