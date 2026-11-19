#!/usr/bin/env node
// OFFLINE evidence verifier only. Reads local report files; never connects to
// a database, modifies GitHub, toggles an app feature flag or deploys SQL.
// Passing means "ready for human release review", NOT production deployment.
import { readFileSync } from "node:fs";

const CATALOG = [
  "B4_POST_RETRY_CONTENT_GUARD",
  "B4_PRIVATE_POST_NOT_DIRECTLY_EXECUTABLE",
  "B4_PRIVATE_REVERSE_NOT_DIRECTLY_EXECUTABLE",
  "B4_REVERSE_RETRY_CONTENT_GUARD",
  "B4_STRICT_MONEY_CHECKS",
  "G58_AMENDMENT_FUNCTION_INSTALLED",
  "G58_POST_REAL_GL_RECEIPT_VALIDATION",
  "G58_REVERSE_REPLAY_GL_VALIDATION",
  "G58_TABLE_RLS_ENABLED",
  "GL_HEADER_EXACTLY_BALANCED",
  "GL_MANUAL_SOURCE_ALLOWED",
];

const LEDGER = [
  "REGISTRY_TARGET_MISSING","REGISTRY_SOURCE_MISMATCH",
  "REGISTRY_KEY_MISMATCH","HEADER_WITHOUT_REGISTRY",
  "DUPLICATE_SOURCE_RECEIPT","HEADER_IMBALANCED",
  "LINE_COUNT_LT_TWO","LINE_SUM_MISMATCH",
  "LINE_SIDE_INVALID","LINE_TENANT_MISMATCH",
  "PERIOD_ENTITY_DATE_MISMATCH","REVERSED_ORIGINAL_LINK_MISMATCH",
  "POSTED_WITH_REVERSAL_POINTER","REVERSAL_SOURCE_LINK_MISMATCH",
  "REVERSAL_TOTALS_MISMATCH","REVERSAL_REASON_RECEIPT_MISMATCH",
  "REVERSAL_ORDERED_LINES_MISMATCH",
];

const REQUIRED_SIGNOFFS = [
  "restore_test_passed",
  "finance_approved",
  "security_approved",
  "module_e2e_passed",
  "historical_exceptions_reviewed",
  "sql_preconditions_reviewed",
  "deployment_order_reviewed",
  "rollback_drill_passed",
  "feature_flags_disabled",
  "change_record_approved",
];

function parsePsv(file, codes, width) {
  const rows = new Map();
  const content = readFileSync(file, "utf8");
  for (const line of content.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const cells = line.trim().split("|");
    if (cells.length !== width) {
      throw new Error("Invalid report shape in " + file);
    }
    const [code] = cells;
    if (!codes.includes(code) || rows.has(code)) {
      throw new Error("Unexpected/duplicate gate code: " + code);
    }
    rows.set(code, cells);
  }
  for (const code of codes) {
    if (!rows.has(code)) throw new Error("Missing report category: " + code);
  }
  return rows;
}

function verify(catalogFile, ledgerFile, signoffsFile) {
  const blockers = [];
  const catalog = parsePsv(catalogFile, CATALOG, 2);
  const ledger = parsePsv(ledgerFile, LEDGER, 3);
  for (const code of CATALOG) {
    const status = catalog.get(code)[1];
    if (status !== "READY" && status !== "HOLD") {
      throw new Error("Unexpected technical catalog status for " + code + ": " + status);
    }
    if (status !== "READY") blockers.push("CATALOG:" + code);
  }
  for (const code of LEDGER) {
    const [, severity, value] = ledger.get(code);
    if (severity !== "BLOCK" && severity !== "REVIEW") {
      throw new Error("Invalid ledger severity for " + code);
    }
    if (!/^(0|[1-9]\d*)$/.test(value)) {
      throw new Error("Non-numeric/untrusted ledger finding for " + code);
    }
    if (BigInt(value) !== 0n) {
      // Even REVIEW-category ledger gaps require reconciliation, not waiver.
      blockers.push("LEDGER:" + code + "(" + value + ")");
    }
  }
  const signoffs = JSON.parse(readFileSync(signoffsFile, "utf8"));
  if (signoffs.environment !== "independently_restored_staging") {
    blockers.push("EVIDENCE:independently_restored_staging");
  }
  for (const key of REQUIRED_SIGNOFFS) {
    if (signoffs[key] !== true) blockers.push("EVIDENCE:" + key);
  }
  return blockers;
}

if (process.argv.length !== 5) {
  console.error("Usage: node scripts/onexa-b4-staging-evidence-gate.mjs CATALOG.psv LEDGER.psv ATTESTATION.json");
  process.exit(2);
}

try {
  const blockers = verify(...process.argv.slice(2));
  if (blockers.length) {
    console.log("ONEXA STAGING RELEASE HOLD (" + blockers.length + " unresolved requirements)");
    for (const item of blockers) console.log(" - " + item);
    process.exitCode = 1;
  } else {
    console.log("ONEXA STAGING EVIDENCE COMPLETE — HUMAN FINANCE/SECURITY RELEASE REVIEW STILL REQUIRED.");
    console.log("This verifier does NOT deploy, approve production or enable feature flags.");
  }
} catch (error) {
  console.error("ONEXA STAGING RELEASE HOLD: " + error.message);
  process.exitCode = 2;
}
