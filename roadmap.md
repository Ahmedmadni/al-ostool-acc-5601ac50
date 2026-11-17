# ONEXA development acceptance

- [x] November 16 source-only Gate 58 editor hardening: exact-precision monetary validation, valid date/account/branch checks, saved-draft retry, fail-closed identity and SQL null-amount rejection; code/test changes in PR #99. This is **not** hosted installation or production activation. See `docs/runbooks/onexa-manual-journal-preflight-2026-11-16.md`.
- [x] November 16 phase 2: read-only customer catalog diagnosed installed Gate 58 with **missing live server-side null/date-period guards**; drafted checksum-guarded review-only patch, SELECT-only audit, and executable Gate 58 disposable PostgreSQL CI smoke. No hosted changes. See `docs/runbooks/onexa-gate58-live-parity-2026-11-16.md`.
- [x] November 17 phase 3 (source-only): reject sub-0.005 imbalanced journals, avoid source rounding (storage 4 decimals; SAR 2 decimals), match source/GL totals exactly, and require a real linked contra-balance reversal. Added synthetic negative tests plus checksum-guarded **review-only** create-RPC and view patches. See `docs/runbooks/onexa-gate58-exact-reconciliation-2026-11-17.md`. No hosted SQL was modified.
- [x] November 18 phase 4 source-only: correct reviewer-only rejection and creator-only cancellation (submitted cancellation needs reason); validate reversal date/period; require exact table-header balance on fresh installs. Added real Gate 58 SQL negative tests, plus guarded **review-only** lifecycle and existing-balance-constraint patches. See `docs/runbooks/onexa-gate58-lifecycle-authorization-2026-11-18.md`.
- [ ] Phase 4 hosted acceptance: prove zero historical unbalanced headers, restoreable Staging, real B4 closed-period validation and authorization, then obtain explicit change approval before the existing constraint or lifecycle RPCs can be patched.
- [ ] Review historical Gate 58 journals and confirm currency/GL-period rules in isolated Staging, then obtain explicit sign-off before installing either patched live RPC or view.

- [ ] After isolated Staging restores, run hosted tests and apply approved Gate 58 RPC patch; the installed production function still differs from the corrected source. Activation is not authorized.

- [ ] Gate 58 live enablement: requires independent Staging UAT, authorized finance mappings, rollback/reversal tests, and explicit production approval. Keep feature switches off until acceptance.

- [ ] November 14 request: complete subsequent stages and enable manual journals — execute only after approval of the isolated validation plan; production activation remains blocked by missing restore evidence, tenant-session acceptance and finance sign-off. No real journals may be used as test records.

- [x] Resume November 12 development: revalidate approved HR fixes, test Gate 71 prerequisites, and document remaining rollout blockers.

- [x] Run latest HR migrations locally using synthetic tenants; test calculation, draft, refresh, denial and isolation.
- [x] Consolidate Gates 42/63/64/71–75 and B4 dependencies using catalog-only inspection.
- [x] Deliver test evidence, defects and approval boundaries.
- [x] Apply HR hardening (negative leave override, cross-tenant clearance) — applied November 12; final migration passed 32/32 synthetic tests and two persisted regression cases; production catalog guards and grants confirmed.
- [x] Validate Gate 71 in independent synthetic PostgreSQL — 25/25 behavioral checks; all eight postcheck objects ready and expected grant matrix verified.
- [ ] Apply Gate 71 tenant-company bridge — approved November 8; blocked by missing tested customer-clone/backup restore evidence and reviewed index-lock window; synthetic tests do not clear this requirement. Feature remains off; no mappings provisioned.
- [ ] Apply Gates 72→73→42→74→64→75→B4 — blocked: per-gate production approval or approved independent testing plan.
- [ ] Hosted save/readback/print acceptance — blocked: available injected session has no usable tenant claim; browser remained loading, with no save button. Production test settlements remain unauthorized.
