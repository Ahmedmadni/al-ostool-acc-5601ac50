-- Gate 68. Run manually after Gate 67 and its postcheck; leave the UI switch off until verified.
begin;

do $preflight$
begin
  if to_regclass('public.onexa_lease_invoice_postings') is null
    or to_regclass('public.onexa_lease_receipt_postings') is null
    or to_regclass('public.onexa_lease_accounting_scopes') is null
    or to_regprocedure('public.re_portfolio_snapshot()') is null then
    raise exception 'ONEXA_GATE67_LEASE_ACCOUNTING_REQUIRED';
  end if;
end $preflight$;

-- Native posting owns the schedule after the invoice is posted. This also blocks
-- re_link_schedule_invoice, re_mark_schedule_paid and re_waive_schedule on it.
create or replace function public.onexa_guard_posted_lease_schedule()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if exists (select 1 from public.onexa_lease_invoice_postings p where p.schedule_id=old.id) then
    if tg_op='DELETE' then raise exception 'ONEXA_POSTED_LEASE_SCHEDULE_IMMUTABLE'; end if;
    if row(new.tenant_lease_id,new.due_date,new.period_start,new.period_end,new.amount,
           new.status,new.invoice_id,new.paid_at)
       is distinct from
       row(old.tenant_lease_id,old.due_date,old.period_start,old.period_end,old.amount,
           old.status,old.invoice_id,old.paid_at) then
      raise exception 'ONEXA_POSTED_LEASE_SCHEDULE_IMMUTABLE';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists onexa_guard_posted_lease_schedule on public.re_lease_schedules;
create trigger onexa_guard_posted_lease_schedule before update or delete
on public.re_lease_schedules for each row execute function public.onexa_guard_posted_lease_schedule();

-- Scoped native leases are read for the active tenant; legacy unscoped schedules
-- retain Gate 15 behavior. A scoped lease of another tenant never enters the result.
create or replace function public.onexa_lease_schedule_dashboard()
returns table(id uuid,due_date date,amount numeric,status text)
language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare _tenant text:=onexa_private.claim_tenant_id(); _company uuid:=public.re_company_id();
begin
  if auth.uid() is null or nullif(_tenant,'') is null
    or not onexa_private.has_module_action(auth.uid(),'facilities','read')
    or _company is null or not public.re_has_company_access(_company) then
    raise exception 'ONEXA_LEASE_DASHBOARD_NOT_AUTHORIZED';
  end if;
  return query
  select s.id,s.due_date,
    (case when p.document_id is not null then greatest(p.gross_amount-coalesce(r.collected,0),0)
          else s.amount end)::numeric as amount,
    (case when p.document_id is not null then
            case when coalesce(r.collected,0)>=p.gross_amount then 'paid'
                 when coalesce(r.collected,0)>0 then 'partially_paid'
                 else 'invoiced' end
          else s.status end)::text as status
  from public.re_lease_schedules s
  join public.re_tenant_leases l on l.id=s.tenant_lease_id and l.company_id=_company
  left join public.onexa_lease_accounting_scopes scope on scope.tenant_lease_id=l.id
  left join public.onexa_lease_invoice_postings p on p.schedule_id=s.id
    and p.tenant_id=_tenant and p.scope_id=scope.id
  left join lateral (
    select coalesce(sum(receipt.amount),0) as collected
    from public.onexa_lease_receipt_postings receipt
    where receipt.invoice_id=p.document_id and receipt.tenant_id=_tenant
  ) r on p.document_id is not null
  where s.due_date>=current_date and (scope.id is null or scope.tenant_id=_tenant)
    and (case when p.document_id is not null then p.gross_amount>coalesce(r.collected,0)
              else s.status in ('pending','invoiced') end)
  order by s.due_date,s.id limit 12;
end;
$$;

create or replace function public.onexa_lease_portfolio_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare _tenant text:=onexa_private.claim_tenant_id(); _company uuid:=public.re_company_id();
  _snapshot jsonb; _outstanding numeric;
begin
  if auth.uid() is null or nullif(_tenant,'') is null
    or not onexa_private.has_module_action(auth.uid(),'facilities','read')
    or _company is null or not public.re_has_company_access(_company) then
    raise exception 'ONEXA_LEASE_DASHBOARD_NOT_AUTHORIZED';
  end if;
  _snapshot:=public.re_portfolio_snapshot();
  select coalesce(sum(case when p.document_id is not null
                        then greatest(p.gross_amount-coalesce(r.collected,0),0)
                        when s.status in ('pending','invoiced') then s.amount else 0 end),0)
    into _outstanding
  from public.re_lease_schedules s
  join public.re_tenant_leases l on l.id=s.tenant_lease_id and l.company_id=_company
  left join public.onexa_lease_accounting_scopes scope on scope.tenant_lease_id=l.id
  left join public.onexa_lease_invoice_postings p on p.schedule_id=s.id
    and p.tenant_id=_tenant and p.scope_id=scope.id
  left join lateral (
    select coalesce(sum(receipt.amount),0) as collected
    from public.onexa_lease_receipt_postings receipt
    where receipt.invoice_id=p.document_id and receipt.tenant_id=_tenant
  ) r on p.document_id is not null
  where s.due_date<=current_date+90 and (scope.id is null or scope.tenant_id=_tenant);
  return jsonb_set(_snapshot,'{receivables_90_days}',to_jsonb(round(_outstanding,2)),true);
end;
$$;

revoke all on function public.onexa_guard_posted_lease_schedule(),
  public.onexa_lease_schedule_dashboard(),public.onexa_lease_portfolio_snapshot() from public,anon;
grant execute on function public.onexa_lease_schedule_dashboard(),
  public.onexa_lease_portfolio_snapshot() to authenticated,service_role;
commit;
