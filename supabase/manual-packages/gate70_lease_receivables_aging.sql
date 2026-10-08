-- Gate 70. Manual rollout after Gate 69; this report only reads posted native lease documents.
begin;

do $preflight$
begin
  if to_regprocedure('public.onexa_lease_property_financial_report(uuid,date,date)') is null
    or to_regclass('public.onexa_lease_invoice_postings') is null
    or to_regclass('public.onexa_lease_receipt_postings') is null then
    raise exception 'ONEXA_GATE69_LEASE_PROPERTY_REPORT_REQUIRED';
  end if;
end $preflight$;

create or replace function public.onexa_lease_receivables_aging(_property_id uuid,_as_of date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare _tenant text:=onexa_private.claim_tenant_id(); _company uuid:=public.re_company_id();
  _result jsonb;
begin
  if auth.uid() is null or nullif(_tenant,'') is null
    or not onexa_private.has_module_action(auth.uid(),'facilities','read')
    or _company is null or not public.re_has_company_access(_company) then
    raise exception 'ONEXA_LEASE_AGING_NOT_AUTHORIZED';
  end if;
  if _property_id is null or _as_of is null then raise exception 'ONEXA_LEASE_AGING_INPUT_REQUIRED'; end if;
  if not exists (select 1 from public.re_properties p where p.id=_property_id and p.company_id=_company)
    or not exists (select 1 from public.onexa_lease_accounting_scopes s
      where s.property_id=_property_id and s.tenant_id=_tenant) then
    raise exception 'ONEXA_LEASE_AGING_PROPERTY_NOT_ACCESSIBLE';
  end if;

  with invoice_balances as (
    select p.document_id,p.customer_id,p.legal_entity_id,
      coalesce(nullif(btrim(d.party_name_snapshot),''),p.customer_id::text) as customer_name,
      coalesce(d.due_date,schedule.due_date) as due_date,
      greatest(p.gross_amount-coalesce(allocation.collected,0),0) as outstanding
    from public.onexa_lease_invoice_postings p
    join public.onexa_lease_accounting_scopes scope on scope.id=p.scope_id
      and scope.tenant_id=_tenant and scope.property_id=_property_id
      and scope.legal_entity_id=p.legal_entity_id
    join public.re_lease_schedules schedule on schedule.id=p.schedule_id
      and schedule.tenant_lease_id=scope.tenant_lease_id
    join public.onexa_business_documents d on d.id=p.document_id and d.tenant_id=_tenant
      and d.legal_entity_id=p.legal_entity_id and d.document_type='lease_invoice'
      and d.status='posted' and d.posted_journal_id=p.journal_id
    left join lateral (
      select sum(r.amount) as collected
      from public.onexa_lease_receipt_postings r
      join public.onexa_business_documents receipt on receipt.id=r.document_id
        and receipt.tenant_id=_tenant and receipt.legal_entity_id=p.legal_entity_id
        and receipt.document_type='lease_receipt' and receipt.status='posted'
        and receipt.posted_journal_id=r.journal_id and receipt.accounting_date<=_as_of
      where r.tenant_id=_tenant and r.invoice_id=p.document_id
        and r.legal_entity_id=p.legal_entity_id and r.property_id=_property_id
    ) allocation on true
    where p.tenant_id=_tenant and p.property_id=_property_id and d.accounting_date<=_as_of
  ), open_invoices as (
    select * from invoice_balances where outstanding>0
  ), customers as (
    select i.customer_id,i.legal_entity_id,e.code::text as legal_entity_code,
      max(i.customer_name) as customer_name,count(*) as invoice_count,min(i.due_date) as oldest_due_date,
      round(sum(i.outstanding),2) as outstanding,
      round(sum(i.outstanding) filter (where i.due_date>=_as_of),2) as current_amount,
      round(sum(i.outstanding) filter (where i.due_date<_as_of and i.due_date>=_as_of-30),2) as days_1_30,
      round(sum(i.outstanding) filter (where i.due_date<_as_of-30 and i.due_date>=_as_of-60),2) as days_31_60,
      round(sum(i.outstanding) filter (where i.due_date<_as_of-60 and i.due_date>=_as_of-90),2) as days_61_90,
      round(sum(i.outstanding) filter (where i.due_date<_as_of-90),2) as days_over_90
    from open_invoices i
    join public.onexa_legal_entities e on e.id=i.legal_entity_id and e.tenant_id=_tenant
    group by i.customer_id,i.legal_entity_id,e.code
  ), ranked as (
    select *,coalesce(days_1_30,0)+coalesce(days_31_60,0)+coalesce(days_61_90,0)+coalesce(days_over_90,0) as overdue
    from customers
  )
  select jsonb_build_object(
    'property_id',_property_id,'as_of',_as_of,
    'invoice_count',(select count(*) from open_invoices),
    'customer_count',(select count(*) from ranked),
    'outstanding',coalesce((select round(sum(outstanding),2) from ranked),0),
    'current_amount',coalesce((select sum(current_amount) from ranked),0),
    'days_1_30',coalesce((select sum(days_1_30) from ranked),0),
    'days_31_60',coalesce((select sum(days_31_60) from ranked),0),
    'days_61_90',coalesce((select sum(days_61_90) from ranked),0),
    'days_over_90',coalesce((select sum(days_over_90) from ranked),0),
    'top_customers',coalesce((select jsonb_agg(to_jsonb(top_rows)) from (
      select customer_id,legal_entity_id,legal_entity_code,customer_name,invoice_count,oldest_due_date,
        outstanding,coalesce(current_amount,0) as current_amount,overdue
      from ranked order by overdue desc,outstanding desc,customer_name,customer_id limit 25
    ) top_rows),'[]'::jsonb)
  ) into _result;
  return _result;
end;
$$;

revoke all on function public.onexa_lease_receivables_aging(uuid,date) from public,anon;
grant execute on function public.onexa_lease_receivables_aging(uuid,date) to authenticated,service_role;
commit;
