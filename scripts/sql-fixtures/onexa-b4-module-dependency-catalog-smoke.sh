#!/usr/bin/env bash
# ONEXA Phase12: exact operator catalog on disposable PostgreSQL only.
# Never queries or changes customer finance data.
set -euo pipefail
phase="$1"
if [[ "$phase" != "baseline" && "$phase" != "source-type-patched" ]]; then
 echo "Unknown B4 dependency smoke phase" >&2; exit 2
fi
if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" != "onexa_gate_test" ]] ||
  [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.fixture_module_grants') is not null")" != "t" ]]; then
 echo "ONEXA_PHASE12_DISPOSABLE_ONLY" >&2; exit 2
fi
report="$(psql -X -v ON_ERROR_STOP=1 -Atq -F '|' -f supabase/manual-packages/onexa_b4_module_dependencies_READ_ONLY.sql)"
count="$(printf '%s\n' "$report" | awk -F '|' 'NF==11 {n++}END {print n+0}')"
if [[ "$count" != 17 ]]; then
 echo "Expected all 17 dependency nodes, found $count" >&2
 printf '%s\n' "$report" >&2
 exit 1
fi
assert_status() {
 local id="$1" status="$2" observed
 observed="$(printf '%s\n' "$report" | awk -F '|' -v node="$id" '$1==node {print $11}')"
 if [[ "$observed" != "$status" ]]; then
   echo "Dependency plan must classify $id as $status, got $observed" >&2
   printf '%s\n' "$report" >&2; exit 1
 fi
}
assert_status g66 SAAS_LEGACY_WRITER_FORBIDDEN
assert_status g67 LEGACY_REAL_ESTATE_COMPAT_REVIEW
assert_status g64 PREREQUISITES_MISSING
assert_status g65 PREREQUISITES_MISSING
if [[ "$phase" == "baseline" ]]; then
 assert_status g58 MANUAL_JOURNAL_ALLOWLIST_BLOCKED
else
 assert_status g58 CATALOG_PRESENT_STAGING_REQUIRED
fi
# Require G64 to report absent prerequisite publisher RPCs.
if ! printf '%s\n' "$report" | awk -F '|' '$1=="g64" && $6>0 && $8>0{ok=1}END{exit !ok}'; then
 echo "Approval bridge must report actual missing module prerequisites" >&2;exit 1
fi
echo "ONEXA B4 dependency catalog $phase: 17 metadata nodes, G64/G65 withheld, legacy G66 forbidden"
