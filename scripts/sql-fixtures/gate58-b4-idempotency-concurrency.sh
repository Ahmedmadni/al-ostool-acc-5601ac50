#!/usr/bin/env bash
# DISPOSABLE PostgreSQL ONLY. Two independent sessions race on the same
# B4 source/revision key but different approved content.
set -euo pipefail

if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" != "onexa_gate_test" ]]; then
  echo "B4 concurrency smoke must run only against onexa_gate_test" >&2
  exit 1
fi
if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.fixture_module_grants') is not null")" != "t" ]]; then
  echo "Synthetic tenancy fixtures required" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/first.sql" <<'SQL'
begin;
select set_config('test.tenant_id','tenant-smoke-A',true);
select set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
select public.onexa_post_journal(
 'a0000000-0000-4000-8000-000000000001'::uuid,
 'sales_invoice','B4-RACE-SOURCE-001',1,'approved',
 '{"correction":"A"}'::jsonb,date '2026-11-18','2026-11',
 'SAR','document A',
 '[{"account_code":"5200","debit":76.25,"credit":0},{"account_code":"2100","debit":0,"credit":76.25}]'::jsonb
);
select pg_sleep(3);
commit;
SQL

cat > "$tmp/second.sql" <<'SQL'
begin;
select set_config('test.tenant_id','tenant-smoke-A',true);
select set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
select public.onexa_post_journal(
 'a0000000-0000-4000-8000-000000000001'::uuid,
 'sales_invoice','B4-RACE-SOURCE-001',1,'approved',
 '{"correction":"B"}'::jsonb,date '2026-11-18','2026-11',
 'SAR','document B',
 '[{"account_code":"5200","debit":90.25,"credit":0},{"account_code":"2100","debit":0,"credit":90.25}]'::jsonb
);
commit;
SQL

psql -X -v ON_ERROR_STOP=1 -Atq -f "$tmp/first.sql" >"$tmp/first.log" 2>&1 &
first_pid=$!

# Wait until the first transaction holds its PostgreSQL advisory lock.
# This makes the competing request queue behind the already-started one.
locked=0
for _ in $(seq 1 100); do
  if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select count(*) from pg_locks where locktype='advisory' and granted and pid<>pg_backend_pid()")" != "0" ]]; then
    locked=1
    break
  fi
  if ! kill -0 "$first_pid" 2>/dev/null; then
    cat "$tmp/first.log" >&2
    echo "First B4 posting exited before advisory lock acquired" >&2
    exit 1
  fi
  sleep 0.05
done

if [[ "$locked" != "1" ]]; then
  cat "$tmp/first.log" >&2
  echo "Timed out waiting for B4 advisory transaction lock" >&2
  exit 1
fi

if psql -X -v ON_ERROR_STOP=1 -Atq -f "$tmp/second.sql" >"$tmp/second.log" 2>&1; then
  cat "$tmp/second.log" >&2
  echo "Conflicting concurrent B4 posting unexpectedly accepted" >&2
  exit 1
fi

if ! grep -q 'ONEXA_B4_POSTING_PAYLOAD_CONFLICT' "$tmp/second.log"; then
  cat "$tmp/second.log" >&2
  echo "Concurrent rejection did not come from the payload guard" >&2
  exit 1
fi

if ! wait "$first_pid"; then
  cat "$tmp/first.log" >&2
  echo "Original B4 posting failed" >&2
  exit 1
fi

totals="$(psql -X -v ON_ERROR_STOP=1 -At -F '|' -c "
select
 (select count(*) from public.onexa_posting_registry where source_document_id='B4-RACE-SOURCE-001'),
 (select count(*) from public.onexa_journal_headers where source_document_id='B4-RACE-SOURCE-001'
   and memo='document A' and total_debit=76.25 and total_credit=76.25),
 (select count(*) from public.onexa_journal_lines l
   join public.onexa_journal_headers h on h.id=l.journal_id
   where h.source_document_id='B4-RACE-SOURCE-001'),
 (select count(*) from public.onexa_workspace_audit_events a
   join public.onexa_journal_headers h on h.id::text=a.entity_id
   where h.source_document_id='B4-RACE-SOURCE-001' and a.action='journal_posted')
")"
if [[ "$totals" != '1|1|2|1' ]]; then
  echo "Unexpected concurrent GL registry/header/line/audit counts: $totals" >&2
  exit 1
fi

echo "B4 concurrent idempotency: one approved source posted, altered retry rejected, one GL/audit receipt"
