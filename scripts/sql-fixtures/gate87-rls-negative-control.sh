#!/usr/bin/env bash
set -euo pipefail
# Disposable PostgreSQL ONLY: destructive RLS mutation to prove the check fails.
test "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" = "onexa_gate_test"
table=public.onexa_operations_work_orders
restore() {
  psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE $table ENABLE ROW LEVEL SECURITY" >/dev/null
}
trap restore EXIT
psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE $table DISABLE ROW LEVEL SECURITY" >/dev/null
if psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate86-native-rls-assertions.sql > /tmp/gate87-expected-failure.log 2>&1; then
  echo "Gate 87 failure: Gate 86 accepted a table with RLS disabled" >&2
  exit 1
fi
if ! grep -q 'GATE86_RLS_DISABLED: onexa_operations_work_orders' /tmp/gate87-expected-failure.log; then
  cat /tmp/gate87-expected-failure.log >&2
  echo "Gate 87 failure: rejected for unexpected reason" >&2
  exit 1
fi
restore
trap - EXIT
psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate86-native-rls-assertions.sql >/dev/null
echo "Gate 87: intentionally disabled RLS was rejected; restored and rechecked."
