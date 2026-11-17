-- ONEXA Gate 58 — historical balance constraint hardening (REVIEW ONLY).
-- NOT automatically deployed. Run only in a dedicated, approved Staging
-- environment with independently tested database restore and finance sign-off.
-- ALTER TABLE takes a strong lock: operator must approve a maintenance window.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $gate58_preflight$
declare
  _constraint oid;
begin
  if to_regclass('public.onexa_manual_journals') is null then
    raise exception 'ONEXA_GATE58_BALANCE_TABLE_MISSING';
  end if;
  select c.oid into _constraint
  from pg_constraint c
  where c.conrelid = 'public.onexa_manual_journals'::regclass
    and c.conname = 'onexa_manual_journals_balanced'
    and c.contype = 'c';
  if _constraint is null or pg_get_constraintdef(_constraint, true) <>
    'CHECK (abs(total_debit - total_credit) <= 0.005)' then
    raise exception 'ONEXA_GATE58_BALANCE_CONSTRAINT_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
  -- Reject the entire migration if historical rows are unbalanced.
  -- Do not auto-repair financial records or silently delete anything.
  if exists (
    select 1 from public.onexa_manual_journals
    where total_debit is distinct from total_credit
  ) then
    raise exception 'ONEXA_GATE58_HISTORICAL_UNBALANCED_ROWS_STOP_FINANCE_REVIEW_REQUIRED';
  end if;
end;
$gate58_preflight$;

alter table public.onexa_manual_journals
  drop constraint onexa_manual_journals_balanced;

alter table public.onexa_manual_journals
  add constraint onexa_manual_journals_balanced
  check (total_debit = total_credit);

-- Financial history and privilege grants are intentionally not modified.
commit;
