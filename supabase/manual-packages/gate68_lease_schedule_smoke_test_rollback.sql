-- Required rollback-only acceptance test. A posted native lease invoice is mandatory.
begin;
do $smoke$
declare _schedule uuid; _blocked boolean:=false;
begin
  select schedule_id into _schedule from public.onexa_lease_invoice_postings order by posted_at limit 1;
  if _schedule is null then
    raise exception 'ONEXA_GATE68_POSTED_LEASE_INVOICE_REQUIRED';
  end if;
  begin
    update public.re_lease_schedules set amount=amount+1 where id=_schedule;
  exception when others then
    if sqlerrm='ONEXA_POSTED_LEASE_SCHEDULE_IMMUTABLE' then
      _blocked:=true;
    else
      raise;
    end if;
  end;
  if not _blocked then raise exception 'ONEXA_GATE68_SCHEDULE_GUARD_FAILED'; end if;
  raise notice 'gate68_lease_schedule_smoke_test | passed | posted schedule mutation blocked';
end $smoke$;
rollback;
