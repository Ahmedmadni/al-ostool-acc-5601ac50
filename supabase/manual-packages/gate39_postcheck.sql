-- Gate 39 fail-safe postcheck.
-- Safe to run before or after the migration. Missing objects are reported as
-- MISSING instead of raising relation-does-not-exist errors.
-- The temporary result table is removed by the final ROLLBACK.

begin;

create temporary table gate39_postcheck_results (
  check_group text not null,
  check_name text not null,
  status text not null,
  details jsonb not null default '{}'::jsonb
) on commit drop;

insert into gate39_postcheck_results (
  check_group,
  check_name,
  status,
  details
)
select
  'object',
  object_name,
  case
    when object_oid is null then 'MISSING'
    else 'READY'
  end,
  jsonb_build_object(
    'object_oid',
    object_oid
  )
from (
  values
    (
      'table:onexa_customer_receipt_postings',
      to_regclass(
        'public.onexa_customer_receipt_postings'
      )::oid
    ),
    (
      'table:onexa_customer_receipt_allocations',
      to_regclass(
        'public.onexa_customer_receipt_allocations'
      )::oid
    ),
    (
      'view:onexa_customer_receivables_reconciliation',
      to_regclass(
        'public.onexa_customer_receivables_reconciliation'
      )::oid
    ),
    (
      'view:onexa_customer_receipt_configuration_gaps',
      to_regclass(
        'public.onexa_customer_receipt_configuration_gaps'
      )::oid
    ),
    (
      'function:onexa_post_customer_receipt',
      to_regprocedure(
        'public.onexa_post_customer_receipt(uuid,text)'
      )::oid
    )
) object_state(
  object_name,
  object_oid
);

insert into gate39_postcheck_results (
  check_group,
  check_name,
  status,
  details
)
select
  'table_security',
  expected.object_name,

  case
    when relation.oid is null then
      'MISSING'

    when relation.relrowsecurity is not true then
      'RLS_DISABLED'

    when has_table_privilege(
      'authenticated',
      relation.oid,
      'INSERT,UPDATE,DELETE'
    ) then
      'DIRECT_WRITE_EXPOSED'

    else
      'READY'
  end,

  jsonb_build_object(
    'rls_enabled',
    relation.relrowsecurity,

    'authenticated_direct_writes_denied',
    case
      when relation.oid is null then null
      else not has_table_privilege(
        'authenticated',
        relation.oid,
        'INSERT,UPDATE,DELETE'
      )
    end
  )

from (
  values
    (
      'onexa_customer_receipt_postings',
      to_regclass(
        'public.onexa_customer_receipt_postings'
      )::oid
    ),
    (
      'onexa_customer_receipt_allocations',
      to_regclass(
        'public.onexa_customer_receipt_allocations'
      )::oid
    )
) expected(
  object_name,
  object_oid
)

left join pg_class relation
  on relation.oid = expected.object_oid;

insert into gate39_postcheck_results (
  check_group,
  check_name,
  status,
  details
)
select
  'view_security',
  expected.object_name,

  case
    when relation.oid is null then
      'MISSING'

    when coalesce(
      relation.reloptions
        @> array['security_invoker=true'],
      false
    ) is not true then
      'SECURITY_INVOKER_DISABLED'

    else
      'READY'
  end,

  jsonb_build_object(
    'security_invoker',
    case
      when relation.oid is null then null

      else coalesce(
        relation.reloptions
          @> array['security_invoker=true'],
        false
      )
    end
  )

from (
  values
    (
      'onexa_customer_receivables_reconciliation',
      to_regclass(
        'public.onexa_customer_receivables_reconciliation'
      )::oid
    ),
    (
      'onexa_customer_receipt_configuration_gaps',
      to_regclass(
        'public.onexa_customer_receipt_configuration_gaps'
      )::oid
    )
) expected(
  object_name,
  object_oid
)

left join pg_class relation
  on relation.oid = expected.object_oid;

