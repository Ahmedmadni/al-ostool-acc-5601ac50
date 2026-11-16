DROP POLICY IF EXISTS hr_wf_insert ON public.hr_workflow_requests;
CREATE POLICY hr_wf_insert ON public.hr_workflow_requests FOR INSERT TO authenticated
WITH CHECK (requested_by = auth.uid() OR public.has_permission(auth.uid(), 'hr.workflow'::text, 'create'::text) OR public.is_admin(auth.uid()));