-- Gate 67 read-only postcheck. READY for all objects, true RLS/direct-write denial,
-- invoker views, authenticated-only RPCs, and zero invalid scope/reconciliation rows.
select check_name,status from (values
  ('scope_table',case when to_regclass('public.onexa_lease_accounting_scopes') is not null then 'READY' else 'MISSING' end),
  ('invoice_postings',case when to_regclass('public.onexa_lease_invoice_postings') is not null then 'READY' else 'MISSING' end),
  ('receipt_postings',case when to_regclass('public.onexa_lease_receipt_postings') is not null then 'READY' else 'MISSING' end),
  ('save_scope_rpc',case when to_regprocedure('public.onexa_save_lease_accounting_scope(uuid,uuid)') is not null then 'READY' else 'MISSING' end),
  ('invoice_rpc',case when to_regprocedure('public.onexa_post_lease_invoice(uuid,text)') is not null then 'READY' else 'MISSING' end),
  ('receipt_rpc',case when to_regprocedure('public.onexa_post_lease_receipt(uuid,text)') is not null then 'READY' else 'MISSING' end),
  ('reconciliation_view',case when to_regclass('public.onexa_lease_accounting_reconciliation') is not null then 'READY' else 'MISSING' end),
  ('gate64_guard',case when to_regprocedure('onexa_private.guard_approval_posting()') is not null
    and exists (select 1 from pg_trigger t
      where t.tgname='onexa_guard_approval_posting'
        and t.tgrelid=to_regclass('public.onexa_business_documents')
        and t.tgenabled<>'D' and not t.tgisinternal)
    then 'READY' else 'MISSING' end)
) checks(check_name,status) order by check_name;

select c.relname,c.relrowsecurity as rls_enabled,
  not has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as direct_writes_denied
from pg_class c where c.oid in (
  'public.onexa_lease_accounting_scopes'::regclass,
  'public.onexa_lease_invoice_postings'::regclass,
  'public.onexa_lease_receipt_postings'::regclass
) order by c.relname;

select c.relname,coalesce(c.reloptions @> array['security_invoker=true'],false) as security_invoker
from pg_class c where c.oid in (
  'public.onexa_lease_accounting_scope_details'::regclass,
  'public.onexa_lease_billing_candidates'::regclass,
  'public.onexa_lease_receivables_reconciliation'::regclass,
  'public.onexa_lease_accounting_reconciliation'::regclass,
  'public.onexa_lease_posting_configuration_gaps'::regclass
) order by c.relname;

select has_function_privilege('anon','public.onexa_post_lease_invoice(uuid,text)','EXECUTE') as anon_can_post_invoice,
  has_function_privilege('anon','public.onexa_post_lease_receipt(uuid,text)','EXECUTE') as anon_can_post_receipt,
  has_function_privilege('authenticated','public.onexa_post_lease_invoice(uuid,text)','EXECUTE') as authenticated_can_post_invoice,
  has_function_privilege('authenticated','public.onexa_post_lease_receipt(uuid,text)','EXECUTE') as authenticated_can_post_receipt,
  has_function_privilege('anon','public.onexa_save_lease_accounting_scope(uuid,uuid)','EXECUTE') as anon_can_save_scope;

select tenant_id,legal_entity_id,account_role,'MISSING' as status
from public.onexa_lease_posting_configuration_gaps order by tenant_id,legal_entity_id,account_role;

select scope.id,scope.tenant_id,scope.tenant_lease_id,'INVALID_SCOPE' as status
from public.onexa_lease_accounting_scopes scope
left join public.onexa_branches branch on branch.id=scope.branch_id and branch.tenant_id=scope.tenant_id
left join public.re_tenant_leases lease on lease.id=scope.tenant_lease_id
left join public.re_units unit on unit.id=lease.unit_id
left join public.re_buildings building on building.id=unit.building_id
left join public.re_properties property on property.id=building.property_id
where branch.id is null or branch.legal_entity_id<>scope.legal_entity_id
  or scope.property_id is distinct from property.id;

select tenant_id,document_number,reconciliation_status,gross_total
from public.onexa_lease_accounting_reconciliation
where status='posted' and reconciliation_status<>'reconciled';

select tenant_id,document_number,reconciliation_status,invoiced_amount,collected_amount,outstanding_amount
from public.onexa_lease_receivables_reconciliation
where reconciliation_status<>'reconciled';

-- Posted documents with a reversed/missing GL source or mismatched posting
-- are not reconciled; investigate the original invoice and receipt separately.
select reconciliation_status,count(*) as affected_documents
from public.onexa_lease_accounting_reconciliation
where status='posted'
  and reconciliation_status in
    ('journal_reversed_or_missing','journal_source_or_amount_mismatch','journal_mismatch')
group by reconciliation_status order by reconciliation_status;

select reconciliation_status,count(*) as affected_invoices
from public.onexa_lease_receivables_reconciliation
where reconciliation_status in
    ('invoice_journal_reversed_or_missing','invoice_journal_mismatch','overallocated')
group by reconciliation_status order by reconciliation_status;
