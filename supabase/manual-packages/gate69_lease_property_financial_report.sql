-- Gate 69. Manual rollout after Gates 67 and 68; no historical financial rows are changed.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_lease_invoice_postings') is null
    or to_regclass('public.onexa_lease_receipt_postings') is null
    or to_regclass('public.onexa_lease_accounting_scopes') is null
    or to_regclass('public.onexa_journal_headers') is null
    or to_regprocedure('public.onexa_lease_portfolio_snapshot()') is null then
    raise exception 'ONEXA_GATE68_LEASE_RECONCILIATION_REQUIRED';
  end if;
end $preflight$;

-- Separate accounting-date activity from the balance as of _to. Revenues are net
-- of VAT; receipts and outstanding amounts are gross. No scheduled rent is counted.
create or replace function public.onexa_lease_property_financial_report(
  _property_id uuid,_from date,_to date
)
returns table(
  legal_entity_id uuid,legal_entity_code text,invoice_count bigint,
  invoiced_net numeric,invoiced_tax numeric,invoiced_gross numeric,
  collected_gross numeric,outstanding_as_of numeric
)
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare _tenant text:=onexa_private.claim_tenant_id(); _company uuid:=public.re_company_id();
begin
  if auth.uid() is null or nullif(_tenant,'') is null
    or not onexa_private.has_module_action(auth.uid(),'facilities','read')
    or _company is null or not public.re_has_company_access(_company) then
    raise exception 'ONEXA_LEASE_REPORT_NOT_AUTHORIZED';
  end if;
  if _property_id is null or _from is null or _to is null or _from>_to then
    raise exception 'ONEXA_LEASE_REPORT_PERIOD_INVALID';
  end if;
  if not exists (select 1 from public.re_properties p where p.id=_property_id and p.company_id=_company)
    or not exists (select 1 from public.onexa_lease_accounting_scopes scope
      where scope.property_id=_property_id and scope.tenant_id=_tenant) then
    raise exception 'ONEXA_LEASE_REPORT_PROPERTY_NOT_ACCESSIBLE';
  end if;

  return query
  with invoices as (
    select p.document_id,p.legal_entity_id,p.customer_id,p.net_amount,p.tax_amount,p.gross_amount,d.accounting_date
    from public.onexa_lease_invoice_postings p
    join public.onexa_lease_accounting_scopes scope on scope.id=p.scope_id
      and scope.tenant_id=_tenant and scope.property_id=_property_id
      and scope.legal_entity_id=p.legal_entity_id
    join public.onexa_business_documents d on d.id=p.document_id and d.tenant_id=_tenant
      and d.legal_entity_id=p.legal_entity_id and d.status='posted'
      and d.document_type='lease_invoice' and d.posted_journal_id=p.journal_id
      and d.party_id=p.customer_id
    join public.onexa_journal_headers invoice_journal
      on invoice_journal.id=p.journal_id and invoice_journal.tenant_id=p.tenant_id
      and invoice_journal.legal_entity_id=p.legal_entity_id
      and invoice_journal.source_document_type='lease_invoice'
      and invoice_journal.source_document_id=p.document_id::text
      and invoice_journal.currency=d.currency
      and invoice_journal.total_debit=p.gross_amount
      and invoice_journal.total_credit=p.gross_amount
    left join public.onexa_journal_headers invoice_reversal
      on invoice_reversal.id=invoice_journal.reversal_journal_id
     and invoice_reversal.tenant_id=invoice_journal.tenant_id
     and invoice_reversal.legal_entity_id=invoice_journal.legal_entity_id
     and invoice_reversal.state='posted'
     and invoice_reversal.reversal_of_id=invoice_journal.id
    where p.tenant_id=_tenant and p.property_id=_property_id
      and (invoice_journal.state='posted' and invoice_journal.reversal_journal_id is null
        or invoice_journal.state='reversed'
          and invoice_reversal.accounting_date>_to)
  ), receipts as (
    select r.invoice_id,r.legal_entity_id,r.amount,d.accounting_date
    from public.onexa_lease_receipt_postings r
    join invoices i on i.document_id=r.invoice_id and i.legal_entity_id=r.legal_entity_id
      and i.customer_id=r.customer_id
    join public.onexa_business_documents d on d.id=r.document_id and d.tenant_id=_tenant
      and d.legal_entity_id=r.legal_entity_id and d.status='posted'
      and d.document_type='lease_receipt' and d.posted_journal_id=r.journal_id
      and d.party_id=r.customer_id
    join public.onexa_journal_headers receipt_journal
      on receipt_journal.id=r.journal_id and receipt_journal.tenant_id=r.tenant_id
     and receipt_journal.legal_entity_id=r.legal_entity_id
     and receipt_journal.source_document_type='lease_receipt'
     and receipt_journal.source_document_id=r.document_id::text
     and receipt_journal.currency=d.currency
     and receipt_journal.total_debit=r.amount
     and receipt_journal.total_credit=r.amount
    left join public.onexa_journal_headers receipt_reversal
      on receipt_reversal.id=receipt_journal.reversal_journal_id
     and receipt_reversal.tenant_id=receipt_journal.tenant_id
     and receipt_reversal.legal_entity_id=receipt_journal.legal_entity_id
     and receipt_reversal.state='posted'
     and receipt_reversal.reversal_of_id=receipt_journal.id
    where r.tenant_id=_tenant and r.property_id=_property_id
      and (receipt_journal.state='posted' and receipt_journal.reversal_journal_id is null
        or receipt_journal.state='reversed'
          and receipt_reversal.accounting_date>_to)
  ), invoice_period as (
    select i.legal_entity_id,count(*) as invoice_count,sum(i.net_amount) as net,
      sum(i.tax_amount) as tax,sum(i.gross_amount) as gross
    from invoices i where i.accounting_date between _from and _to group by i.legal_entity_id
  ), receipt_period as (
    select r.legal_entity_id,sum(r.amount) as collected
    from receipts r where r.accounting_date between _from and _to group by r.legal_entity_id
  ), balance as (
    select i.legal_entity_id,
      sum(greatest(i.gross_amount-coalesce(alloc.collected,0),0)) as outstanding
    from invoices i
    left join lateral (
      select sum(r.amount) as collected from receipts r
      where r.invoice_id=i.document_id and r.accounting_date<=_to
    ) alloc on true
    where i.accounting_date<=_to group by i.legal_entity_id
  ), entities as (
    select legal_entity_id from invoice_period
    union select legal_entity_id from receipt_period
    union select legal_entity_id from balance
  )
  select e.id,e.code::text,coalesce(ip.invoice_count,0),
    round(coalesce(ip.net,0),2),round(coalesce(ip.tax,0),2),round(coalesce(ip.gross,0),2),
    round(coalesce(rp.collected,0),2),round(coalesce(b.outstanding,0),2)
  from entities selected
  join public.onexa_legal_entities e on e.id=selected.legal_entity_id and e.tenant_id=_tenant
  left join invoice_period ip on ip.legal_entity_id=e.id
  left join receipt_period rp on rp.legal_entity_id=e.id
  left join balance b on b.legal_entity_id=e.id
  order by e.code;
end;
$$;

revoke all on function public.onexa_lease_property_financial_report(uuid,date,date) from public,anon;
grant execute on function public.onexa_lease_property_financial_report(uuid,date,date) to authenticated,service_role;
commit;
