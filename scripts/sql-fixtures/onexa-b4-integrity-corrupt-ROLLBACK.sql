-- Deliberately corrupt SYNTHETIC GL data in a transaction; run the exact
-- same production-compatible SELECT-only integrity query, then ROLLBACK.
-- NEVER use on hosted project. File contains deliberate DELETE/UPDATE/ALTER!
begin;

do $preflight$
begin
  if current_database()<>'onexa_gate_test'
     or to_regclass('public.fixture_module_grants') is null
     or to_regclass('public.onexa_posting_registry') is null
     or not exists (
       select 1 from public.onexa_journal_headers
       where source_document_id='INTEGRITY-SEED-sales_invoice'
         and tenant_id='tenant-smoke-A'
     ) then
    raise exception 'ONEXA_B4_INTEGRITY_CORRUPTION_DISPOSABLE_ONLY';
  end if;
end $preflight$;

-- The exact-balance CHECK is dropped ONLY inside this transaction to emulate
-- historical imported/corrupted ledger rows that would now be rejected.
alter table public.onexa_journal_headers
  drop constraint onexa_journal_headers_check;

update public.onexa_posting_registry
set source_document_id='BROKEN-SOURCE-MISMATCH'
where source_document_id='INTEGRITY-SEED-purchase_invoice';
-- This also creates a canonical idempotency-key/fields mismatch.

update public.onexa_journal_headers
set total_credit=total_credit+0.004
where source_document_id='INTEGRITY-SEED-payroll_run';

update public.onexa_journal_lines l
set debit=0,credit=0
from public.onexa_journal_headers h
where l.journal_id=h.id and h.source_document_id='INTEGRITY-SEED-payroll_run'
  and l.line_number=1;

update public.onexa_journal_headers
set accounting_date=date '2026-10-31'
where source_document_id='INTEGRITY-SEED-bank_transfer';

insert into public.onexa_journal_headers (
 id,tenant_id,legal_entity_id,journal_number,accounting_date,
 fiscal_period_id,currency,source_document_type,source_document_id,
 source_revision,source_snapshot,memo,state,total_debit,total_credit,posted_by
)
select gen_random_uuid(),h.tenant_id,h.legal_entity_id,
       h.journal_number||'-DUPLICATE',h.accounting_date,
       h.fiscal_period_id,h.currency,h.source_document_type,h.source_document_id,
       h.source_revision,h.source_snapshot,h.memo,h.state,
       h.total_debit,h.total_credit,h.posted_by
from public.onexa_journal_headers h
where h.source_document_id='INTEGRITY-SEED-bank_transfer';

-- Deliberately remove a second line: count and header sum must both fail.
delete from public.onexa_journal_lines l using public.onexa_journal_headers h
where l.journal_id=h.id and h.source_document_id='INTEGRITY-SEED-TENANT-B'
  and l.line_number=2;

update public.onexa_journal_lines l
set tenant_id='tenant-smoke-A'
from public.onexa_journal_headers h
where l.journal_id=h.id and h.source_document_id='INTEGRITY-SEED-TENANT-B'
  and l.line_number=1;

delete from public.onexa_posting_registry
where source_document_id='INTEGRITY-SEED-TENANT-B';

-- A legal journal must never reference a reversal without being marked
-- reversed and linked reciprocally.
update public.onexa_journal_headers
set reversal_journal_id=(
   select r.id from public.onexa_journal_headers r
   where r.source_document_type='journal_reversal'
     and r.tenant_id='tenant-smoke-A'
   limit 1
 )
where source_document_id='INTEGRITY-SEED-purchase_invoice';

-- Simulate source/contra divergence in the one legitimate seeded reversal.
update public.onexa_journal_headers
set source_document_id='BROKEN-REVERSAL-LINK',
    memo='tampered reversal reason',
    total_debit=total_debit+1,total_credit=total_credit+1
where source_document_type='journal_reversal' and tenant_id='tenant-smoke-A';

update public.onexa_journal_lines l
set account_code='9999'
from public.onexa_journal_headers h
where l.journal_id=h.id and h.source_document_type='journal_reversal'
  and h.tenant_id='tenant-smoke-A' and l.line_number=1;

-- Deliberately simulate an orphaned registry entry. Only this disposable
-- transaction drops the synthetic FK; rollback restores it.
alter table public.onexa_posting_registry
  drop constraint onexa_posting_registry_journal_id_fkey;

update public.onexa_posting_registry
set journal_id='11111111-1111-4111-8111-111111111111'::uuid
where source_document_id='INTEGRITY-SEED-customer_receipt';

-- The audit must remain identical to the operator's SELECT-only script.
\i supabase/manual-packages/onexa_b4_ledger_integrity_READ_ONLY.sql

rollback;