insert into gate39_postcheck_results (
  check_group,
  check_name,
  status,
  details
)
select
  'function_security',
  'onexa_post_customer_receipt',

  case
    when routine_oid is null then
      'MISSING'

    when coalesce(
      has_function_privilege(
        'anon',
        routine_oid,
        'EXECUTE'
      ),
      false
    ) then
      'ANON_EXECUTE_EXPOSED'

    when coalesce(
      has_function_privilege(
        'authenticated',
        routine_oid,
        'EXECUTE'
      ),
      false
    ) is not true then
      'AUTHENTICATED_EXECUTE_MISSING'

    else
      'READY'
  end,

  jsonb_build_object(
    'anon_can_execute',
    case
      when routine_oid is null then null

      else has_function_privilege(
        'anon',
        routine_oid,
        'EXECUTE'
      )
    end,

    'authenticated_can_execute',
    case
      when routine_oid is null then null

      else has_function_privilege(
        'authenticated',
        routine_oid,
        'EXECUTE'
      )
    end
  )

from (
  select to_regprocedure(
    'public.onexa_post_customer_receipt(uuid,text)'
  )::oid as routine_oid
) function_state;

do $postcheck$
declare
  _configuration_view regclass :=
    to_regclass(
      'public.onexa_customer_receipt_configuration_gaps'
    );

  _reconciliation_view regclass :=
    to_regclass(
      'public.onexa_customer_receivables_reconciliation'
    );

begin
  if _configuration_view is null then
    insert into gate39_postcheck_results (
      check_group,
      check_name,
      status,
      details
    )
    values (
      'configuration',
      'account_mapping_gaps',
      'SKIPPED_OBJECT_MISSING',
      jsonb_build_object(
        'missing_object',
        'public.onexa_customer_receipt_configuration_gaps'
      )
    );
  else
    execute $sql$
      insert into gate39_postcheck_results (
        check_group,
        check_name,
        status,
        details
      )
      select
        'configuration',
        'account_mapping_gaps',
        case
          when count(*) = 0 then 'READY'
          else 'MAPPING_REQUIRED'
        end,
        jsonb_build_object(
          'gap_count',
          count(*)
        )
      from public.onexa_customer_receipt_configuration_gaps
    $sql$;

    execute $sql$
      insert into gate39_postcheck_results (
        check_group,
        check_name,
        status,
        details
      )
      select
        'configuration_gap',
        legal_entity_code || ':' || account_role,
        'MAPPING_REQUIRED',
        jsonb_build_object(
          'tenant_id',
          tenant_id,
          'legal_entity_id',
          legal_entity_id,
          'legal_entity_code',
          legal_entity_code,
          'account_role',
          account_role
        )
      from public.onexa_customer_receipt_configuration_gaps
      order by
        tenant_id,
        legal_entity_code,
        account_role
    $sql$;
  end if;

  if _reconciliation_view is null then
    insert into gate39_postcheck_results (
      check_group,
      check_name,
      status,
      details
    )
    values (
      'reconciliation',
      'receipt_anomalies',
      'SKIPPED_OBJECT_MISSING',
      jsonb_build_object(
        'missing_object',
        'public.onexa_customer_receivables_reconciliation'
      )
    );
  else
    execute $sql$
      insert into gate39_postcheck_results (
        check_group,
        check_name,
        status,
        details
      )
      select
        'reconciliation',
        'receipt_anomalies',
        case
          when count(*) = 0 then 'READY'
          else 'REVIEW_REQUIRED'
        end,
        jsonb_build_object(
          'anomaly_count',
          count(*)
        )
      from public.onexa_customer_receivables_reconciliation
      where reconciliation_status <> 'reconciled'
         or outstanding_amount < 0
    $sql$;

    execute $sql$
      insert into gate39_postcheck_results (
        check_group,
        check_name,
        status,
        details
      )
      select
        'reconciliation_anomaly',
        document_number,
        'REVIEW_REQUIRED',
        jsonb_build_object(
          'tenant_id',
          tenant_id,
          'legal_entity_id',
          legal_entity_id,
          'document_number',
          document_number,
          'reconciliation_status',
          reconciliation_status,
          'invoiced_amount',
          invoiced_amount,
          'collected_amount',
          collected_amount,
          'outstanding_amount',
          outstanding_amount
        )
      from public.onexa_customer_receivables_reconciliation
      where reconciliation_status <> 'reconciled'
         or outstanding_amount < 0
      order by
        tenant_id,
        legal_entity_id,
        document_number
    $sql$;
  end if;
end;
$postcheck$;

select
  check_group,
  check_name,
  status,
  details
from gate39_postcheck_results
order by
  case check_group
    when 'object' then 1
    when 'table_security' then 2
    when 'view_security' then 3
    when 'function_security' then 4
    when 'configuration' then 5
    when 'configuration_gap' then 6
    when 'reconciliation' then 7
    else 8
  end,
  check_name;

rollback;
