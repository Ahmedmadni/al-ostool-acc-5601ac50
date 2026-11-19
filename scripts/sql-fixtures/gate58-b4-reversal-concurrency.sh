#!/usr/bin/env bash
# Synthetic CI only. Two independent PostgreSQL sessions race to reverse one
# original GL posting with a different accounting reason/date.
set -euo pipefail
if [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc 'select current_database()')" != 'onexa_gate_test' ]] ||
   [[ "$(psql -X -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.fixture_module_grants') is not null")" != 't' ]]; then
 echo 'ONEXA_B4_REVERSE_RACE_DISPOSABLE_ONLY' >&2
 exit 1
fi
tmp="$(mktemp -d)"
first_pid=''
cleanup() {
  if [[ -n "$first_pid" ]]; then kill "$first_pid" 2>/dev/null || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$tmp/setup.sql" <<'SQL'
begin;
select set_config('test.tenant_id','tenant-smoke-A',true);
select set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
select public.onexa_post_journal(
 'a0000000-0000-4000-8000-000000000001'::uuid,
 'sales_invoice','B4-CONCURRENT-REVERSE-ORIGINAL',1,'approved',
 '{"race":"reverse"}'::jsonb,date '2026-11-18','2026-11',
 'SAR','synthetic reversal race source',
 '[{"account_code":"5200","debit":64.25,"credit":0},{"account_code":"2100","debit":0,"credit":64.25}]'::jsonb);
commit;
SQL
psql -X -v ON_ERROR_STOP=1 -Atq -f "$tmp/setup.sql" >"$tmp/setup.log" 2>&1

cat > "$tmp/first.sql" <<'SQL'
begin;
select set_config('test.tenant_id','tenant-smoke-A',true);
select set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
select public.onexa_reverse_journal(
 (select id from public.onexa_journal_headers
   where source_document_type='sales_invoice'
     and source_document_id='B4-CONCURRENT-REVERSE-ORIGINAL'),
 date '2026-12-03','2026-12','concurrent reason A');
select 'B4_REVERSE_FIRST_LOCK_HELD';
select pg_sleep(4);
commit;
SQL

cat > "$tmp/second.sql" <<'SQL'
begin;
select set_config('test.tenant_id','tenant-smoke-A',true);
select set_config('test.user_id','a0000000-0000-4000-8000-000000000011',true);
select public.onexa_reverse_journal(
 (select id from public.onexa_journal_headers
   where source_document_type='sales_invoice'
     and source_document_id='B4-CONCURRENT-REVERSE-ORIGINAL'),
 date '2026-12-04','2026-12','concurrent reason B');
commit;
SQL

psql -X -v ON_ERROR_STOP=1 -Atq -f "$tmp/first.sql" >"$tmp/first.log" 2>&1 &
first_pid=$!

ready=0
for _ in $(seq 1 100); do
  if grep -q 'B4_REVERSE_FIRST_LOCK_HELD' "$tmp/first.log"; then
    ready=1
    break
  fi
  if ! kill -0 "$first_pid" 2>/dev/null; then
    cat "$tmp/first.log" >&2
    echo "First B4 reversal session exited before holding original row lock" >&2
    exit 1
  fi
  sleep 0.05
done
if [[ "$ready" != '1' ]]; then
  cat "$tmp/first.log" >&2
  echo 'Timed out waiting for the first B4 reversal row lock' >&2
  exit 1
fi

if psql -X -v ON_ERROR_STOP=1 -Atq -f "$tmp/second.sql" >"$tmp/second.log" 2>&1; then
  cat "$tmp/second.log" >&2
  echo 'Conflicting concurrent reversal incorrectly succeeded' >&2
  exit 1
fi
if ! grep -q 'ONEXA_B4_REVERSAL_PAYLOAD_CONFLICT' "$tmp/second.log"; then
  cat "$tmp/second.log" >&2
  echo 'Expected exact B4 reversal payload conflict' >&2
  exit 1
fi
if ! wait "$first_pid"; then
  cat "$tmp/first.log" >&2
  echo 'First B4 reversal failed' >&2
  exit 1
fi
first_pid=''

counts="$(psql -X -v ON_ERROR_STOP=1 -Atc "
  with orig as (
    select id from public.onexa_journal_headers
    where source_document_type='sales_invoice'
      and source_document_id='B4-CONCURRENT-REVERSE-ORIGINAL'
  )
  select
   (select count(*) from public.onexa_journal_headers h
    where h.source_document_type='journal_reversal'
      and h.source_document_id=(select id::text from orig)
      and h.accounting_date=date '2026-12-03'
      and h.source_snapshot->>'reason'='concurrent reason A'),
   (select count(*) from public.onexa_posting_registry r
    where r.source_document_type='journal_reversal'
      and r.source_document_id=(select id::text from orig)),
   (select count(*) from public.onexa_workspace_audit_events a
    where a.entity_id=(select id::text from orig)
      and a.action='journal_reversed'),
   (select count(*) from public.onexa_journal_headers h
    where h.id=(select id from orig) and h.state='reversed'
      and h.reversal_journal_id is not null)
" -F '|')"
if [[ "$counts" != '1|1|1|1' ]]; then
  echo "B4 reversal race left invalid header/registry/audit/original counts: $counts" >&2
  exit 1
fi
echo 'B4 reversal row-lock race passed: original A committed, conflicting B rejected; one contra GL'
