-- Optional rollback-only test after a native lease invoice has been posted.
begin;
do $smoke$
declare _schedule uuid; _blocked boolean:=false;
begin
  select schedule_id into _schedule from public.onexa_lease_invoice_postings order by posted_at limit 1;
  if _schedule is null then
    raise notice 'No native lease invoice exists yet; immutability test deferred';
    return;
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
  raise notice 'Posted schedule mutation blocked';
end $smoke$;
rollback;
