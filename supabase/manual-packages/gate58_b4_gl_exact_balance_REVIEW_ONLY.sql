-- B4 main-ledger exact debit/credit header equality — REVIEW ONLY.
-- Observe and reconcile historical GL entries BEFORE attempting this patch.
-- No customer financial entries are altered by this script; refusal is atomic.
-- Requires independently restored Staging, finance sign-off, tested restore,
-- maintenance lock window, and reviewed cross-module exact monetary patch.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $preflight$
declare _original text;
begin
  if to_regclass('public.onexa_journal_headers') is null then
    raise exception 'ONEXA_B4_HEADERS_MISSING_STOP';
  end if;
  select pg_get_constraintdef(c.oid,true) into _original
  from pg_constraint c
  where c.conrelid='public.onexa_journal_headers'::regclass
    and c.contype='c' and c.conname='onexa_journal_headers_check';
  if _original is distinct from
    'CHECK (abs(total_debit - total_credit) <= 0.005)' then
    raise exception 'ONEXA_B4_HEADER_BALANCE_CONSTRAINT_DRIFT_STOP';
  end if;
  if exists(
    select 1 from public.onexa_journal_headers
    where total_debit is distinct from total_credit
  ) then
    raise exception 'ONEXA_B4_HISTORICAL_IMBALANCE_REQUIRES_FINANCE_REVIEW';
  end if;
  if exists (
    select 1 from pg_constraint
    where conrelid='public.onexa_journal_headers'::regclass
      and conname='onexa_journal_headers_exact_balance_v2'
  ) then
    raise exception 'ONEXA_B4_EXACT_BALANCE_STAGING_CONFLICT_STOP';
  end if;
end;
$preflight$;

alter table public.onexa_journal_headers
 add constraint onexa_journal_headers_exact_balance_v2
 check (total_debit = total_credit) not valid;

alter table public.onexa_journal_headers
 validate constraint onexa_journal_headers_exact_balance_v2;

alter table public.onexa_journal_headers
 drop constraint onexa_journal_headers_check;

alter table public.onexa_journal_headers
 rename constraint onexa_journal_headers_exact_balance_v2
 to onexa_journal_headers_check;

commit;
