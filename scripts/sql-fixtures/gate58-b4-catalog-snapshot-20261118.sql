-- Exact deployed B4 function definitions captured via SELECT-only pg_get_functiondef
-- from the connected ONEXA project on 2026-11-18. DESIGNED EXCLUSIVELY
-- FOR DISPOSABLE POSTGRESQL CI. NEVER run this snapshot against hosted DB.
-- Underlying parents/roles/tenants in CI are synthetic; production Staging
-- parity requires separate validation. Refresh from the approved catalog
-- rather than editing these function bodies to fit a test.

-- onexa_private.post_journal: pg_get_functiondef MD5 5ac58a780bbed49e8ba31b6f46c39f48
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
  v_debit numeric(20,4);
  v_credit numeric(20,4);
  v_number text;
begin
  if auth.uid() is null
     or not onexa_private.has_workspace_role(
       auth.uid(),
       array['workspace_owner','finance_manager','accountant']
     ) then
    raise exception 'ONEXA_POSTING_FORBIDDEN';
  end if;

  if _source_status <> 'approved' then
    raise exception 'ONEXA_SOURCE_NOT_APPROVED';
  end if;

  if _source_revision < 1 then
    raise exception 'ONEXA_INVALID_SOURCE_REVISION';
  end if;

  if _currency !~ '^[A-Z]{3}$' then
    raise exception 'ONEXA_INVALID_CURRENCY';
  end if;

  if jsonb_typeof(_lines) <> 'array'
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

  select
    coalesce(sum((x->>'debit')::numeric), 0),
    coalesce(sum((x->>'credit')::numeric), 0)
  into
    v_debit,
    v_credit
  from jsonb_array_elements(_lines) x;

  if v_debit <= 0
     or v_credit <= 0
     or abs(v_debit - v_credit) > 0.005 then
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

-- onexa_private.reverse_journal: pg_get_functiondef MD5 f51a890027057a0e838c13cbfd6ddb61
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

  if v_original.state = 'reversed'
     and v_original.reversal_journal_id is not null then
    return v_original.reversal_journal_id;
  end if;

  if v_original.state <> 'posted' then
    raise exception 'ONEXA_JOURNAL_NOT_REVERSIBLE';
  end if;

  if v_original.source_document_type = 'journal_reversal' then
    raise exception 'ONEXA_REVERSAL_OF_REVERSAL_NOT_ALLOWED';
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

-- public.onexa_post_journal: pg_get_functiondef MD5 0f8adeaf5c85cd470f1c1a29b6545376
CREATE OR REPLACE FUNCTION public.onexa_post_journal(_legal_entity_id uuid, _source_document_type text, _source_document_id text, _source_revision integer, _source_status text, _source_snapshot jsonb, _accounting_date date, _period_code text, _currency text, _memo text, _lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'onexa_private'
AS $function$
begin
  if auth.uid() is null or not onexa_private.has_module_action(auth.uid(), 'finance', 'post') then
    raise exception 'ONEXA_JOURNAL_POST_NOT_AUTHORIZED';
  end if;
  return public.onexa_post_journal_unchecked(
    _legal_entity_id, _source_document_type, _source_document_id,
    _source_revision, _source_status, _source_snapshot, _accounting_date,
    _period_code, _currency, _memo, _lines
  );
end;
$function$;

-- public.onexa_reverse_journal: pg_get_functiondef MD5 ac77042a26c0c954a7f26402a583f52e
CREATE OR REPLACE FUNCTION public.onexa_reverse_journal(_journal_id uuid, _accounting_date date, _period_code text, _reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'onexa_private'
AS $function$
begin
  if auth.uid() is null or not onexa_private.has_module_action(auth.uid(), 'finance', 'reverse') then
    raise exception 'ONEXA_JOURNAL_REVERSE_NOT_AUTHORIZED';
  end if;
  return public.onexa_reverse_journal_unchecked(
    _journal_id, _accounting_date, _period_code, _reason
  );
end;
$function$;

-- Public intermediate wrappers also captured from installed production catalog.
-- public.onexa_post_journal_unchecked: pg_get_functiondef MD5 51db95c8878a9ff78db87cc1cef7ae3d
CREATE OR REPLACE FUNCTION public.onexa_post_journal_unchecked(_legal_entity_id uuid, _source_document_type text, _source_document_id text, _source_revision integer, _source_status text, _source_snapshot jsonb, _accounting_date date, _period_code text, _currency text, _memo text, _lines jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select onexa_private.post_journal(
    _legal_entity_id,
    _source_document_type,
    _source_document_id,
    _source_revision,
    _source_status,
    _source_snapshot,
    _accounting_date,
    _period_code,
    _currency,
    _memo,
    _lines
  )
$function$;

-- public.onexa_reverse_journal_unchecked: pg_get_functiondef MD5 9f9b4798858ca441280c07de774769f4
CREATE OR REPLACE FUNCTION public.onexa_reverse_journal_unchecked(_journal_id uuid, _accounting_date date, _period_code text, _reason text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select onexa_private.reverse_journal(
    _journal_id,
    _accounting_date,
    _period_code,
    _reason
  )
$function$;
