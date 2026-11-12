-- Two HR hardening fixes explicitly approved November 8, 2026.
-- Validated against a synthetic independent PostgreSQL harness.
CREATE OR REPLACE FUNCTION public.hr_termination_clearance(_employee_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_tenant TEXT := onexa_private.claim_tenant_id();
  loans_open INTEGER;
  assets_open INTEGER;
  loans_remaining NUMERIC;
BEGIN
  IF v_tenant IS NULL OR NOT onexa_private.is_active_member(auth.uid()) THEN
    RAISE EXCEPTION 'Active tenant membership required' USING ERRCODE = '42501';
  END IF;
  IF NOT (
    public.has_permission(auth.uid(), 'hr.termination', 'view')
    OR public.has_permission(auth.uid(), 'hr.termination', 'create')
    OR public.has_permission(auth.uid(), 'hr.termination', 'edit')
    OR public.has_permission(auth.uid(), 'hr.termination', 'approve')
    OR public.is_admin(auth.uid()) OR auth.role() = 'service_role'
  ) THEN
    RAISE EXCEPTION 'ليست لديك صلاحية الاطلاع على تسوية الموظف';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hr_employees WHERE id = _employee_id AND tenant_id = v_tenant) THEN
    RAISE EXCEPTION 'Employee not available in current tenant' USING ERRCODE = '42501';
  END IF;
  SELECT COUNT(*), COALESCE(SUM(GREATEST(amount - COALESCE(paid_amount, 0), 0)), 0)
  INTO loans_open, loans_remaining FROM public.hr_loans
  WHERE employee_id = _employee_id AND tenant_id = v_tenant AND status = 'active';
  SELECT COUNT(*) INTO assets_open FROM public.hr_assets_assignment
  WHERE employee_id = _employee_id AND tenant_id = v_tenant AND is_returned = false;
  RETURN jsonb_build_object('loans_open', loans_open, 'loans_remaining_amount', loans_remaining,
    'loans_settled_by_final_settlement', true, 'assets_not_returned', assets_open, 'can_terminate', assets_open = 0);
END $function$;
CREATE OR REPLACE FUNCTION public.hr_termination_refresh_components(_termination_id UUID)
RETURNS public.hr_terminations LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_tenant TEXT := onexa_private.claim_tenant_id();
  v_term public.hr_terminations;
  v_gross NUMERIC;
  v_service JSONB;
  v_leave_days NUMERIC;
  v_leave_override NUMERIC;
  v_loan_balance NUMERIC;
  v_row public.hr_terminations;
BEGIN
  IF v_tenant IS NULL OR NOT onexa_private.is_active_member(auth.uid()) THEN
    RAISE EXCEPTION 'Active tenant membership required' USING ERRCODE = '42501';
  END IF;
  IF NOT (
    public.has_permission(auth.uid(), 'hr.termination', 'edit')
    OR public.has_permission(auth.uid(), 'hr.termination', 'approve')
    OR public.has_permission(auth.uid(), 'hr.termination', 'create')
    OR public.is_admin(auth.uid()) OR auth.role() = 'service_role'
  ) THEN RAISE EXCEPTION 'ليست لديك صلاحية إعادة احتساب المخالصة'; END IF;
  SELECT * INTO v_term FROM public.hr_terminations
  WHERE id = _termination_id AND tenant_id = v_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ملف إنهاء الخدمة غير موجود'; END IF;
  IF v_term.status NOT IN ('draft', 'pending') THEN
    RAISE EXCEPTION 'لا يمكن إعادة احتساب مخالصة في الحالة (%)', v_term.status;
  END IF;
  SELECT COALESCE(gross_salary, COALESCE(basic_salary, 0) + COALESCE(housing_allowance, 0)
    + COALESCE(transport_allowance, 0) + COALESCE(other_allowances, 0), 0)
  INTO v_gross FROM public.hr_employees WHERE id = v_term.employee_id AND tenant_id = v_tenant;
  v_service := public.hr_calculate_service_period(v_term.employee_id, v_term.last_working_day);
  v_leave_override := NULLIF(v_term.settlement_details->>'leave_days_override', '')::NUMERIC;
  IF v_leave_override < 0 OR v_leave_override::TEXT IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'Invalid leave override' USING ERRCODE = '22023';
  END IF;
  v_leave_days := COALESCE(v_leave_override, public.hr_leave_accrued_for_settlement(v_term.employee_id, v_term.last_working_day));
  SELECT COALESCE(SUM(GREATEST(amount - COALESCE(paid_amount, 0), 0)), 0)
  INTO v_loan_balance FROM public.hr_loans
  WHERE employee_id = v_term.employee_id AND tenant_id = v_tenant AND status = 'active';
  UPDATE public.hr_terminations
  SET calendar_service_days = (v_service->>'calendar_days')::INTEGER,
    excluded_service_days = (v_service->>'excluded_days')::INTEGER,
    effective_service_days = (v_service->>'effective_days')::INTEGER,
    service_years = (v_service->>'effective_years')::NUMERIC,
    eos_amount = public.hr_calc_end_of_service(v_gross, (v_service->>'effective_years')::NUMERIC, v_term.reason::TEXT),
    leave_balance_days = ROUND(v_leave_days, 2),
    leave_balance_amount = ROUND(v_leave_days * (v_gross / 30.0), 2),
    loan_settlement = v_loan_balance,
    settlement_details = COALESCE(settlement_details, '{}'::JSONB) || jsonb_build_object(
      'service_period', v_service, 'calculation_version', 'termination-v2', 'calculated_at', now())
  WHERE id = _termination_id AND tenant_id = v_tenant RETURNING * INTO v_row;
  RETURN v_row;
END $function$;