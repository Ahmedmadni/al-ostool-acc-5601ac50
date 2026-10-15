-- Gate 40 fail-safe production postcheck.
-- Uses temporary tables only and rolls every diagnostic change back.
begin;

create temporary table onexa_gate40_postcheck_results (
  check_group text not null,
  check_name text not null,
  details jsonb not null default '{}'::jsonb,
  status text not null
) on commit drop;

insert into onexa_gate40_postcheck_results (
  check_group,
  check_name,
  details,
  status
)
values
  ('object', 'onexa_supplier_payment_postings', '{}'::jsonb,
    case when to_regclass('public.onexa_supplier_payment_postings') is not null
      then 'READY' else 'MISSING' end),
  ('object', 'onexa_supplier_payment_allocations', '{}'::jsonb,
    case when to_regclass('public.onexa_supplier_payment_allocations') is not null
      then 'READY' else 'MISSING' end),
  ('object', 'onexa_supplier_payables_reconciliation', '{}'::jsonb,
    case when to_regclass('public.onexa_supplier_payables_reconciliation') is not null
      then 'READY' else 'MISSING' end),
  ('object', 'onexa_supplier_payment_configuration_gaps', '{}'::jsonb,
    case when to_regclass('public.onexa_supplier_payment_configuration_gaps') is not null
      then 'READY' else 'MISSING' end),
  ('object', 'onexa_post_supplier_payment', '{}'::jsonb,
    case when to_regprocedure('public.onexa_post_supplier_payment(uuid,text)') is not null
      then 'READY' else 'MISSING' end);

do $postcheck$
declare
  _object_name text;
  _object_oid oid;
  _rls_enabled boolean;
  _direct_writes_denied boolean;
  _security_invoker boolean;
  _routine_oid oid;
  _anon_can_execute boolean;
  _authenticated_can_execute boolean;
  _gap_count bigint;
  _anomaly_count bigint;
  _pending_count bigint;
  _member record;
  _creator_count integer := 0;
  _operator_count integer := 0;
  _distinct_pair_ready boolean := false;
