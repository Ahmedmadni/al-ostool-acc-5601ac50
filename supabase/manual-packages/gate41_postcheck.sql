-- Gate 41 read-only postcheck. All booleans must be true, no mismatches.
select 'treasury_accounts' as object_name,
  to_regclass('public.onexa_treasury_accounts') is not null as ready
union all select 'transfer_postings',
  to_regclass('public.onexa_bank_transfer_postings') is not null
union all select 'posting_rpc',
  to_regprocedure('public.onexa_post_bank_transfer(uuid,text)') is not null;

select c.relname, c.relrowsecurity as rls_enabled,
  not has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE') as direct_writes_denied
from pg_class c where c.oid in (
  'public.onexa_treasury_accounts'::regclass,
  'public.onexa_bank_transfer_postings'::regclass
);
select coalesce(c.reloptions @> array['security_invoker=true'], false) as security_invoker
from pg_class c where c.oid = 'public.onexa_bank_transfer_reconciliation'::regclass;
select has_function_privilege('anon', 'public.onexa_post_bank_transfer(uuid,text)', 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', 'public.onexa_post_bank_transfer(uuid,text)', 'EXECUTE') as authenticated_can_execute;

select account.tenant_id, account.legal_entity_id, account.branch_id,
  account.account_code, account.display_name,
  (gl.code is not null and gl.is_active and gl.account_type::text = 'detail'
   and gl.category::text = 'assets') as valid_gl_account
from public.onexa_treasury_accounts account
left join public.chart_of_accounts gl
  on gl.tenant_id = account.tenant_id and gl.code = account.account_code
order by account.tenant_id, account.legal_entity_id, account.account_code;

-- Include missing/reversed B4 journals and legal-entity / branch mismatches in
-- the existing fail-closed reconciliation result rather than reporting a false OK.
-- A reversed journal is expected historical evidence, not an active GL transfer.
select tenant_id, document_number, reconciliation_status, transfer_amount, posted_amount
from public.onexa_bank_transfer_reconciliation
where status = 'posted' and reconciliation_status <> 'reconciled';

-- Explicit breakdown to distinguish a control failure from a historical reversal.
select reconciliation_status, count(*) as document_count
from public.onexa_bank_transfer_reconciliation
where status = 'posted'
  and reconciliation_status in ('journal_reversed_or_missing','account_scope_mismatch','journal_mismatch','amount_mismatch')
group by reconciliation_status order by reconciliation_status;
