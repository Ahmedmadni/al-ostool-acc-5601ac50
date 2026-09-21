import { supabase } from "@/integrations/supabase/client";
import { ONEXA_PROCUREMENT_POSTING_ENABLED } from "@/lib/runtime-flags";

export type PurchasePostingResult =
  | { status: "disabled"; code: "ONEXA_PROCUREMENT_POSTING_DISABLED" }
  | { status: "posted"; journalId: string };

export type PurchaseInventoryReconciliation = {
  document_id: string;
  legal_entity_id: string;
  branch_id: string;
  document_number: string;
  document_date: string;
  due_date: string | null;
  currency: string;
  status: string;
  payable_amount: number;
  net_purchase_amount: number;
  tax_amount: number;
  posted_inventory_amount: number;
  movement_inventory_amount: number;
  expense_amount: number;
  asset_amount: number;
  expected_movement_count: number;
  actual_movement_count: number;
  posted_journal_id: string | null;
  reconciliation_status: "not_posted" | "journal_missing" | "invoice_unbalanced" | "stock_movement_missing" | "inventory_value_mismatch" | "classification_mismatch" | "reconciled";
};

export type PurchasePostingConfigurationGap = {
  legal_entity_id: string;
  legal_entity_code: string;
  account_role: string;
};

/** Posts one approved purchase invoice atomically into AP, VAT, inventory and GL. */
export async function postPurchaseInvoice(documentId: string, periodCode: string): Promise<PurchasePostingResult> {
  if (!ONEXA_PROCUREMENT_POSTING_ENABLED) {
    return { status: "disabled", code: "ONEXA_PROCUREMENT_POSTING_DISABLED" };
  }
  if (!documentId.trim()) throw new Error("ONEXA_DOCUMENT_REQUIRED");
  if (!periodCode.trim()) throw new Error("ONEXA_FISCAL_PERIOD_REQUIRED");

  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_purchase_invoice", {
    _document_id: documentId,
    _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message || "ONEXA_PURCHASE_POSTING_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_PURCHASE_POSTING_INVALID_RESPONSE");
  return { status: "posted", journalId: data };
}

export async function fetchPurchaseInventoryReconciliation(limit = 200): Promise<PurchaseInventoryReconciliation[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_purchase_inventory_reconciliation")
    .select("document_id,legal_entity_id,branch_id,document_number,document_date,due_date,currency,status,payable_amount,net_purchase_amount,tax_amount,posted_inventory_amount,movement_inventory_amount,expense_amount,asset_amount,expected_movement_count,actual_movement_count,posted_journal_id,reconciliation_status")
    .order("document_date", { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_PURCHASE_RECONCILIATION_FAILED");
  return (data ?? []) as PurchaseInventoryReconciliation[];
}

export async function fetchPurchasePostingConfigurationGaps(): Promise<PurchasePostingConfigurationGap[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_purchase_posting_configuration_gaps")
    .select("legal_entity_id,legal_entity_code,account_role")
    .order("legal_entity_code")
    .order("account_role");
  if (error) throw new Error(error.message || "ONEXA_PURCHASE_CONFIGURATION_GAPS_FAILED");
  return (data ?? []) as PurchasePostingConfigurationGap[];
}
