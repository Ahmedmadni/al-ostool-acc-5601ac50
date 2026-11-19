-- ONEXA B4 REVERSAL IDEMPOTENCY — REVIEW ONLY.
-- Never auto-apply to customer/hosted database. Approved independent Staging
-- with verified backup/restore and every finance module acceptance REQUIRED.
-- Protects a historical reversal receipt from changed reason/date/period.
begin;
do $preflight$
declare _actual regprocedure := to_regprocedure(
  'onexa_private.reverse_journal(uuid,date,text,text)'
);
begin
  if _actual is null then
    raise exception 'ONEXA_B4_REVERSE_FUNCTION_MISSING_STOP';
  end if;
  if md5(pg_get_functiondef(_actual::oid))
     <> 'f51a890027057a0e838c13cbfd6ddb61' then
    raise exception 'ONEXA_B4_REVERSAL_DEFINITION_DRIFT_STOP_REVIEW_REQUIRED';
  end if;
  if to_regclass('public.onexa_journal_headers') is null
     or to_regclass('public.onexa_fiscal_periods') is null
     or to_regclass('public.onexa_journal_lines') is null then
    raise exception 'ONEXA_B4_REVERSAL_REQUIRED_LEDGER_PARENTS_MISSING';
  end if;
end $preflight$;

