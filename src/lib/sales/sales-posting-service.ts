import { supabase } from "@/integrations/supabase/client";
import { ONEXA_SALES_POSTING_ENABLED } from "@/lib/runtime-flags";

export type SalesPostingResult =
  | { status: "disabled"; code: "ONEXA_SALES_POSTING_DISABLED" }
  | { status: "posted"; journalId: string };

export type SalesInventoryReconciliation = {
  document_id: string;
  legal_entity_id: string;
  branch_id: string;
  document_number: string;
  document_date: string;
  currency: string;
  status: string;
  receivable_amount: number;
  revenue_amount: number;
  tax_amount: number;
  posted_inventory_cost: number;
  movement_inventory_cost: number;
  expected_movement_count: number;
  actual_movement_count: number;
  posted_journal_id: string | null;
  reconciliation_status: "not_posted" | "journal_missing" | "invoice_unbalanced" | "stock_movement_missing" | "inventory_value_mismatch" | "reconciled";
};

export type SalesPostingConfigurationGap = {
  legal_entity_id: string;
  legal_entity_code: string;
  account_role: string;
};

/**
 * Posts one approved sales invoice. The database owns account resolution,
 * weighted-average costing, stock locks, journal creation, and idempotency.
 */
export async function postSalesInvoice(documentId: string, periodCode: string): Promise<SalesPostingResult> {
  if (!ONEXA_SALES_POSTING_ENABLED) {
    return { status: "disabled", code: "ONEXA_SALES_POSTING_DISABLED" };
  }
  if (!documentId.trim()) throw new Error("ONEXA_DOCUMENT_REQUIRED");
  if (!periodCode.trim()) throw new Error("ONEXA_FISCAL_PERIOD_REQUIRED");

  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_sales_invoice", {
    _document_id: documentId,
    _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message || "ONEXA_SALES_POSTING_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_SALES_POSTING_INVALID_RESPONSE");
  return { status: "posted", journalId: data };
}

export async function fetchSalesInventoryReconciliation(limit = 200): Promise<SalesInventoryReconciliation[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_sales_inventory_reconciliation")
    .select("document_id,legal_entity_id,branch_id,document_number,document_date,currency,status,receivable_amount,revenue_amount,tax_amount,posted_inventory_cost,movement_inventory_cost,expected_movement_count,actual_movement_count,posted_journal_id,reconciliation_status")
    .order("document_date", { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_SALES_RECONCILIATION_FAILED");
  return (data ?? []) as SalesInventoryReconciliation[];
}

export async function fetchSalesPostingConfigurationGaps(): Promise<SalesPostingConfigurationGap[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_sales_posting_configuration_gaps")
    .select("legal_entity_id,legal_entity_code,account_role")
    .order("legal_entity_code")
    .order("account_role");
  if (error) throw new Error(error.message || "ONEXA_SALES_CONFIGURATION_GAPS_FAILED");
  return (data ?? []) as SalesPostingConfigurationGap[];
}
