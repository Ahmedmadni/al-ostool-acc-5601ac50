-- ONEXA Gate 58 — reviewer/creator separation and reversal-date guard.
-- REVIEW ONLY, never installed automatically. The observed live definition MD5s
-- below came from SELECT-only pg_catalog inspection on 2026-11-18.
-- Separate Staging, verified restore and security/finance change approval required.
-- STOP rather than bypass either guard if hosted SQL has drifted.
begin;

do $gate58_preflight$
declare
  _transition regprocedure := to_regprocedure(
    'public.onexa_transition_manual_journal(uuid,text,text)'
  );
  _reverse regprocedure := to_regprocedure(
    'public.onexa_reverse_manual_journal(uuid,date,text,text)'
  );
begin
  if _transition is null or _reverse is null then
    raise exception 'ONEXA_GATE58_LIFECYCLE_RPC_MISSING';
  end if;
  if md5(pg_get_functiondef(_transition::oid)) <> '6be0100c16f4594132af3ac119afdc3a' then
    raise exception 'ONEXA_GATE58_TRANSITION_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
  if md5(pg_get_functiondef(_reverse::oid)) <> '0b72dab37dd9057dde187102cfe2dce7' then
    raise exception 'ONEXA_GATE58_REVERSAL_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
end;
$gate58_preflight$;

create or replace function public.onexa_transition_manual_journal(
  _journal_id uuid,
  _to_status text,
  _reason text default null
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _allowed boolean := false;
  _action text;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;

  select * into _journal from public.onexa_manual_journals
  where id = _journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;

  _allowed := (_journal.status = 'draft' and _to_status in ('submitted','cancelled'))
    or (_journal.status = 'submitted' and _to_status in ('approved','rejected','cancelled'))
    or (_journal.status = 'rejected' and _to_status in ('draft','cancelled'));
  if not _allowed then
    raise exception 'ONEXA_MANUAL_JOURNAL_TRANSITION_INVALID:%->%', _journal.status, _to_status;
  end if;

  -- Rejection is a reviewer decision, not a creator's general edit action.
  _action := case when _to_status in ('approved','rejected') then 'approve'
                  when _to_status = 'submitted' then 'submit'
                  else 'create' end;
  if not onexa_private.has_module_action(_actor, 'finance', _action) then
    raise exception 'ONEXA_MANUAL_JOURNAL_TRANSITION_NOT_AUTHORIZED:%', _action;
  end if;

  if _to_status in ('submitted','draft') and _actor <> _journal.created_by then
    raise exception 'ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_SUBMIT';
  end if;
  if _to_status = 'approved' and _actor = _journal.created_by then
    raise exception 'ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_APPROVE';
  end if;
  if _to_status = 'rejected' and _actor = _journal.created_by then
    raise exception 'ONEXA_MANUAL_JOURNAL_CREATOR_CANNOT_REJECT';
  end if;
  if _to_status = 'cancelled' and _actor <> _journal.created_by then
    raise exception 'ONEXA_ONLY_MANUAL_JOURNAL_CREATOR_CAN_CANCEL';
  end if;
  if _to_status = 'rejected' and nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_REJECTION_REASON_REQUIRED';
  end if;
  if _to_status = 'cancelled' and _journal.status = 'submitted'
     and nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_CANCELLATION_REASON_REQUIRED';
  end if;

  update public.onexa_manual_journals
  set status = _to_status,
      submitted_by = case when _to_status = 'submitted' then _actor else submitted_by end,
      submitted_at = case when _to_status = 'submitted' then now() else submitted_at end,
      approved_by = case when _to_status = 'approved' then _actor else approved_by end,
      approved_at = case when _to_status = 'approved' then now() else approved_at end,
      rejected_by = case when _to_status = 'rejected' then _actor else rejected_by end,
      rejected_at = case when _to_status = 'rejected' then now() else rejected_at end,
      cancelled_by = case when _to_status = 'cancelled' then _actor else cancelled_by end,
      cancelled_at = case when _to_status = 'cancelled' then now() else cancelled_at end,
      updated_at = now()
  where id = _journal_id and tenant_id = _tenant_id;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, from_status, to_status, actor_id, reason
  ) values (
    _tenant_id, _journal_id, 'status_changed', _journal.status, _to_status,
    _actor, nullif(btrim(_reason), '')
  );

  return _to_status;
end;
$function$;

create or replace function public.onexa_reverse_manual_journal(
  _manual_journal_id uuid,
  _accounting_date date,
  _period_code text,
  _reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _reversal_id uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'reverse') then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVERSE_NOT_AUTHORIZED';
  end if;
  if nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_REVERSAL_REASON_REQUIRED';
  end if;
  -- The B4 engine must additionally enforce closed/frozen fiscal periods.
  if _accounting_date is null or _period_code is null
     or _period_code !~ '^[0-9]{4}-(0[1-9]|1[0-2])

  select * into _journal from public.onexa_manual_journals
  where id = _manual_journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;
  if _journal.status = 'reversed' and _journal.reversal_journal_id is not null then
    return _journal.reversal_journal_id;
  end if;
  if _journal.status <> 'posted' or _journal.posted_journal_id is null then
    raise exception 'ONEXA_MANUAL_JOURNAL_MUST_BE_POSTED';
  end if;

  _reversal_id := public.onexa_reverse_journal(
    _journal_id => _journal.posted_journal_id,
    _accounting_date => _accounting_date,
    _period_code => _period_code,
    _reason => btrim(_reason)
  )::uuid;

  update public.onexa_manual_journals
  set status = 'reversed', reversal_journal_id = _reversal_id,
      reversed_by = _actor, reversed_at = now(), updated_at = now()
  where id = _journal.id and tenant_id = _tenant_id;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, from_status, to_status, actor_id, reason, event_data
  ) values (
    _tenant_id, _journal.id, 'reversal_completed', 'posted', 'reversed', _actor,
    btrim(_reason), jsonb_build_object('reversal_journal_id', _reversal_id)
  );

  return _reversal_id;
end;
$function$;

-- Existing grants, RLS policies and journal data are unchanged by these
-- CREATE OR REPLACE FUNCTION statements. Requires full staged postchecks.
commit;
