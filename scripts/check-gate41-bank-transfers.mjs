import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const sql = read("supabase/manual-packages/gate41_bank_transfers.sql");
const mapping = read("supabase/manual-packages/gate41_aoa_treasury_accounts.sql");
const postcheck = read("supabase/manual-packages/gate41_postcheck.sql");
const smoke = read("supabase/manual-packages/gate41_bank_transfer_smoke_test_rollback.sql");
const service = read("src/lib/finance/bank-transfer-service.ts");
const panel = read("src/components/finance/onexa-bank-transfers-panel.tsx");
const route = read("src/routes/_authenticated/banks/index.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "onexa_post_journal(", "onexa_treasury_accounts", "onexa_bank_transfer_postings",
  "onexa_private.claim_tenant_id()", "has_module_action(_actor, 'finance', 'post')",
  "pg_advisory_xact_lock", "order by id for update", "security_invoker = true",
  "enable row level security", "ONEXA_POSTER_MUST_DIFFER_FROM_CREATOR",
  "ONEXA_BANK_TRANSFER_SAME_ACCOUNT", "ONEXA_BANK_TRANSFER_ACCOUNT_SCOPE_INVALID",
  "onexa.transition_authorized", "_source_document_type => 'bank_transfer'",
  "ONEXA_POSTED_TREASURY_ACCOUNT_IMMUTABLE",
]) assert.ok(sql.includes(marker), `Missing treasury control: ${marker}`);
assert.ok(sql.includes("'account_code', _destination.account_code,\n        'debit', _document.gross_total"));
assert.ok(sql.includes("'account_code', _source.account_code,\n        'debit', 0, 'credit', _document.gross_total"));
assert.ok(!/grant\s+(insert|update|delete)/i.test(sql), "Direct treasury ledger writes exposed");
assert.ok(mapping.includes("ONEXA_GATE41_CONFIRMED_BANK_ACCOUNTS_REQUIRED"));
assert.ok(mapping.includes("REPLACE_SOURCE_BANK_GL_CODE"));
assert.ok(postcheck.includes("direct_writes_denied") && postcheck.includes("security_invoker"));
assert.ok(smoke.includes("ONEXA_SMOKE_BANK_RETRY_FAILED"));
assert.ok(smoke.includes("ONEXA_SMOKE_CROSS_TENANT_BANK_TRANSFER_ALLOWED"));
assert.match(smoke.trim(), /rollback;$/);
assert.ok(!smoke.includes("commit;"));
assert.ok(service.includes("createBusinessDocument") && service.includes("onexa_post_bank_transfer"));
assert.ok(panel.includes("approveOnexaBankTransfer") && route.includes("OnexaBankTransfersPanel"));
assert.ok(flags.includes("ONEXA_BANK_TRANSFER_POSTING_ENABLED"));
assert.ok(env.includes('VITE_ENABLE_ONEXA_BANK_TRANSFER_POSTING=""'));
assert.ok(pkg.scripts.verify.includes("check:gate41-bank-transfers"));
assert.match(sql, /journal\.state = 'posted'/);
assert.match(sql, /journal\.reversal_journal_id is null/);
assert.match(sql, /journal_reversed_or_missing/);
assert.match(sql, /journal_source_or_amount_mismatch/);
assert.match(sql, /journal\.source_document_type is distinct from 'bank_transfer'/);
assert.match(sql, /journal\.total_debit is distinct from document\.gross_total/);
assert.match(sql, /journal\.total_credit is distinct from document\.gross_total/);
assert.match(sql, /ONEXA_BANK_TRANSFER_JOURNAL_REVERSED_OR_MISSING/);
assert.match(sql, /posting\.legal_entity_id = document\.legal_entity_id/);
assert.match(sql, /account_scope_mismatch/);
assert.match(panel, /today\.getFullYear\(\)/);
assert.match(panel, /today\.getMonth\(\)/);
assert.doesNotMatch(panel, /new Date\(\)\.toISOString\(\)\.slice\(0, 10\)/);
assert.match(postcheck, /journal_reversed_or_missing/);
console.log("Gate 41 bank transfer package checks passed");
