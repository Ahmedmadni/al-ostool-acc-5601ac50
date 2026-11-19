-- Source-parity CI fixture derived from the same prospective reviewed
-- B4 publisher function. Disposable PostgreSQL ONLY, never production.
do $check$
begin
 if current_database()<>'onexa_gate_test' or
    to_regclass('public.fixture_module_grants') is null then
   raise exception 'ONEXA_B4_STRICT_FIXTURE_DISPOSABLE_ONLY';
 end if;
end $check$;

CREATE OR REPLACE FUNCTION onexa_private.post_journal(_legal_entity_id uuid, _source_document_type text, _source_document_id text, _source_revision integer, _source_status text, _source_snapshot jsonb, _accounting_date date, _period_code text, _currency text, _memo text, _lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tenant_id text := onexa_private.claim_tenant_id();
  v_period_id uuid;
  v_journal_id uuid;
  v_existing uuid;
  v_key text;
  -- Aggregate source values at original precision: no storage rounding before validation.
  v_debit numeric;
  v_credit numeric;
  v_number text;
begin
  if auth.uid() is null
     or not onexa_private.has_workspace_role(
       auth.uid(),
       array['workspace_owner','finance_manager','accountant']
     ) then
    raise exception 'ONEXA_POSTING_FORBIDDEN';
  end if;

  if _source_status is distinct from 'approved' then
    raise exception 'ONEXA_SOURCE_NOT_APPROVED';
  end if;

  if _source_revision is null or _source_revision < 1 then
    raise exception 'ONEXA_INVALID_SOURCE_REVISION';
  end if;

  if _currency is null or _currency !~ '^[A-Z]{3}$' then
    raise exception 'ONEXA_INVALID_CURRENCY';
  end if;

  if _lines is null or jsonb_typeof(_lines) <> 'array'
     or jsonb_array_length(_lines) < 2 then
    raise exception 'ONEXA_JOURNAL_REQUIRES_TWO_LINES';
  end if;

  if not exists (
    select 1
    from public.onexa_legal_entities e
    where e.id = _legal_entity_id
      and e.tenant_id = v_tenant_id
      and e.is_active
  ) then
    raise exception 'ONEXA_INVALID_LEGAL_ENTITY';
  end if;

  select p.id
  into v_period_id
  from public.onexa_fiscal_periods p
  where p.tenant_id = v_tenant_id
    and p.legal_entity_id = _legal_entity_id
    and p.period_code = _period_code
    and p.status = 'open'
    and _accounting_date between p.starts_on and p.ends_on;

  if v_period_id is null then
    raise exception 'ONEXA_PERIOD_NOT_OPEN';
  end if;

  -- B4 is shared by every finance module. Reject null/missing/non-numeric
  -- source amounts before aggregation, and reject silent numeric(20,4)
  -- storage rounding (SAR must be expressed in full halalas).
  if nullif(btrim(_source_document_type), '') is null
     or nullif(btrim(_source_document_id), '') is null then
    raise exception 'ONEXA_B4_SOURCE_ID_REQUIRED';
  end if;
  if exists (
    select 1 from jsonb_array_elements(_lines) x
    where jsonb_typeof(x) is distinct from 'object'
       or jsonb_typeof(x->'debit') is distinct from 'number'
       or jsonb_typeof(x->'credit') is distinct from 'number'
       or nullif(btrim(x->>'account_code'), '') is null
       or (x->>'debit')::numeric < 0
       or (x->>'credit')::numeric < 0
       or not (((x->>'debit')::numeric > 0) <> ((x->>'credit')::numeric > 0))
       or (x ? 'dimensions' and x->'dimensions' <> 'null'::jsonb
          and jsonb_typeof(x->'dimensions') is distinct from 'object')
  ) then
    raise exception 'ONEXA_B4_LINE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(_lines) x
    where (x->>'debit')::numeric <> round((x->>'debit')::numeric,4)
       or (x->>'credit')::numeric <> round((x->>'credit')::numeric,4)
  ) then
    raise exception 'ONEXA_B4_STORAGE_PRECISION_INVALID';
  end if;
  if _currency='SAR' and exists (
    select 1 from jsonb_array_elements(_lines) x
    where (x->>'debit')::numeric <> round((x->>'debit')::numeric,2)
       or (x->>'credit')::numeric <> round((x->>'credit')::numeric,2)
  ) then
    raise exception 'ONEXA_B4_SAR_HALALA_PRECISION_INVALID';
  end if;

  select
    coalesce(sum((x->>'debit')::numeric), 0),
    coalesce(sum((x->>'credit')::numeric), 0)
  into
    v_debit,
    v_credit
  from jsonb_array_elements(_lines) x;

  if v_debit <= 0
     or v_credit <= 0
     or v_debit <> v_credit then
    raise exception 'ONEXA_JOURNAL_NOT_BALANCED';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(_lines) x
    where coalesce(x->>'account_code', '') = ''
       or coalesce((x->>'debit')::numeric, 0) < 0
       or coalesce((x->>'credit')::numeric, 0) < 0
       or (
         (coalesce((x->>'debit')::numeric, 0) > 0)
         =
         (coalesce((x->>'credit')::numeric, 0) > 0)
       )
  ) then
    raise exception 'ONEXA_INVALID_JOURNAL_LINE';
  end if;

  v_key := concat_ws(
    ':',
    'onexa-posting-v1',
    v_tenant_id,
    _legal_entity_id::text,
    _source_document_type,
    _source_document_id,
    _source_revision::text
  );

  perform pg_advisory_xact_lock(
    hashtextextended(v_key, 0)
  );

  select r.journal_id
  into v_existing
  from public.onexa_posting_registry r
  where r.idempotency_key = v_key;

  if v_existing is not null then
    -- An idempotency key protects against *duplicate inserts*, but does not
    -- establish that a retry carries the same approved accounting payload.
    -- Compare the stored receipt and the ordered GL lines under the same
    -- advisory transaction lock before returning the original posting ID.
    if not exists (
      select 1
      from public.onexa_posting_registry r
      join public.onexa_journal_headers h
        on h.id = r.journal_id
       and h.tenant_id = v_tenant_id
      where r.idempotency_key = v_key
        and r.tenant_id = v_tenant_id
        and r.legal_entity_id = _legal_entity_id
        and r.source_document_type = _source_document_type
        and r.source_document_id = _source_document_id
        and r.source_revision = _source_revision
        and h.id = v_existing
        and h.legal_entity_id = _legal_entity_id
        and h.source_document_type = _source_document_type
        and h.source_document_id = _source_document_id
        and h.source_revision = _source_revision
        and h.accounting_date = _accounting_date
        and h.fiscal_period_id = v_period_id
        and h.currency = _currency
        and h.memo is not distinct from _memo
        and h.source_snapshot = coalesce(_source_snapshot, '{}'::jsonb)
        and h.total_debit = v_debit
        and h.total_credit = v_credit
        and h.state in ('posted', 'reversed')
        and (
          select coalesce(jsonb_agg(jsonb_build_object(
            'account_code', l.account_code,
            'debit', l.debit,
            'credit', l.credit,
            'description', l.description,
            'dimensions', l.dimensions
          ) order by l.line_number), '[]'::jsonb)
          from public.onexa_journal_lines l
          where l.journal_id = h.id
            and l.tenant_id = v_tenant_id
        ) = (
          select coalesce(jsonb_agg(jsonb_build_object(
            'account_code', x->>'account_code',
            'debit', (x->>'debit')::numeric,
            'credit', (x->>'credit')::numeric,
            'description', nullif(x->>'description', ''),
            'dimensions', coalesce(x->'dimensions', '{}'::jsonb)
          ) order by ordinality), '[]'::jsonb)
          from jsonb_array_elements(_lines) with ordinality as t(x, ordinality)
        )
    ) then
      raise exception 'ONEXA_B4_POSTING_PAYLOAD_CONFLICT';
    end if;
    return v_existing;
  end if;

  v_journal_id := gen_random_uuid();

  v_number :=
    'J-'
    || to_char(_accounting_date, 'YYYYMM')
    || '-'
    || lpad(
      nextval('public.onexa_journal_number_seq')::text,
      8,
      '0'
    );

  insert into public.onexa_journal_headers (
    id,
    tenant_id,
    legal_entity_id,
    journal_number,
    accounting_date,
    fiscal_period_id,
    currency,
    source_document_type,
    source_document_id,
    source_revision,
    source_snapshot,
    memo,
    total_debit,
    total_credit,
    posted_by
  )
  values (
    v_journal_id,
    v_tenant_id,
    _legal_entity_id,
    v_number,
    _accounting_date,
    v_period_id,
    _currency,
    _source_document_type,
    _source_document_id,
    _source_revision,
    coalesce(_source_snapshot, '{}'::jsonb),
    _memo,
    v_debit,
    v_credit,
    auth.uid()
  );

  insert into public.onexa_journal_lines (
    tenant_id,
    journal_id,
    line_number,
    account_code,
    debit,
    credit,
    description,
    dimensions
  )
  select
    v_tenant_id,
    v_journal_id,
    ordinality::integer,
    x->>'account_code',
    coalesce((x->>'debit')::numeric, 0),
    coalesce((x->>'credit')::numeric, 0),
    nullif(x->>'description', ''),
    coalesce(x->'dimensions', '{}'::jsonb)
  from jsonb_array_elements(_lines)
  with ordinality as t(x, ordinality);

  insert into public.onexa_posting_registry (
    idempotency_key,
    tenant_id,
    legal_entity_id,
    source_document_type,
    source_document_id,
    source_revision,
    journal_id
  )
  values (
    v_key,
    v_tenant_id,
    _legal_entity_id,
    _source_document_type,
    _source_document_id,
    _source_revision,
    v_journal_id
  );

  insert into public.onexa_workspace_audit_events (
    tenant_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    details
  )
  values (
    v_tenant_id,
    auth.uid(),
    'journal_posted',
    'journal',
    v_journal_id::text,
    jsonb_build_object(
      'source_type', _source_document_type,
      'source_id', _source_document_id,
      'source_revision', _source_revision
    )
  );

  return v_journal_id;
end;
$function$;
