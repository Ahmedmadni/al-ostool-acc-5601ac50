#!/usr/bin/env bash
set -euo pipefail
# Strictly disposable PostgreSQL. Never run on a hosted database.
test "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" = "onexa_gate_test"
table=public.onexa_operations_assets
rpc='public.onexa_create_operations_asset(uuid,text,text,text)'
restore() {
  psql -X -v ON_ERROR_STOP=1 -c "GRANT SELECT ON TABLE $table TO authenticated" >/dev/null
  psql -X -v ON_ERROR_STOP=1 -c "GRANT EXECUTE ON FUNCTION $rpc TO authenticated" >/dev/null
}
trap restore EXIT
# Gate116: authenticated table read revocation must be detected.
psql -X -v ON_ERROR_STOP=1 -c "REVOKE SELECT ON TABLE $table FROM authenticated" >/dev/null
if psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql > /tmp/g116-missing-read.log 2>&1; then
  echo "G116 FAILED: revoked authenticated SELECT was accepted" >&2
  exit 1
fi
grep -Fq "G90_AUTHENTICATED_READ_MISSING: $table" /tmp/g116-missing-read.log || {
  cat /tmp/g116-missing-read.log >&2; exit 1;
}
psql -X -v ON_ERROR_STOP=1 -c "GRANT SELECT ON TABLE $table TO authenticated" >/dev/null
# Gate117: revoked authenticated controlled RPC execution must be detected.
psql -X -v ON_ERROR_STOP=1 -c "REVOKE EXECUTE ON FUNCTION $rpc FROM authenticated" >/dev/null
if psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql > /tmp/g117-missing-rpc.log 2>&1; then
  echo "G117 FAILED: revoked authenticated RPC grant was accepted" >&2
  exit 1
fi
grep -Fq "G90_AUTH_RPC_EXECUTE_MISSING: $rpc" /tmp/g117-missing-rpc.log || {
  cat /tmp/g117-missing-rpc.log >&2; exit 1;
}
# Gate118: restore and re-run the original complete matrix.
restore
trap - EXIT
psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql >/dev/null
echo 'Gates116-118 passed: revoked table SELECT and RPC EXECUTE detected, restored.'
