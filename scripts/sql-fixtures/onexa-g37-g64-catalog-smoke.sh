#!/usr/bin/env bash
# ONLY on onexa_gate_test (synthetic native parents); a non-production negative
# control. It runs the EXACT read-only catalog SQL used in a restored Staging
# environment. It must return HOLD while G7/G8/G37/G64 are not installed.
set -euo pipefail
if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" != 'onexa_gate_test' ]] ||
   [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.fixture_module_grants') is not null")" != 't' ]]; then
  echo "ONEXA_G37_G64_CATALOG_DISPOSABLE_ONLY" >&2
  exit 2
fi
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
psql -X -v ON_ERROR_STOP=1 -Atq -F '|' \
  -f supabase/manual-packages/onexa_g37_g64_chain_READ_ONLY.sql >"$temp/chain.psv"
psql -X -v ON_ERROR_STOP=1 -Atq -F '|' \
  -f supabase/manual-packages/onexa_g64_patch_guard_READ_ONLY.sql >"$temp/guard.psv"

set +e
node scripts/onexa-g37-g64-foundation-gate.mjs "$temp/chain.psv" "$temp/guard.psv" > "$temp/result.txt" 2>&1
status="$?"
set -e
if [[ "$status" != '1' ]]; then
  cat "$temp/result.txt" >&2
  echo "Missing payroll/G64 staging prerequisites must HOLD, got exit $status" >&2
  exit 1
fi
for required in \
 "FOUNDATION:G7_PRE:attendance_periods" \
 "FOUNDATION:G8_INST:employer_cost_fn" \
 "FOUNDATION:G37_INST:payroll_journal_rpc" \
 "G64:MISSING:G42:public.onexa_post_project_cost(uuid,text)"; do
  if ! grep -Fq "$required" "$temp/result.txt"; then
    cat "$temp/result.txt" >&2
    echo "G37/G64 missing dependency was not diagnosed: $required" >&2
    exit 1
  fi
done
if [[ "$(awk -F '|' 'NF==7{n++}END{print n+0}' "$temp/chain.psv")" != 35 ]] ||
   [[ "$(awk -F '|' 'NF==6{n++}END{print n+0}' "$temp/guard.psv")" != 7 ]]; then
  echo "Read-only SQL reports must return 35 prerequisite rows plus 7 G64 guard rows" >&2
  exit 1
fi
echo "G7/G8/G37/G64 read-only PostgreSQL smoke passed: 35 metadata checks + 7 guard reports; unsafe installation held"
