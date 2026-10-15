-- ONEXA Gates 40-43 prerequisites — READ ONLY (do not use to activate a feature).
-- This is for the actual customer Data Plane; no production changes are made.
-- PASS = required dependency object/role exists, NOT approval to run DDL.
with checks(gate_code,check_name,ready) as (
  values
    ('G40','B4_GL_post_journal',
      to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is not null),
    ('G40','G36_purchase_posting_runs',to_regclass('public.onexa_purchase_posting_runs') is not null),
    ('G40','business_documents',to_regclass('public.onexa_business_documents') is not null),
    ('G40','account_mapping_AR_AP',
      exists(select 1 from public.onexa_account_role_mappings m
        where m.tenant_id='tenant-001-al-ostool' and m.is_active
          and m.account_role='accounts_payable')),
    ('G40','account_mapping_cash_or_bank',
      exists(select 1 from public.onexa_account_role_mappings m
        where m.tenant_id='tenant-001-al-ostool' and m.is_active
          and m.account_role='cash_or_bank')),
    ('G40','supplier_payment_rpc_installed',
      to_regprocedure('public.onexa_post_supplier_payment(uuid,text)') is not null),
    ('G41','B4_GL_post_journal',
      to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is not null),
    ('G41','chart_of_accounts',to_regclass('public.chart_of_accounts') is not null),
    ('G41','treasury_accounts_table',to_regclass('public.onexa_treasury_accounts') is not null),
    ('G41','bank_transfer_rpc_installed',
      to_regprocedure('public.onexa_post_bank_transfer(uuid,text)') is not null),
    ('G42','B4_GL_post_journal',
      to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is not null),
    ('G42','account_role_mappings',to_regclass('public.onexa_account_role_mappings') is not null),
    ('G42','project_cost_centers_table',to_regclass('public.onexa_project_cost_centers') is not null),
    ('G42','project_cost_posting_rpc_installed',
      to_regprocedure('public.onexa_post_project_cost(uuid,text)') is not null),
    ('G43','B4_GL_post_journal',
      to_regprocedure('public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)') is not null),
    ('G43','fleet_trips',to_regclass('public.fleet_trips') is not null),
    ('G43','fleet_vehicles',to_regclass('public.fleet_vehicles') is not null),
    ('G43','fleet_trips_tenant_id',
      exists(select 1 from information_schema.columns
        where table_schema='public' and table_name='fleet_trips' and column_name='tenant_id')),
    ('G43','fleet_vehicles_tenant_id',
      exists(select 1 from information_schema.columns
        where table_schema='public' and table_name='fleet_vehicles' and column_name='tenant_id')),
    ('G43','fleet_cost_posting_rpc_installed',
      to_regprocedure('public.onexa_post_fleet_trip_cost(uuid,text)') is not null)
)
select gate_code,check_name,case when ready then 'PRESENT' else 'MISSING' end as state,
  'PERMISSIONS_MAPPINGS_AND_SMOKE_NOT_VERIFIED' as qualification
from checks order by gate_code,check_name;
