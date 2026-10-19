#!/usr/bin/env bash
set -euo pipefail
test "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" = "onexa_gate_test"
table=public.onexa_operations_work_orders
restore() {
  psql -X -v ON_ERROR_STOP=1 -c "REVOKE SELECT ON $table FROM anon" >/dev/null
}
trap restore EXIT
psql -X -v ON_ERROR_STOP=1 -c "GRANT SELECT ON $table TO anon" >/dev/null
if psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql > /tmp/onexa-g91-negative.log 2>&1; then
  echo 'Gate91: unexpected success when anon has SELECT on work orders' >&2
  exit 1
fi
if ! grep -q 'G90_ANON_TABLE_PRIVILEGE: public.onexa_operations_work_orders SELECT' /tmp/onexa-g91-negative.log; then
  cat /tmp/onexa-g91-negative.log >&2
  echo 'Gate91: rejected for unexpected reason' >&2
  exit 1
fi
restore
trap - EXIT
psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql >/dev/null
echo 'Gate91: anon grant escalation rejected and reverted.'
