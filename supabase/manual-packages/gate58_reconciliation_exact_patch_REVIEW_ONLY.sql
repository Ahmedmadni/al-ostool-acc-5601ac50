-- ONEXA G58 reconciliation-view precision correction — REVIEW ONLY.
-- NOT run by CI or against connected production. Requires independent staging,
-- verified restore, approved change window and finance sign-off.
-- The MD5 is the catalog-view definition observed read-only on 2026-11-17
-- from the connected project, not proof of backup readiness or UAT acceptance.
begin;

do $preflight$
declare
  _view regclass := to_regclass('public.onexa_manual_journal_reconciliation');
begin
  if _view is null
    or to_regclass('public.onexa_manual_journals') is null
    or to_regclass('public.onexa_journal_headers') is null then
    raise exception 'ONEXA_G58_VIEW_DEPENDENCY_MISSING_STOP';
  end if;
  if md5(pg_get_viewdef(_view::oid, true)) <> 'bd0ad9c8eeec4f6567d1bb0f6d776aa7' then
    raise exception 'ONEXA_G58_VIEW_DEFINITION_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
  if not exists (
    select 1 from pg_class c where c.oid = _view::oid
      and 'security_invoker=true' = any(c.reloptions)
  ) then
    raise exception 'ONEXA_G58_VIEW_MUST_REMAIN_SECURITY_INVOKER';
  end if;
end;
$preflight$;

create or replace view public.onexa_manual_journal_reconciliation
with (security_invoker = true)
as
select
  manual.id as manual_journal_id,
  manual.tenant_id,
  manual.legal_entity_id,
  manual.branch_id,
  manual.journal_number,
  manual.accounting_date,
  manual.period_code,
  manual.currency,
  manual.memo,
  manual.status,
  manual.total_debit,
  manual.total_credit,
  manual.posted_journal_id,
  manual.reversal_journal_id,
  header.journal_number as ledger_journal_number,
  header.total_debit as ledger_total_debit,
  header.total_credit as ledger_total_credit,
  case
    when manual.status in ('draft','submitted','approved','rejected','cancelled') then 'not_posted'
    when manual.status in ('posted','reversed') and header.id is null then 'journal_missing'
    when manual.status = 'reversed' and
      (manual.reversal_journal_id is null or reversal.id is null) then 'reversal_missing'
    when manual.status = 'reversed' and (
      reversal.reversal_of_id is distinct from manual.posted_journal_id
      or reversal.legal_entity_id is distinct from manual.legal_entity_id
      or reversal.total_debit is distinct from header.total_credit
      or reversal.total_credit is distinct from header.total_debit
    ) then 'reversal_mismatch'
    when manual.total_debit is distinct from header.total_debit
      or manual.total_credit is distinct from header.total_credit
      or header.legal_entity_id is distinct from manual.legal_entity_id then 'amount_mismatch'
    else 'reconciled'
  end as reconciliation_status
from public.onexa_manual_journals manual
left join public.onexa_journal_headers header
  on header.id = manual.posted_journal_id
 and header.tenant_id = manual.tenant_id
left join public.onexa_journal_headers reversal
  on reversal.id = manual.reversal_journal_id
 and reversal.tenant_id = manual.tenant_id;

-- CREATE OR REPLACE preserves existing grants; do not modify RLS or access.
commit;
