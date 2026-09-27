-- Gate 39 read-only production preflight.
-- Run before gate39_customer_receipts.sql. The transaction is rolled back.

begin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'role', 'authenticated',
    'app_metadata', jsonb_build_object(
      'onexa_tenant_id',
      'tenant-001-al-ostool'
    )
  )::text,
  true
);

select *
from (
  values
    (
      'foundation_business_documents',
      to_regclass('public.onexa_business_documents') is not null
    ),
    (
      'foundation_business_document_lines',
      to_regclass('public.onexa_business_document_lines') is not null
    ),
    (
      'foundation_post_journal',
      to_regprocedure(
        'public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'
      ) is not null
    ),
    (
      'gate35_sales_posting_runs',
      to_regclass('public.onexa_sales_posting_runs') is not null
    ),
    (
      'authorization_has_module_action',
      to_regprocedure(
        'onexa_private.has_module_action(uuid,text,text)'
      ) is not null
    )
) as dependency(check_name, ready)
order by check_name;

create temporary table gate39_authorization_candidates (
  user_id uuid primary key,
  role_key text not null,
  can_create boolean not null,
  can_submit boolean not null,
  can_approve boolean not null,
  can_post boolean not null
) on commit drop;

do $authorization$
declare
  _candidate record;
begin
  for _candidate in
    select
      membership.user_id,
      membership.role_key
    from public.onexa_workspace_memberships membership
    join auth.users auth_user
      on auth_user.id = membership.user_id
    where membership.tenant_id = 'tenant-001-al-ostool'
      and membership.status = 'active'
      and membership.role_key in (
        'workspace_owner',
        'finance_manager',
        'accountant'
      )
    order by membership.role_key, membership.user_id
  loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', _candidate.user_id,
        'role', 'authenticated',
        'app_metadata', jsonb_build_object(
          'onexa_tenant_id',
          'tenant-001-al-ostool'
        )
      )::text,
      true
    );

    insert into gate39_authorization_candidates (
      user_id,
      role_key,
      can_create,
      can_submit,
      can_approve,
      can_post
    )
    values (
      _candidate.user_id,
      _candidate.role_key,
      coalesce(
        onexa_private.has_module_action(
          _candidate.user_id,
          'sales',
          'create'
        ),
        false
      ),
      coalesce(
        onexa_private.has_module_action(
          _candidate.user_id,
          'sales',
          'submit'
        ),
        false
      ),
      coalesce(
        onexa_private.has_module_action(
          _candidate.user_id,
          'sales',
          'approve'
        ),
        false
      ),
      coalesce(
        onexa_private.has_module_action(
          _candidate.user_id,
          'sales',
          'post'
        ),
        false
      )
    );
  end loop;
end;
$authorization$;

select
  candidate.user_id,
  candidate.role_key,
  candidate.can_create,
  candidate.can_submit,
  candidate.can_approve,
  candidate.can_post
from gate39_authorization_candidates candidate
order by candidate.role_key, candidate.user_id;

select
  count(*) filter (
    where can_create and can_submit
  ) as eligible_creators,
  count(*) filter (
    where can_approve and can_post
  ) as eligible_operators,
  exists (
    select 1
    from gate39_authorization_candidates creator
    cross join gate39_authorization_candidates operator
    where creator.user_id <> operator.user_id
      and creator.can_create
      and creator.can_submit
      and operator.can_approve
      and operator.can_post
  ) as distinct_creator_and_operator_ready
from gate39_authorization_candidates;

select
  mapping.account_role,
  mapping.account_code,
  account.name_ar,
  account.name_en,
  account.category,
  account.account_type,
  account.is_active,
  case
    when account.code is null then 'ACCOUNT_MISSING'
    when account.is_active is not true then 'ACCOUNT_INACTIVE'
    when account.account_type::text <> 'detail' then 'DETAIL_ACCOUNT_REQUIRED'
    when account.category::text <> 'assets' then 'ASSET_ACCOUNT_REQUIRED'
    else 'READY'
  end as status
from public.onexa_account_role_mappings mapping
left join public.chart_of_accounts account
  on account.tenant_id = mapping.tenant_id
 and account.code = mapping.account_code
where mapping.tenant_id = 'tenant-001-al-ostool'
  and mapping.legal_entity_id = '3ba2a953-db1d-4c1f-a192-c7343a93ab36'
  and mapping.account_role in (
    'accounts_receivable',
    'cash_or_bank'
  )
  and mapping.is_active is true
order by mapping.account_role;

select
  account.code,
  account.name_ar,
  account.name_en,
  account.category,
  account.account_type
from public.chart_of_accounts account
where account.tenant_id = 'tenant-001-al-ostool'
  and account.is_active is true
  and account.account_type::text = 'detail'
  and account.category::text = 'assets'
order by account.code;

select
  count(*) filter (
    where document.status = 'posted'
      and document.posted_journal_id is not null
      and document.branch_id is not null
      and document.party_type = 'customer'
      and document.party_id is not null
  ) as posted_sales_invoice_candidates,
  count(distinct document.created_by) as distinct_sales_invoice_creators,
  true as smoke_test_creates_temporary_sales_invoice,
  'INFORMATIONAL_ONLY'::text as candidate_count_status
from public.onexa_business_documents document
join public.onexa_sales_posting_runs posting
  on posting.document_id = document.id
 and posting.tenant_id = document.tenant_id
 and posting.journal_id = document.posted_journal_id
where document.tenant_id = 'tenant-001-al-ostool'
  and document.document_type = 'sales_invoice';

rollback;
