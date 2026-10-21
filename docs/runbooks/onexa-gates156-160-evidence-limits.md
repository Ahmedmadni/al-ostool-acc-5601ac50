# Gates 156–160 — Staging evidence size limits

Gate156 rejects evidence payloads longer than 16 KiB in the offline validator. Gate157 enforces the 16 KiB limit on the CLI input before JSON parsing. Gate158 adds synthetic negative tests for both paths. Gate159 executes the tests in all three disposable CI jobs. Gate160 documents the safety boundary: this is an offline evidence parser, not a hosted Supabase or production validation. Staging is not provisioned, finance mappings are not approved, and no production credentials or data are used.
