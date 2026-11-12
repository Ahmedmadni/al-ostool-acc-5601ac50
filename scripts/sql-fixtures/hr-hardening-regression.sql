-- LOCAL SYNTHETIC HARNESS ONLY. Requires onexa-hr-synthetic-fixture-v2.sql
-- and the approved HR migrations. Never run against hosted customer data.
begin;
set local request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","app_metadata":{"onexa_tenant_id":"test-a"}}';
set local role authenticated;

-- Rule: a negative leave-day override must reject the entire draft transaction.
do $$
declare before_count bigint; after_count bigint;
begin
  select count(*) into before_count from public.hr_terminations;
  begin
    perform public.hr_termination_create_draft('{"employee_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reason":"end_of_contract","last_working_day":"2025-12-31","leave_days_override":-10}'::jsonb);
    raise exception 'NEGATIVE_LEAVE_OVERRIDE_ACCEPTED';
  exception when sqlstate '22023' then null;
  end;
  select count(*) into after_count from public.hr_terminations;
  if after_count <> before_count then raise exception 'REJECTED_DRAFT_LEFT_ROWS'; end if;
end $$;

-- Rule: clearance must reject an employee belonging to another tenant.
do $$
begin
  begin
    perform public.hr_termination_clearance('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    raise exception 'CROSS_TENANT_CLEARANCE_ACCEPTED';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;