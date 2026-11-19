#!/usr/bin/env bash
# Phase 11 catalog smoke: REAL Gate58 source, synthetic parent tables, no
# customer records. Leave other publisher RPCs intentionally uninstalled.
set -euo pipefail
phase="$1"
if [[ "$phase" != "baseline" && "$phase" != "patched" ]]; then
  echo "Invalid catalog test phase" >&2; exit 2
fi
if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" != 'onexa_gate_test' ]] ||
  [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.fixture_module_grants') is not null")" != 't' ]]; then
  echo "B4 module catalog only runs in disposable onexa_gate_test" >&2;exit 2
fi

report="$(psql -X -v ON_ERROR_STOP=1 -Atq -F '|' -f supabase/manual-packages/onexa_b4_module_publishers_READ_ONLY.sql)"
lines="$(printf '%s\n' "$report" | grep -c '|')"
if [[ "$lines" != 14 ]]; then
 echo "B4 module catalog must list exactly fourteen RPCs: $lines" >&2
 exit 1
fi
manual="$(printf '%s\n' "$report" | awk -F '|' '$1=="manual_journal"{print $10}')"
expected_manual='SOURCE_TYPE_BLOCKED'
if [[ "$phase" == 'patched' ]]; then expected_manual='SOURCE_PRESENT_ONLY_STAGING_REQUIRED'; fi
if [[ "$manual" != "$expected_manual" ]]; then
 echo "Unexpected installed manual journal source gate: $manual (expected $expected_manual)" >&2
 printf '%s\n' "$report" >&2
 exit 1
fi
missing="$(printf '%s\n' "$report" | awk -F '|' '$10=="MISSING_RPC"{n++}END{print n+0}')"
if [[ "$missing" != 13 ]]; then
 echo "Synthetic module catalog must reveal 13 uninstalled RPCs, got $missing" >&2
 exit 1
fi
present="$(printf '%s\n' "$report" | awk -F '|' '$4=="t"{n++}END{print n+0}')"
if [[ "$present" != 1 ]]; then
 echo "Synthetic module catalog must find one real Gate58 publisher, got $present" >&2
 exit 1
fi
echo "B4 module catalog $phase: 14 rows, manual=$manual, 13 missing (expected synthetic) ✓"
