# Gates 126–130: approval audit continuity

G126 checks the unique posted decision names the assigned synthetic posting actor. G127 checks no approval instance remains awaiting post once the actual Gate42/Gate64 posting completed. G128 checks a synthetic reversal does not mutate the historical posting actor. G129 adds a source-contract regression check, invoked in all three disposable PostgreSQL CI jobs. G130 documents release blockers.

**Scope:** Real Gate42 and Gate64 SQL is executed against synthetic parent fixtures on ephemeral PostgreSQL. These tests do not certify real Supabase JWT roles, actual finance mappings, source records or full ledger line completeness. Hosted Staging, two tenant UAT, finance approval and backup/recovery rehearsal remain blockers. No production changes.
