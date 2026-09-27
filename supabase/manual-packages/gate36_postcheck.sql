-- Gate 36 fail-safe production verification.
-- Uses temporary diagnostic rows only and rolls them back.

begin;

create temporary table onexa_gate36_postcheck_results (
  check_group text not null,
  check_name text not null,
  details jsonb not null default '{}'::jsonb,
  status text not null
) on commit drop;

insert into onexa_gate36_postcheck_results (
  check_group,
  check_name,
  details,
  status
)
values
  (
    'object',
    'onexa_purchase_posting_runs',
    '{"object_type":"table"}'::jsonb,
    case when to_regclass('public.onexa_purchase_posting_runs') is not null
      then 'READY' else 'MISSING' end
  ),
  (
    'object',
    'onexa_purchase_inventory_reconciliation',
    '{"object_type":"view"}'::jsonb,
    case when to_regclass('public.onexa_purchase_inventory_reconciliation') is not null
      then 'READY' else 'MISSING' end
  ),
  (
    'object',
    'onexa_purchase_posting_configuration_gaps',
    '{"object_type":"view"}'::jsonb,
    case when to_regclass('public.onexa_purchase_posting_configuration_gaps') is not null
      then 'READY' else 'MISSING' end
  ),
  (
    'object',
    'onexa_post_purchase_invoice',
    '{"object_type":"function"}'::jsonb,
    case when to_regprocedure(
      'public.onexa_post_purchase_invoice(uuid,text)'
    ) is not null then 'READY' else 'MISSING' end
  );

do $postcheck$
declare
  _object_name text;
  _object_oid oid;
  _rls_enabled boolean;
  _direct_writes_denied boolean;
  _security_invoker boolean;
  _routine_oid oid;
  _security_definer boolean;
  _fixed_search_path boolean;
  _anon_can_execute boolean;
  _authenticated_can_execute boolean;
  _gap_count bigint;
  _anomaly_count bigint;
  _pending_count bigint;
begin
  _object_oid := to_regclass('public.onexa_purchase_posting_runs');

  if _object_oid is null then
    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'table_security',
      'onexa_purchase_posting_runs',
      '{}'::jsonb,
      'MISSING'
    );
  else
    select c.relrowsecurity
    into _rls_enabled
    from pg_catalog.pg_class as c
    where c.oid = _object_oid;

    _direct_writes_denied := not has_table_privilege(
      'authenticated',
      _object_oid,
      'INSERT,UPDATE,DELETE'
    );

    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'table_security',
      'onexa_purchase_posting_runs',
      jsonb_build_object(
        'rls_enabled', coalesce(_rls_enabled, false),
        'authenticated_direct_writes_denied',
        coalesce(_direct_writes_denied, false),
        'requirement',
        'authenticated direct insert/update/delete must remain false'
      ),
      case
        when coalesce(_rls_enabled, false)
          and coalesce(_direct_writes_denied, false)
        then 'READY'
        else 'REVIEW_REQUIRED'
      end
    );
  end if;

  foreach _object_name in array array[
    'onexa_purchase_inventory_reconciliation',
    'onexa_purchase_posting_configuration_gaps'
  ]
  loop
    _object_oid := to_regclass('public.' || _object_name);

    if _object_oid is null then
      insert into onexa_gate36_postcheck_results
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

      insert into onexa_gate36_postcheck_results
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
    'public.onexa_post_purchase_invoice(uuid,text)'
  );

  if _routine_oid is null then
    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'function_security',
      'onexa_post_purchase_invoice',
      '{}'::jsonb,
      'MISSING'
    );
  else
    select
      proc.prosecdef,
      coalesce(proc.proconfig, array[]::text[])
        @> array['search_path=pg_catalog, public']
    into
      _security_definer,
      _fixed_search_path
    from pg_catalog.pg_proc as proc
    where proc.oid = _routine_oid;

    _anon_can_execute := has_function_privilege(
      'anon', _routine_oid, 'EXECUTE'
    );
    _authenticated_can_execute := has_function_privilege(
      'authenticated', _routine_oid, 'EXECUTE'
    );

    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'function_security',
      'onexa_post_purchase_invoice',
      jsonb_build_object(
        'security_definer', coalesce(_security_definer, false),
        'fixed_search_path', coalesce(_fixed_search_path, false),
        'anon_can_execute', coalesce(_anon_can_execute, false),
        'authenticated_can_execute',
        coalesce(_authenticated_can_execute, false)
      ),
      case
        when coalesce(_security_definer, false)
          and coalesce(_fixed_search_path, false)
          and not coalesce(_anon_can_execute, false)
          and coalesce(_authenticated_can_execute, false)
        then 'READY'
        else 'REVIEW_REQUIRED'
      end
    );
  end if;

  if to_regclass(
    'public.onexa_purchase_posting_configuration_gaps'
  ) is null then
    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values ('configuration', 'account_mapping_gaps', '{}'::jsonb, 'MISSING');
  else
    execute
      'select count(*) from public.onexa_purchase_posting_configuration_gaps'
    into _gap_count;

    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'configuration',
      'account_mapping_gaps',
      jsonb_build_object('gap_count', _gap_count),
      case when _gap_count = 0 then 'READY' else 'MAPPING_REQUIRED' end
    );
  end if;

  if to_regclass(
    'public.onexa_purchase_inventory_reconciliation'
  ) is null then
    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'reconciliation',
      'purchase_posting_anomalies',
      '{}'::jsonb,
      'MISSING'
    );
  else
    execute $sql$
      select
        count(*) filter (
          where reconciliation_status not in ('reconciled', 'not_posted')
        ),
        count(*) filter (
          where reconciliation_status = 'not_posted'
        )
      from public.onexa_purchase_inventory_reconciliation
    $sql$
    into _anomaly_count, _pending_count;

    insert into onexa_gate36_postcheck_results
      (check_group, check_name, details, status)
    values (
      'reconciliation',
      'purchase_posting_anomalies',
      jsonb_build_object(
        'anomaly_count', _anomaly_count,
        'workflow_pending_count', _pending_count
      ),
      case when _anomaly_count = 0
        then 'READY' else 'REVIEW_REQUIRED' end
    );
  end if;
end;
$postcheck$;

select
  check_group,
  check_name,
  details,
  status
from onexa_gate36_postcheck_results
order by
  case check_group
    when 'object' then 1
    when 'table_security' then 2
    when 'view_security' then 3
    when 'function_security' then 4
    when 'configuration' then 5
    when 'reconciliation' then 6
    else 99
  end,
  check_name;

rollback;
