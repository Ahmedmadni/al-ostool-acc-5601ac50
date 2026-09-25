-- Gate 58 end-to-end manual journal smoke test.
-- Requires two distinct active finance users:
--   * one user authorized for create + submit
--   * another user authorized for approve + post
-- The test selects an active legal entity, branch, and two active detail accounts.
-- No data persists because the entire test ends with ROLLBACK.

begin;

do $smoke$
declare
  _tenant constant text := 'tenant-001-al-ostool';
  _candidate uuid;
  _creator uuid;
  _poster uuid;
  _legal_entity uuid;
  _branch uuid;
  _debit_account text;
  _credit_account text;
  _manual_journal uuid;
  _ledger_journal uuid;
  _retry uuid;
  _status text;
begin
  select legal_entity.id, branch.id
  into _legal_entity, _branch
  from public.onexa_legal_entities legal_entity
  join public.onexa_branches branch
    on branch.tenant_id = legal_entity.tenant_id
   and branch.legal_entity_id = legal_entity.id
   and branch.is_active is true
  where legal_entity.tenant_id = _tenant
    and legal_entity.is_active is true
  order by legal_entity.id, branch.id
  limit 1;

  if _legal_entity is null or _branch is null then
    raise exception 'ONEXA_SMOKE_ACTIVE_LEGAL_ENTITY_AND_BRANCH_REQUIRED';
  end if;

  select account.code
  into _debit_account
  from public.chart_of_accounts account
  where account.tenant_id = _tenant
    and account.is_active is true
    and account.account_type::text = 'detail'
  order by account.code
  limit 1;

  select account.code
  into _credit_account
  from public.chart_of_accounts account
  where account.tenant_id = _tenant
    and account.is_active is true
    and account.account_type::text = 'detail'
    and account.code <> _debit_account
  order by account.code
  limit 1;

  if _debit_account is null or _credit_account is null then
    raise exception 'ONEXA_SMOKE_TWO_ACTIVE_DETAIL_ACCOUNTS_REQUIRED';
  end if;

  for _candidate in
    select distinct membership.user_id
    from public.onexa_workspace_memberships membership
    where membership.tenant_id = _tenant
      and membership.status = 'active'
      and membership.role_key in (
        'workspace_owner',
        'finance_manager',
        'accountant'
      )
    order by membership.user_id
  loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', _candidate,
        'role', 'authenticated',
        'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
      )::text,
      true
    );

    if onexa_private.has_module_action(_candidate, 'finance', 'create')
       and onexa_private.has_module_action(_candidate, 'finance', 'submit') then
      _creator := _candidate;
      exit;
    end if;
  end loop;

  if _creator is null then
    raise exception 'ONEXA_SMOKE_AUTHORIZED_MANUAL_JOURNAL_CREATOR_REQUIRED';
  end if;

  for _candidate in
    select distinct membership.user_id
    from public.onexa_workspace_memberships membership
    where membership.tenant_id = _tenant
      and membership.status = 'active'
      and membership.role_key in (
        'workspace_owner',
        'finance_manager',
        'accountant'
      )
      and membership.user_id <> _creator
    order by membership.user_id
  loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', _candidate,
        'role', 'authenticated',
        'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
      )::text,
      true
    );

    if onexa_private.has_module_action(_candidate, 'finance', 'approve')
       and onexa_private.has_module_action(_candidate, 'finance', 'post') then
      _poster := _candidate;
      exit;
    end if;
  end loop;

  if _poster is null then
    raise exception 'ONEXA_SMOKE_DISTINCT_AUTHORIZED_APPROVER_AND_POSTER_REQUIRED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _creator,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
    )::text,
    true
  );

  _manual_journal := public.onexa_create_manual_journal(
    _legal_entity_id => _legal_entity,
    _branch_id => _branch,
    _accounting_date => current_date,
    _period_code => to_char(current_date, 'YYYY-MM'),
    _currency => 'SAR',
    _memo => 'Gate 58 end-to-end rollback smoke test',
    _external_reference => 'G58-SMOKE-' || gen_random_uuid()::text,
    _lines => jsonb_build_array(
      jsonb_build_object(
        'line_number', 1,
        'account_code', _debit_account,
        'debit', 1.00,
        'credit', 0,
        'description', 'Gate 58 smoke debit',
        'dimensions', '{}'::jsonb
      ),
      jsonb_build_object(
        'line_number', 2,
        'account_code', _credit_account,
        'debit', 0,
        'credit', 1.00,
        'description', 'Gate 58 smoke credit',
        'dimensions', '{}'::jsonb
      )
    )
  );

  if _manual_journal is null then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_CREATE_FAILED';
  end if;

  _status := public.onexa_transition_manual_journal(
    _journal_id => _manual_journal,
    _to_status => 'submitted',
    _reason => null
  );

  if _status <> 'submitted'
     or not exists (
       select 1
       from public.onexa_manual_journals journal
       where journal.id = _manual_journal
         and journal.tenant_id = _tenant
         and journal.status = 'submitted'
         and journal.created_by = _creator
         and journal.submitted_by = _creator
     ) then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_SUBMIT_FAILED';
  end if;

  begin
    perform public.onexa_transition_manual_journal(
      _journal_id => _manual_journal,
      _to_status => 'approved',
      _reason => null
    );
    raise exception 'ONEXA_SMOKE_CREATOR_APPROVAL_ALLOWED';
  exception
    when others then
      if sqlerrm <> 'ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_APPROVE' then
        raise;
      end if;
  end;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _poster,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('onexa_tenant_id', _tenant)
    )::text,
    true
  );

  _status := public.onexa_transition_manual_journal(
    _journal_id => _manual_journal,
    _to_status => 'approved',
    _reason => null
  );

  if _status <> 'approved'
     or not exists (
       select 1
       from public.onexa_manual_journals journal
       where journal.id = _manual_journal
         and journal.tenant_id = _tenant
         and journal.status = 'approved'
         and journal.approved_by = _poster
         and journal.created_by <> journal.approved_by
     ) then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_APPROVAL_FAILED';
  end if;

  _ledger_journal := public.onexa_post_manual_journal(_manual_journal);

  if _ledger_journal is null
     or not exists (
       select 1
       from public.onexa_manual_journals journal
       where journal.id = _manual_journal
         and journal.tenant_id = _tenant
         and journal.status = 'posted'
         and journal.posted_journal_id = _ledger_journal
         and journal.posted_by = _poster
     )
     or not exists (
       select 1
       from public.onexa_manual_journal_reconciliation reconciliation
       where reconciliation.manual_journal_id = _manual_journal
         and reconciliation.reconciliation_status = 'reconciled'
     ) then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_RECONCILIATION_FAILED';
  end if;

  _retry := public.onexa_post_manual_journal(_manual_journal);

  if _retry is distinct from _ledger_journal then
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_RETRY_FAILED';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', _poster,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object(
        'onexa_tenant_id',
        'tenant-smoke-other'
      )
    )::text,
    true
  );

  begin
    perform public.onexa_post_manual_journal(_manual_journal);
    raise exception 'ONEXA_SMOKE_MANUAL_JOURNAL_CROSS_TENANT_ALLOWED';
  exception
    when others then
      if sqlerrm not in (
        'ONEXA_MANUAL_JOURNAL_POST_NOT_AUTHORIZED',
        'ONEXA_MANUAL_JOURNAL_NOT_FOUND'
      ) then
        raise;
      end if;
  end;

  raise notice
    'gate58_manual_journal_smoke_test | passed | manual_journal=% | ledger_journal=% | rollback follows',
    _manual_journal,
    _ledger_journal;
end;
$smoke$;

rollback;