CREATE OR REPLACE FUNCTION onexa_private.reverse_journal(_journal_id uuid, _accounting_date date, _period_code text, _reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_original public.onexa_journal_headers%rowtype;
  v_reversal_id uuid;
  v_lines jsonb;
begin
  if auth.uid() is null
     or not onexa_private.has_workspace_role(
       auth.uid(),
       array['workspace_owner','finance_manager','accountant']
     ) then
    raise exception 'ONEXA_REVERSAL_FORBIDDEN';
  end if;

  if nullif(btrim(_reason), '') is null then
    raise exception 'ONEXA_REVERSAL_REASON_REQUIRED';
  end if;

  select *
  into v_original
  from public.onexa_journal_headers h
  where h.id = _journal_id
    and h.tenant_id = onexa_private.claim_tenant_id()
  for update;

  if not found then
    raise exception 'ONEXA_JOURNAL_NOT_FOUND';
  end if;

  if v_original.source_document_type = 'journal_reversal' then
    raise exception 'ONEXA_REVERSAL_OF_REVERSAL_NOT_ALLOWED';
  end if;

  if v_original.state = 'reversed'
     and v_original.reversal_journal_id is not null then
    -- A reversal is idempotent only for the *same* accounting instruction,
    -- not merely the same original GL id. The historical receipt remains
    -- valid even if its fiscal period was subsequently closed.
    if not exists (
      select 1
      from public.onexa_journal_headers reversal
      join public.onexa_fiscal_periods period
        on period.id = reversal.fiscal_period_id
       and period.tenant_id = v_original.tenant_id
       and period.legal_entity_id = v_original.legal_entity_id
      where reversal.id = v_original.reversal_journal_id
        and reversal.tenant_id = v_original.tenant_id
        and reversal.legal_entity_id = v_original.legal_entity_id
        and reversal.state = 'posted'
        and reversal.source_document_type = 'journal_reversal'
        and reversal.source_document_id = v_original.id::text
        and reversal.source_revision = 1
        and reversal.reversal_of_id = v_original.id
        and reversal.accounting_date = _accounting_date
        and period.period_code = _period_code
        and _accounting_date between period.starts_on and period.ends_on
        and reversal.currency = v_original.currency
        and reversal.total_debit = v_original.total_credit
        and reversal.total_credit = v_original.total_debit
        and reversal.source_snapshot = jsonb_build_object(
          'reversal_of', v_original.id, 'reason', _reason
        )
        and reversal.memo = concat(
          'Reversal of ', v_original.journal_number, ' — ', _reason
        )
        and (select count(*) from public.onexa_journal_lines l
             where l.journal_id = v_original.id and l.tenant_id = v_original.tenant_id) >= 2
        and (select count(*) from public.onexa_journal_lines l
             where l.journal_id = reversal.id and l.tenant_id = v_original.tenant_id) >= 2
        and (select coalesce(sum(l.debit), 0) from public.onexa_journal_lines l
             where l.journal_id = v_original.id and l.tenant_id = v_original.tenant_id) = v_original.total_debit
        and (select coalesce(sum(l.credit), 0) from public.onexa_journal_lines l
             where l.journal_id = v_original.id and l.tenant_id = v_original.tenant_id) = v_original.total_credit
        and (select coalesce(sum(l.debit), 0) from public.onexa_journal_lines l
             where l.journal_id = reversal.id and l.tenant_id = v_original.tenant_id) = reversal.total_debit
        and (select coalesce(sum(l.credit), 0) from public.onexa_journal_lines l
             where l.journal_id = reversal.id and l.tenant_id = v_original.tenant_id) = reversal.total_credit
        and (
          select coalesce(jsonb_agg(jsonb_build_object(
            'account_code', line.account_code,
            'debit', line.debit,
            'credit', line.credit,
            'description', line.description,
            'dimensions', line.dimensions
          ) order by line.line_number), '[]'::jsonb)
          from public.onexa_journal_lines line
          where line.journal_id = reversal.id
            and line.tenant_id = v_original.tenant_id
        ) = (
          select coalesce(jsonb_agg(jsonb_build_object(
            'account_code', line.account_code,
            'debit', line.credit,
            'credit', line.debit,
            'description', concat(
              'عكس القيد ', v_original.journal_number, ' — ', _reason
            ),
            'dimensions', line.dimensions
          ) order by line.line_number), '[]'::jsonb)
          from public.onexa_journal_lines line
          where line.journal_id = v_original.id
            and line.tenant_id = v_original.tenant_id
        )
    ) then
      raise exception 'ONEXA_B4_REVERSAL_PAYLOAD_CONFLICT';
    end if;
    return v_original.reversal_journal_id;
  end if;

  if v_original.state <> 'posted' then
    raise exception 'ONEXA_JOURNAL_NOT_REVERSIBLE';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'account_code', l.account_code,
      'debit', l.credit,
      'credit', l.debit,
      'description',
        concat(
          'عكس القيد ',
          v_original.journal_number,
          ' — ',
          _reason
        ),
      'dimensions', l.dimensions
    )
    order by l.line_number
  )
  into v_lines
  from public.onexa_journal_lines l
  where l.journal_id = v_original.id;

  v_reversal_id := onexa_private.post_journal(
    v_original.legal_entity_id,
    'journal_reversal',
    v_original.id::text,
    1,
    'approved',
    jsonb_build_object(
      'reversal_of', v_original.id,
      'reason', _reason
    ),
    _accounting_date,
    _period_code,
    v_original.currency,
    concat(
      'Reversal of ',
      v_original.journal_number,
      ' — ',
      _reason
    ),
    v_lines
  );

  -- Fail closed if an upstream publisher reuses a stale or inconsistent
  -- reversal registry receipt. Do not reverse the original until validated.
  if v_reversal_id is null or not exists (
    select 1
    from public.onexa_journal_headers reversal
    join public.onexa_fiscal_periods period
      on period.id = reversal.fiscal_period_id
     and period.tenant_id = v_original.tenant_id
     and period.legal_entity_id = v_original.legal_entity_id
    where reversal.id = v_reversal_id
      and reversal.tenant_id = v_original.tenant_id
      and reversal.legal_entity_id = v_original.legal_entity_id
      and reversal.state = 'posted'
      and reversal.source_document_type = 'journal_reversal'
      and reversal.source_document_id = v_original.id::text
      and reversal.source_revision = 1
      and (reversal.reversal_of_id is null
           or reversal.reversal_of_id = v_original.id)
      and reversal.accounting_date = _accounting_date
      and period.period_code = _period_code
      and _accounting_date between period.starts_on and period.ends_on
      and reversal.currency = v_original.currency
      and reversal.total_debit = v_original.total_credit
      and reversal.total_credit = v_original.total_debit
      and reversal.source_snapshot = jsonb_build_object(
        'reversal_of', v_original.id, 'reason', _reason
      )
      and reversal.memo = concat(
        'Reversal of ', v_original.journal_number, ' — ', _reason
      )
      and (select count(*) from public.onexa_journal_lines l
           where l.journal_id = v_original.id and l.tenant_id = v_original.tenant_id) >= 2
      and (select count(*) from public.onexa_journal_lines l
           where l.journal_id = reversal.id and l.tenant_id = v_original.tenant_id) >= 2
      and (select coalesce(sum(l.debit), 0) from public.onexa_journal_lines l
           where l.journal_id = v_original.id and l.tenant_id = v_original.tenant_id) = v_original.total_debit
      and (select coalesce(sum(l.credit), 0) from public.onexa_journal_lines l
           where l.journal_id = v_original.id and l.tenant_id = v_original.tenant_id) = v_original.total_credit
      and (select coalesce(sum(l.debit), 0) from public.onexa_journal_lines l
           where l.journal_id = reversal.id and l.tenant_id = v_original.tenant_id) = reversal.total_debit
      and (select coalesce(sum(l.credit), 0) from public.onexa_journal_lines l
           where l.journal_id = reversal.id and l.tenant_id = v_original.tenant_id) = reversal.total_credit
  ) then
    raise exception 'ONEXA_B4_REVERSAL_RECEIPT_INVALID';
  end if;

  update public.onexa_journal_headers
  set
    state = 'reversed',
    reversal_journal_id = v_reversal_id
  where id = v_original.id;

  update public.onexa_journal_headers
  set reversal_of_id = v_original.id
  where id = v_reversal_id;

  insert into public.onexa_workspace_audit_events (
    tenant_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    details
  )
  values (
    v_original.tenant_id,
    auth.uid(),
    'journal_reversed',
    'journal',
    v_original.id::text,
    jsonb_build_object(
      'reversal_journal_id', v_reversal_id,
      'reason', _reason
    )
  );

  return v_reversal_id;
end;
$function$;

-- No grants, RLS, journal or accounting data are changed by this package.
commit;
