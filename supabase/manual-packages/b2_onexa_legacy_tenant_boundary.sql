-- ONEXA ERP — B2 legacy tenant boundary
-- Production package for the inspected 98-table legacy schema.
-- Run only after taking a verified backup/export.

begin;

do $preflight$
declare
  _workspace_count integer;
  _foreign_claim_count integer;
begin
  if to_regprocedure('onexa_private.claim_tenant_id()') is null
     or to_regprocedure('onexa_private.is_active_member(uuid)') is null then
    raise exception 'ONEXA_B2_AUTHORIZATION_HELPERS_REQUIRED';
  end if;

  select count(*) into _workspace_count
  from public.onexa_workspace
  where status = 'active';
  if _workspace_count <> 1 or not exists (
    select 1 from public.onexa_workspace
    where tenant_id = 'tenant-001-al-ostool' and status = 'active'
  ) then
    raise exception 'ONEXA_B2_EXPECTED_SINGLE_ACTIVE_WORKSPACE';
  end if;

  select count(*) into _foreign_claim_count
  from auth.users
  where nullif(raw_app_meta_data->>'onexa_tenant_id', '') is not null
    and raw_app_meta_data->>'onexa_tenant_id' <> 'tenant-001-al-ostool';
  if _foreign_claim_count <> 0 then
    raise exception 'ONEXA_B2_FOREIGN_TENANT_CLAIMS_EXIST';
  end if;
end;
$preflight$;

-- The SQL editor does not carry an end-user JWT. Some legacy UPDATE triggers
-- write to audit_logs, whose tenant_id default reads the trusted app_metadata
-- claim. Install a transaction-local migration claim so those trigger writes
-- remain tenant-scoped. The value is cleared automatically at COMMIT/ROLLBACK.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'service_role',
    'app_metadata', jsonb_build_object(
      'onexa_tenant_id', 'tenant-001-al-ostool'
    )
  )::text,
  true
);

do $migration_context$
begin
  if onexa_private.claim_tenant_id() is distinct from 'tenant-001-al-ostool' then
    raise exception 'ONEXA_B2_MIGRATION_TENANT_CONTEXT_FAILED';
  end if;
end;
$migration_context$;

create temporary table onexa_b2_targets (
  table_name text primary key
) on commit drop;

insert into onexa_b2_targets(table_name)
select cls.relname
from pg_class cls
join pg_namespace ns on ns.oid = cls.relnamespace
where ns.nspname = 'public'
  and cls.relkind in ('r', 'p')
  and cls.relname not like 'onexa\_%' escape '\'
  and (
    not exists (
      select 1 from information_schema.columns col
      where col.table_schema = 'public'
        and col.table_name = cls.relname
        and col.column_name = 'tenant_id'
    )
    or exists (
      select 1 from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = cls.relname
        and policy.policyname = 'onexa_tenant_boundary_restrictive'
    )
  );

do $validate_scope$
declare
  _target_count integer;
  _without_rls integer;
  _without_policy integer;
begin
  select count(*) into _target_count from onexa_b2_targets;
  if _target_count <> 98 then
    raise exception 'ONEXA_B2_SCHEMA_DRIFT: expected 98 legacy tables, found %', _target_count;
  end if;

  select count(*) into _without_rls
  from onexa_b2_targets target
  join pg_class cls on cls.oid = to_regclass(format('public.%I', target.table_name))
  where not cls.relrowsecurity;
  if _without_rls <> 0 then
    raise exception 'ONEXA_B2_RLS_BASELINE_DRIFT: % tables have RLS disabled', _without_rls;
  end if;

  select count(*) into _without_policy
  from onexa_b2_targets target
  where not exists (
    select 1 from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = target.table_name
  );
  if _without_policy <> 0 then
    raise exception 'ONEXA_B2_POLICY_BASELINE_DRIFT: % tables have no legacy policy', _without_policy;
  end if;
end;
$validate_scope$;

do $install$
declare
  _target record;
  _index_name text;
begin
  for _target in select table_name from onexa_b2_targets order by table_name loop
    execute format(
      'alter table public.%I add column if not exists tenant_id text',
      _target.table_name
    );

    execute format(
      'update public.%I set tenant_id = %L where tenant_id is null',
      _target.table_name,
      'tenant-001-al-ostool'
    );

    execute format(
      'alter table public.%I alter column tenant_id set default onexa_private.claim_tenant_id()',
      _target.table_name
    );
    -- audit_logs is a write target of triggers fired by later backfills. Keep it
    -- nullable until those writes finish, then backfill and lock it below.
    if _target.table_name <> 'audit_logs' then
      execute format(
        'alter table public.%I alter column tenant_id set not null',
        _target.table_name
      );
    end if;
    execute format('alter table public.%I enable row level security', _target.table_name);

    if not exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid = to_regclass(format('public.%I', _target.table_name))
        and constraint_row.conname = 'onexa_tenant_id_fkey'
    ) then
      execute format(
        'alter table public.%I add constraint onexa_tenant_id_fkey foreign key (tenant_id) references public.onexa_workspace(tenant_id) on delete restrict not valid',
        _target.table_name
      );
    end if;
    execute format(
      'alter table public.%I validate constraint onexa_tenant_id_fkey',
      _target.table_name
    );

    _index_name := 'onexa_b2_' || substr(md5(_target.table_name), 1, 16) || '_tenant_idx';
    execute format(
      'create index if not exists %I on public.%I (tenant_id)',
      _index_name,
      _target.table_name
    );

    execute format(
      'drop policy if exists onexa_tenant_boundary_restrictive on public.%I',
      _target.table_name
    );
    execute format(
      'create policy onexa_tenant_boundary_restrictive on public.%I as restrictive for all to authenticated using (tenant_id = onexa_private.claim_tenant_id() and onexa_private.is_active_member(auth.uid())) with check (tenant_id = onexa_private.claim_tenant_id() and onexa_private.is_active_member(auth.uid()))',
      _target.table_name
    );

    execute format('revoke all on table public.%I from public, anon', _target.table_name);
  end loop;

  if exists (
    select 1 from onexa_b2_targets where table_name = 'audit_logs'
  ) then
    update public.audit_logs
    set tenant_id = 'tenant-001-al-ostool'
    where tenant_id is null;

    alter table public.audit_logs
      alter column tenant_id set not null;
  end if;
end;
$install$;

commit;
