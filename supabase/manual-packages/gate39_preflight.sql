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

select
  membership.user_id,
  membership.role_key,
  onexa_private.has_module_action(
    membership.user_id,
    'sales',
    'create'
  ) as can_create,
  onexa_private.has_module_action(
    membership.user_id,
    'sales',
    'submit'
  ) as can_submit,
  onexa_private.has_module_action(
    membership.user_id,
    'sales',
    'approve'
  ) as can_approve,
  onexa_private.has_module_action(
    membership.user_id,
    'sales',
    'post'
  ) as can_post
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
order by membership.role_key, membership.user_id;

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
  count(distinct document.created_by) as distinct_sales_invoice_creators
from public.onexa_business_documents document
join public.onexa_sales_posting_runs posting
  on posting.document_id = document.id
 and posting.tenant_id = document.tenant_id
 and posting.journal_id = document.posted_journal_id
where document.tenant_id = 'tenant-001-al-ostool'
  and document.document_type = 'sales_invoice';

rollback;
