#!/usr/bin/env bash
set -euo pipefail
# Gates 111-114: destructive negative tests are restricted to disposable DB.
test "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" = "onexa_gate_test"
table=public.onexa_operations_work_orders
rpc='public.onexa_create_operations_site(uuid,uuid,text,text)'
restore() {
  psql -X -v ON_ERROR_STOP=1 -c "REVOKE EXECUTE ON FUNCTION $rpc FROM anon" >/dev/null
  psql -X -v ON_ERROR_STOP=1 -c "REVOKE UPDATE ON TABLE $table FROM authenticated" >/dev/null
}
trap restore EXIT
# Gate111: Anonymous RPC execution must be rejected by G90 catalog contract.
psql -X -v ON_ERROR_STOP=1 -c "GRANT EXECUTE ON FUNCTION $rpc TO anon" >/dev/null
if psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql > /tmp/g111-denied.log 2>&1; then
  echo 'G111 failed: unauthorized anonymous RPC grant was accepted' >&2; exit 1
fi
if ! grep -Fq "G90_ANON_RPC_EXECUTE: $rpc" /tmp/g111-denied.log; then
  cat /tmp/g111-denied.log >&2
  echo 'G111 failed: expected RPC privilege error absent' >&2; exit 1
fi
psql -X -v ON_ERROR_STOP=1 -c "REVOKE EXECUTE ON FUNCTION $rpc FROM anon" >/dev/null
# Gate112: authenticated must never have direct UPDATE on work-order records.
psql -X -v ON_ERROR_STOP=1 -c "GRANT UPDATE ON TABLE $table TO authenticated" >/dev/null
if psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql > /tmp/g112-denied.log 2>&1; then
  echo 'G112 failed: authenticated direct UPDATE grant was accepted' >&2; exit 1
fi
if ! grep -Fq "G90_AUTHENTICATED_DIRECT_WRITE: $table UPDATE" /tmp/g112-denied.log; then
  cat /tmp/g112-denied.log >&2
  echo 'G112 failed: expected UPDATE privilege error absent' >&2; exit 1
fi
# Gate113: revoked privilege must restore healthy matrix.
restore
trap - EXIT
psql -X -v ON_ERROR_STOP=1 -f scripts/sql-fixtures/gate90-native-grant-matrix.sql >/dev/null
echo 'Gates111-113 passed: unauthorized RPC and UPDATE grants detected; clean restore verified.'
