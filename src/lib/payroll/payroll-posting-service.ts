import { supabase } from "@/integrations/supabase/client";
import { ONEXA_PAYROLL_POSTING_ENABLED } from "@/lib/runtime-flags";

export type PayrollPostingResult =
  | { status: "disabled"; code: "ONEXA_PAYROLL_POSTING_DISABLED" }
  | { status: "posted"; journalId: string };

export type PayrollAccountingReconciliation = {
  payroll_run_id: string;
  legal_entity_id: string | null;
  branch_id: string | null;
  run_no: string;
  period_year: number;
  period_month: number;
  payroll_status: string;
  employees_count: number;
  employer_cost: number;
  net_pay: number;
  gosi_payable: number;
  loan_recovery: number;
  cost_ledger_amount: number;
  cost_line_count: number;
  expected_cost_line_count: number;
  posted_journal_id: string | null;
  reconciliation_status: "not_approved" | "attendance_stale" | "cost_sync_pending" | "cost_value_mismatch" | "not_posted" | "journal_missing" | "journal_unbalanced" | "reconciled";
};

export type PayrollPostingConfigurationGap = {
  legal_entity_id: string;
  legal_entity_code: string;
  account_role: string;
};

export async function postPayrollRun(
  payrollRunId: string,
  legalEntityId: string,
  branchId: string,
  periodCode: string,
): Promise<PayrollPostingResult> {
  if (!ONEXA_PAYROLL_POSTING_ENABLED) {
    return { status: "disabled", code: "ONEXA_PAYROLL_POSTING_DISABLED" };
  }
  if (![payrollRunId, legalEntityId, branchId, periodCode].every((value) => value.trim())) {
    throw new Error("ONEXA_PAYROLL_POSTING_CONTEXT_REQUIRED");
  }
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_payroll_run", {
    _payroll_run_id: payrollRunId,
    _legal_entity_id: legalEntityId,
    _branch_id: branchId,
    _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message || "ONEXA_PAYROLL_POSTING_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_PAYROLL_POSTING_INVALID_RESPONSE");
  return { status: "posted", journalId: data };
}

export async function fetchPayrollAccountingReconciliation(limit = 200): Promise<PayrollAccountingReconciliation[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_payroll_accounting_reconciliation")
    .select("payroll_run_id,legal_entity_id,branch_id,run_no,period_year,period_month,payroll_status,employees_count,employer_cost,net_pay,gosi_payable,loan_recovery,cost_ledger_amount,cost_line_count,expected_cost_line_count,posted_journal_id,reconciliation_status")
    .order("period_year", { ascending: false })
    .order("period_month", { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_PAYROLL_RECONCILIATION_FAILED");
  return (data ?? []) as PayrollAccountingReconciliation[];
}

export async function fetchPayrollPostingConfigurationGaps(): Promise<PayrollPostingConfigurationGap[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_payroll_posting_configuration_gaps")
    .select("legal_entity_id,legal_entity_code,account_role")
    .order("legal_entity_code")
    .order("account_role");
  if (error) throw new Error(error.message || "ONEXA_PAYROLL_CONFIGURATION_GAPS_FAILED");
  return (data ?? []) as PayrollPostingConfigurationGap[];
}
