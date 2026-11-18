-- Gate58 B4 post-result integrity upgrade — REVIEW ONLY.
-- NO auto deploy. Checks exact installed function fingerprint recorded via
-- read-only ONEXA catalog on 2026-11-18; abort on drift.
-- Staging + independently tested restore + finance/security approval required.
begin;
do $preflight$
declare _old regprocedure := to_regprocedure('public.onexa_post_manual_journal(uuid)');
begin
  if _old is null or to_regclass('public.onexa_journal_headers') is null then
    raise exception 'ONEXA_GATE58_B4_POST_DEPENDENCY_MISSING_STOP';
  end if;
  if md5(pg_get_functiondef(_old::oid)) <> '83e16f9b40853942437b253dfb5651b9' then
    raise exception 'ONEXA_GATE58_B4_POST_RPC_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
end $preflight$;

create or replace function public.onexa_post_manual_journal(_journal_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  _tenant_id text := onexa_private.claim_tenant_id();
  _actor uuid := auth.uid();
  _journal public.onexa_manual_journals%rowtype;
  _lines jsonb;
  _journal_id_result uuid;
begin
  if _actor is null or nullif(_tenant_id, '') is null then
    raise exception 'ONEXA_AUTHENTICATED_TENANT_REQUIRED';
  end if;
  if not onexa_private.has_module_action(_actor, 'finance', 'post') then
    raise exception 'ONEXA_MANUAL_JOURNAL_POST_NOT_AUTHORIZED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(_tenant_id || ':manual-journal:' || _journal_id::text, 0));

  select * into _journal from public.onexa_manual_journals
  where id = _journal_id and tenant_id = _tenant_id
  for update;
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_NOT_FOUND'; end if;
  if _journal.status = 'posted' and _journal.posted_journal_id is not null then
    return _journal.posted_journal_id;
  end if;
  if _journal.status <> 'approved' then
    raise exception 'ONEXA_MANUAL_JOURNAL_MUST_BE_APPROVED';
  end if;
  if _actor = _journal.created_by then
    raise exception 'ONEXA_MANUAL_JOURNAL_POSTER_MUST_DIFFER_FROM_CREATOR';
  end if;

  select jsonb_agg(jsonb_build_object(
    'account_code', line.account_code,
    'debit', line.debit,
    'credit', line.credit,
    'description', line.description,
    'dimensions', line.dimensions || jsonb_build_object(
      'legalEntity', _journal.legal_entity_id,
      'branch', _journal.branch_id
    )
  ) order by line.line_number)
  into _lines
  from public.onexa_manual_journal_lines line
  where line.manual_journal_id = _journal.id and line.tenant_id = _tenant_id;

  if _lines is null or jsonb_array_length(_lines) < 2 then
    raise exception 'ONEXA_MANUAL_JOURNAL_REQUIRES_TWO_LINES';
  end if;

  _journal_id_result := public.onexa_post_journal(
    _legal_entity_id => _journal.legal_entity_id,
    _source_document_type => 'manual_journal',
    _source_document_id => _journal.id::text,
    _source_revision => _journal.revision,
    _source_status => 'approved',
    _source_snapshot => jsonb_build_object(
      'manual_journal_number', _journal.journal_number,
      'external_reference', _journal.external_reference,
      'approved_by', _journal.approved_by,
      'posting_contract_version', 'manual-journal-v1'
    ),
    _accounting_date => _journal.accounting_date,
    _period_code => _journal.period_code,
    _currency => _journal.currency,
    _memo => _journal.memo,
    _lines => _lines
  )::uuid;

  if _journal_id_result is null then raise exception 'ONEXA_POST_JOURNAL_INVALID_RESPONSE'; end if;

  -- Treat the B4 result as an untrusted downstream contract. A UUID alone
  -- does not prove that the exact approved source reached this tenant's GL.
  perform 1 from public.onexa_journal_headers posted
  where posted.id = _journal_id_result
    and posted.tenant_id = _tenant_id
    and posted.legal_entity_id = _journal.legal_entity_id
    and posted.accounting_date = _journal.accounting_date
    and posted.currency = _journal.currency
    and posted.source_document_type = 'manual_journal'
    and posted.source_document_id = _journal.id::text
    and posted.source_revision = _journal.revision
    and posted.total_debit = _journal.total_debit
    and posted.total_credit = _journal.total_credit
    and posted.state = 'posted';
  if not found then
    raise exception 'ONEXA_MANUAL_JOURNAL_B4_POST_CONTRACT_MISMATCH';
  end if;

  update public.onexa_manual_journals
  set status = 'posted', posted_journal_id = _journal_id_result,
      posted_by = _actor, posted_at = now(), updated_at = now()
  where id = _journal.id and tenant_id = _tenant_id and status = 'approved';
  if not found then raise exception 'ONEXA_MANUAL_JOURNAL_POST_STATUS_UPDATE_FAILED'; end if;

  insert into public.onexa_manual_journal_events (
    tenant_id, manual_journal_id, event_type, from_status, to_status, actor_id, event_data
  ) values (
    _tenant_id, _journal.id, 'posting_completed', 'approved', 'posted', _actor,
    jsonb_build_object('journal_id', _journal_id_result, 'posting_contract_version', 'manual-journal-v1')
  );

  return _journal_id_result;
end;
$function$;

-- This replacement preserves the existing EXECUTE grants.
commit;
