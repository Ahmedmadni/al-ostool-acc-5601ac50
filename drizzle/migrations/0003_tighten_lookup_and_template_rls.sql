DROP POLICY IF EXISTS pa_read ON public.permission_actions;
CREATE POLICY pa_read ON public.permission_actions FOR SELECT TO authenticated
  USING (tenant_id = onexa_private.claim_tenant_id() AND onexa_private.is_active_member(auth.uid()));
DROP POLICY IF EXISTS jt_read ON public.job_titles;
CREATE POLICY jt_read ON public.job_titles FOR SELECT TO authenticated
  USING (tenant_id = onexa_private.claim_tenant_id() AND onexa_private.is_active_member(auth.uid()));
DROP POLICY IF EXISTS pm_read ON public.permission_modules;
CREATE POLICY pm_read ON public.permission_modules FOR SELECT TO authenticated
  USING (tenant_id = onexa_private.claim_tenant_id() AND onexa_private.is_active_member(auth.uid()));
DROP POLICY IF EXISTS data_templates_select ON public.data_templates;
CREATE POLICY data_templates_select ON public.data_templates FOR SELECT TO authenticated
  USING (tenant_id = onexa_private.claim_tenant_id() AND onexa_private.is_active_member(auth.uid()));
DROP POLICY IF EXISTS data_templates_insert ON public.data_templates;
CREATE POLICY data_templates_insert ON public.data_templates FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid() AND tenant_id = onexa_private.claim_tenant_id());
DROP POLICY IF EXISTS data_templates_update ON public.data_templates;
CREATE POLICY data_templates_update ON public.data_templates FOR UPDATE TO authenticated
  USING (created_by = auth.uid() OR public.is_admin(auth.uid()))
  WITH CHECK (created_by = auth.uid() OR public.is_admin(auth.uid()));
DROP POLICY IF EXISTS data_templates_delete ON public.data_templates;
CREATE POLICY data_templates_delete ON public.data_templates FOR DELETE TO authenticated
  USING (created_by = auth.uid() OR public.is_admin(auth.uid()));