begin
  foreach _object_name in array array[
    'onexa_supplier_payment_postings',
    'onexa_supplier_payment_allocations'
  ]
  loop
    _object_oid := to_regclass('public.' || _object_name);

    if _object_oid is null then
      insert into onexa_gate40_postcheck_results
        (check_group, check_name, details, status)
      values ('table_security', _object_name, '{}'::jsonb, 'MISSING');
    else
      select c.relrowsecurity
      into _rls_enabled
      from pg_catalog.pg_class as c
      where c.oid = _object_oid;

      _direct_writes_denied := not has_table_privilege(
        'authenticated', _object_oid, 'INSERT,UPDATE,DELETE'
      );

      insert into onexa_gate40_postcheck_results
        (check_group, check_name, details, status)
      values (
        'table_security',
        _object_name,
        jsonb_build_object(
          'rls_enabled', coalesce(_rls_enabled, false),
          'authenticated_direct_writes_denied',
          coalesce(_direct_writes_denied, false)
        ),
        case
          when coalesce(_rls_enabled, false)
            and coalesce(_direct_writes_denied, false)
          then 'READY'
          else 'REVIEW_REQUIRED'
        end
      );
    end if;
  end loop;

  foreach _object_name in array array[
    'onexa_supplier_payables_reconciliation',
    'onexa_supplier_payment_configuration_gaps'
  ]
  loop
    _object_oid := to_regclass('public.' || _object_name);

    if _object_oid is null then
      insert into onexa_gate40_postcheck_results
        (check_group, check_name, details, status)
      values ('view_security', _object_name, '{}'::jsonb, 'MISSING');
    else
      select coalesce(
        c.reloptions @> array['security_invoker=true'],
        false
      )
      into _security_invoker
      from pg_catalog.pg_class as c
      where c.oid = _object_oid;

      insert into onexa_gate40_postcheck_results
        (check_group, check_name, details, status)
      values (
        'view_security',
        _object_name,
        jsonb_build_object(
          'security_invoker', coalesce(_security_invoker, false)
        ),
        case when coalesce(_security_invoker, false)
          then 'READY' else 'REVIEW_REQUIRED' end
      );
    end if;
  end loop;

  _routine_oid := to_regprocedure(
    'public.onexa_post_supplier_payment(uuid,text)'
  );

  if _routine_oid is null then
    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values
      ('function_security', 'onexa_post_supplier_payment', '{}'::jsonb, 'MISSING');
  else
    _anon_can_execute := has_function_privilege(
      'anon', _routine_oid, 'EXECUTE'
    );
    _authenticated_can_execute := has_function_privilege(
      'authenticated', _routine_oid, 'EXECUTE'
    );

    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values (
      'function_security',
      'onexa_post_supplier_payment',
      jsonb_build_object(
        'anon_can_execute', coalesce(_anon_can_execute, false),
        'authenticated_can_execute',
        coalesce(_authenticated_can_execute, false)
      ),
      case
        when not coalesce(_anon_can_execute, false)
          and coalesce(_authenticated_can_execute, false)
        then 'READY'
        else 'REVIEW_REQUIRED'
      end
    );
  end if;

  if to_regclass('public.onexa_supplier_payment_configuration_gaps') is null then
    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values ('configuration', 'account_mapping_gaps', '{}'::jsonb, 'MISSING');
  else
    execute
      'select count(*) from public.onexa_supplier_payment_configuration_gaps'
    into _gap_count;

    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values (
      'configuration',
      'account_mapping_gaps',
      jsonb_build_object('gap_count', _gap_count),
      case when _gap_count = 0 then 'READY' else 'MAPPING_REQUIRED' end
    );
  end if;

  if to_regclass('public.onexa_supplier_payables_reconciliation') is null then
    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values
      ('reconciliation', 'supplier_payment_anomalies', '{}'::jsonb, 'MISSING');
  else
    execute $sql$
      select
        count(*) filter (
          where reconciliation_status in (
            'invoice_journal_mismatch',
            'overallocated'
          )
          or outstanding_amount < 0
        ),
        count(*) filter (
          where reconciliation_status = 'invoice_not_posted'
        )
      from public.onexa_supplier_payables_reconciliation
    $sql$
    into _anomaly_count, _pending_count;

    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values (
      'reconciliation',
      'supplier_payment_anomalies',
      jsonb_build_object(
        'anomaly_count', _anomaly_count,
        'workflow_pending_count', _pending_count
      ),
      case when _anomaly_count = 0 then 'READY' else 'REVIEW_REQUIRED' end
    );
  end if;

  -- A stray allocation, a cross-entity/vendor allocation, or an allocation
  -- without a journal-backed posted payment must never silently reduce AP.
  if to_regclass('public.onexa_supplier_payment_allocations') is null
    or to_regclass('public.onexa_supplier_payment_postings') is null then
    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values ('reconciliation', 'payment_allocation_source_integrity', '{}'::jsonb, 'MISSING');
  else
    execute $sql$
      select count(*)
      from public.onexa_supplier_payment_allocations allocation
      left join public.onexa_supplier_payment_postings posted_payment
        on posted_payment.document_id = allocation.payment_id
        and posted_payment.tenant_id = allocation.tenant_id
        and posted_payment.legal_entity_id = allocation.legal_entity_id
        and posted_payment.vendor_id = allocation.vendor_id
      left join public.onexa_business_documents payment_document
        on payment_document.id = posted_payment.document_id
        and payment_document.tenant_id = posted_payment.tenant_id
        and payment_document.legal_entity_id = posted_payment.legal_entity_id
        and payment_document.party_type = 'vendor'
        and payment_document.party_id = posted_payment.vendor_id
        and payment_document.document_type = 'supplier_payment'
        and payment_document.module_key = 'procurement'
        and payment_document.status = 'posted'
        and payment_document.posted_journal_id = posted_payment.journal_id
      left join public.onexa_business_documents invoice
        on invoice.id = allocation.invoice_id
        and invoice.tenant_id = allocation.tenant_id
        and invoice.legal_entity_id = allocation.legal_entity_id
        and invoice.party_id = allocation.vendor_id
        and invoice.document_type = 'purchase_invoice'
        and invoice.status = 'posted'
      where posted_payment.document_id is null
         or payment_document.id is null
         or invoice.id is null
    $sql$ into _anomaly_count;

    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values (
      'reconciliation', 'payment_allocation_source_integrity',
      jsonb_build_object('invalid_allocation_count', _anomaly_count),
      case when _anomaly_count = 0 then 'READY' else 'REVIEW_REQUIRED' end
    );
  end if;

  if to_regclass('public.onexa_workspace_memberships') is null
    or to_regprocedure(
      'onexa_private.has_module_action(uuid,text,text)'
    ) is null then
    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values
      ('authorization', 'distinct_creator_and_operator', '{}'::jsonb, 'MISSING');
  else
    create temporary table onexa_gate40_user_actions (
      user_id uuid primary key,
      can_create boolean not null,
      can_post boolean not null
    ) on commit drop;

    for _member in
      select membership.user_id
      from public.onexa_workspace_memberships as membership
      where membership.tenant_id = 'tenant-001-al-ostool'
        and membership.status = 'active'
    loop
      perform set_config(
        'request.jwt.claims',
        jsonb_build_object(
          'sub', _member.user_id,
          'role', 'authenticated',
          'app_metadata', jsonb_build_object(
            'onexa_tenant_id', 'tenant-001-al-ostool'
          )
        )::text,
        true
      );

      insert into onexa_gate40_user_actions (
        user_id,
        can_create,
        can_post
      )
      values (
        _member.user_id,
        coalesce(onexa_private.has_module_action(
          _member.user_id, 'procurement', 'create'
        ), false),
        coalesce(onexa_private.has_module_action(
          _member.user_id, 'procurement', 'post'
        ), false)
      );
    end loop;

    select
      count(*) filter (where can_create),
      count(*) filter (where can_post)
    into _creator_count, _operator_count
    from onexa_gate40_user_actions;

    select exists (
      select 1
      from onexa_gate40_user_actions as creator
      cross join onexa_gate40_user_actions as operator
      where creator.can_create
        and operator.can_post
        and creator.user_id <> operator.user_id
    )
    into _distinct_pair_ready;

    insert into onexa_gate40_postcheck_results
      (check_group, check_name, details, status)
    values (
      'authorization',
      'distinct_creator_and_operator',
      jsonb_build_object(
        'eligible_creators', _creator_count,
        'eligible_operators', _operator_count,
        'distinct_pair_ready', _distinct_pair_ready
      ),
      case when _distinct_pair_ready then 'READY' else 'BLOCKED' end
    );
  end if;
end;
$postcheck$;

select
  check_group,
  check_name,
  details,
  status
from onexa_gate40_postcheck_results
order by
  case check_group
    when 'object' then 1
    when 'table_security' then 2
    when 'view_security' then 3
    when 'function_security' then 4
    when 'configuration' then 5
    when 'authorization' then 6
    when 'reconciliation' then 7
    else 99
  end,
  check_name;

rollback;
