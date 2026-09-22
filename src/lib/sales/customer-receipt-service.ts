import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument, transitionBusinessDocument } from "@/lib/documents/business-document-service";
import { ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED } from "@/lib/runtime-flags";

export type Receivable = {
  invoice_id: string;
  legal_entity_id: string;
  branch_id: string;
  customer_id: string;
  document_number: string;
  currency: string;
  due_date: string | null;
  invoiced_amount: number;
  collected_amount: number;
  outstanding_amount: number;
  reconciliation_status: string;
};

export type ReceiptDocument = {
  id: string;
  document_number: string;
  status: string;
  gross_total: number;
  currency: string;
  party_name_snapshot: string | null;
  accounting_date: string;
  created_by: string;
  posted_journal_id: string | null;
};

export async function listOnexaReceivables(): Promise<Receivable[]> {
  if (!ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED) return [];
  const db = supabase as any;
  const { data, error } = await db.from("onexa_customer_receivables_reconciliation")
    .select("invoice_id,legal_entity_id,branch_id,customer_id,document_number,currency,due_date,invoiced_amount,collected_amount,outstanding_amount,reconciliation_status")
    .eq("reconciliation_status", "reconciled")
    .gt("outstanding_amount", 0)
    .order("due_date", { ascending: true })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []) as Receivable[];
}

export async function listOnexaReceipts(): Promise<ReceiptDocument[]> {
  if (!ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED) return [];
  const db = supabase as any;
  const { data, error } = await db.from("onexa_business_documents")
    .select("id,document_number,status,gross_total,currency,party_name_snapshot,accounting_date,created_by,posted_journal_id")
    .eq("document_type", "customer_receipt")
    .order("created_at", { ascending: false }).limit(100);
  if (error) throw new Error(error.message);
  return (data ?? []) as ReceiptDocument[];
}

export async function createOnexaReceipt(invoice: Receivable, amount: number, date: string) {
  if (!ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED) throw new Error("ONEXA_RECEIPT_POSTING_DISABLED");
  if (invoice.reconciliation_status !== "reconciled" ||
      !Number.isFinite(amount) || amount <= 0 ||
      Math.abs(Math.round(amount * 100) - amount * 100) > 1e-7 ||
      amount > Number(invoice.outstanding_amount)) {
    throw new Error("ONEXA_RECEIPT_AMOUNT_INVALID");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("ONEXA_RECEIPT_DATE_INVALID");
  const id = await createBusinessDocument({
    legalEntityId: invoice.legal_entity_id,
    branchId: invoice.branch_id,
    module: "sales",
    documentType: "customer_receipt",
    documentDate: date,
    accountingDate: date,
    currency: invoice.currency,
    party: { type: "customer", id: invoice.customer_id },
    subtotal: amount,
    taxTotal: 0,
    grossTotal: amount,
    sourceSnapshot: { invoice_allocations: [{ invoice_id: invoice.invoice_id, amount }] },
    memo: `Collection for ${invoice.document_number}`,
    lines: [{ lineNumber: 1, description: `Collection for ${invoice.document_number}`,
      quantity: 1, unitPrice: amount, netAmount: amount, taxAmount: 0, grossAmount: amount }],
  });
  await transitionBusinessDocument(id, "submitted");
  return id;
}

export async function approveOnexaReceipt(id: string) {
  if (!ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED) throw new Error("ONEXA_RECEIPT_POSTING_DISABLED");
  return transitionBusinessDocument(id, "approved");
}

export async function postOnexaReceipt(id: string, accountingDate: string): Promise<string> {
  if (!ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED) throw new Error("ONEXA_RECEIPT_POSTING_DISABLED");
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_customer_receipt", {
    _document_id: id, _period_code: accountingDate.slice(0, 7),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_RECEIPT_POST_INVALID_RESPONSE");
  return data;
}
