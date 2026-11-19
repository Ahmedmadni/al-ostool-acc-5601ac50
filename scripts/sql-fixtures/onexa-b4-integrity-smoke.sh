#!/usr/bin/env bash
# Run only inside disposable PostgreSQL GitHub Actions, never hosted.
set -euo pipefail
if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" != 'onexa_gate_test' ]] ||
  [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.fixture_module_grants') is not null")" != 't' ]]; then
  echo 'ONEXA_B4_LEDGER_INTEGRITY_DISPOSABLE_ONLY' >&2
  exit 1
fi

audit="supabase/manual-packages/onexa_b4_ledger_integrity_READ_ONLY.sql"
psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/onexa-b4-integrity-seed-ONLY.sql

check_report() {
  local report="$1"
  local expected="$2"
  local name
  for name in \
    REGISTRY_TARGET_MISSING \
    REGISTRY_SOURCE_MISMATCH \
    REGISTRY_KEY_MISMATCH \
    HEADER_WITHOUT_REGISTRY \
    DUPLICATE_SOURCE_RECEIPT \
    HEADER_IMBALANCED \
    LINE_COUNT_LT_TWO \
    LINE_SUM_MISMATCH \
    LINE_SIDE_INVALID \
    LINE_TENANT_MISMATCH \
    PERIOD_ENTITY_DATE_MISMATCH \
    REVERSED_ORIGINAL_LINK_MISMATCH \
    POSTED_WITH_REVERSAL_POINTER \
    REVERSAL_SOURCE_LINK_MISMATCH \
    REVERSAL_TOTALS_MISMATCH \
    REVERSAL_REASON_RECEIPT_MISMATCH \
    REVERSAL_ORDERED_LINES_MISMATCH; do
    local count
    count="$(printf '%s\n' "$report" | awk -F '|' -v code="$name" '$1==code {print $3}')"
    if [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]]; then
      echo "Missing/non-numeric integrity report code $name: $count" >&2
      exit 1
    fi
    if [[ "$expected" == 'clean' && "$count" -ne 0 ]] ||
       [[ "$expected" == 'corrupt' && "$count" -eq 0 ]]; then
      echo "Incorrect $name finding count for $expected synthetic ledger: $count" >&2
      printf '%s\n' "$report" >&2
      exit 1
    fi
  done
  if [[ "$(printf '%s\n' "$report" | awk -F '|' '$1 != "" {n++} END {print n+0}')" -ne 17 ]]; then
    echo "Expected exactly seventeen stable audit categories" >&2
    exit 1
  fi
}

# Audit before injecting any synthetic anomalies.
clean="$(psql -X -v ON_ERROR_STOP=1 -Atq -F '|' -f "$audit")"
check_report "$clean" clean

# Execute the EXACT SAME read-only query WITHIN the deliberate corruption
# transaction; ROLLBACK must restore every original synthetic ledger row.
corrupt="$(psql -X -v ON_ERROR_STOP=1 -Atq -F '|' -f scripts/sql-fixtures/onexa-b4-integrity-corrupt-ROLLBACK.sql)"
check_report "$corrupt" corrupt

clean_after="$(psql -X -v ON_ERROR_STOP=1 -Atq -F '|' -f "$audit")"
check_report "$clean_after" clean

echo "ONEXA B4 integrity audit: clean 0/17, injected all 17 anomaly categories, rolled back 0/17 ✓"
