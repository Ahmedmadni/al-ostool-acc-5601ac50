-- Gate 82: diagnostic ONLY. No deployment, database mutation, or signoff.
-- Output contains metadata only, with no customer documents or journal values.
WITH required(stage, signature) AS (
 VALUES
 ('BASE','public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)'),
 ('G63','onexa_private.approval_actor_matches_step(uuid,uuid,uuid)'),
 ('G63','public.onexa_approval_separation_required(text,text)'),
 ('G35','public.onexa_post_sales_invoice(uuid,text)'),
 ('G36','public.onexa_post_purchase_invoice(uuid,text)'),
 ('G39','public.onexa_post_customer_receipt(uuid,text)'),
 ('G40','public.onexa_post_supplier_payment(uuid,text)'),
 ('G41','public.onexa_post_bank_transfer(uuid,text)'),
 ('G42','public.onexa_post_project_cost(uuid,text)'),
 ('G43','public.onexa_post_fleet_trip_cost(uuid,text)'),
 ('G64','onexa_private.guard_approval_posting()'),
 ('G64','onexa_private.finalize_approval_posting()'),
 ('G64','public.onexa_can_post_business_document(uuid)')
)
SELECT stage, signature,
 CASE WHEN to_regprocedure(signature) IS NOT NULL THEN 'PRESENT'
 ELSE 'MISSING' END AS installation_status,
 'FUNCTION_PRESENCE_ONLY_NOT_DEPLOYMENT_APPROVAL' AS limitation
FROM required ORDER BY stage,signature;

-- Confirm that all mandatory approval tables exist without accessing rows.
WITH required(name) AS (
 VALUES
 ('public.onexa_approval_workflows'),
 ('public.onexa_approval_workflow_steps'),
 ('public.onexa_approval_instances'),
 ('public.onexa_approval_decisions'),
 ('public.onexa_business_documents'),
 ('public.onexa_account_role_mappings'),
 ('public.onexa_project_cost_centers'),
 ('public.onexa_project_cost_postings')
)
SELECT name,
 CASE WHEN to_regclass(name) IS NOT NULL THEN 'PRESENT' ELSE 'MISSING' END AS installation_status
FROM required ORDER BY name;

-- Show whether the approval-aware computed inbox columns exist.
WITH required(column_name) AS (
 VALUES ('approval_instance_id'), ('posting_step_name'), ('can_current_user_post')
)
SELECT e.column_name,
 CASE WHEN c.column_name IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS installation_status
FROM required e LEFT JOIN information_schema.columns c
 ON c.table_schema='public' AND c.table_name='onexa_accounting_inbox'
 AND c.column_name=e.column_name ORDER BY e.column_name;

-- Grants and RLS status are advisory observations, NOT proof of effective row isolation.
SELECT cls.relname AS table_name, cls.relrowsecurity AS rls_enabled,
 cls.relforcerowsecurity AS force_rls, count(pol.policyname) AS policy_count
FROM pg_catalog.pg_class cls
JOIN pg_catalog.pg_namespace ns ON ns.oid=cls.relnamespace
LEFT JOIN pg_catalog.pg_policies pol ON pol.schemaname=ns.nspname AND pol.tablename=cls.relname
WHERE ns.nspname='public' AND cls.relkind IN ('r','p') AND cls.relname IN
 ('onexa_business_documents','onexa_approval_instances','onexa_project_cost_postings')
GROUP BY cls.relname,cls.relrowsecurity,cls.relforcerowsecurity ORDER BY cls.relname;
