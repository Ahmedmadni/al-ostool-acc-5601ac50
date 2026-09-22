import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument, transitionBusinessDocument } from "@/lib/documents/business-document-service";
import { ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED } from "@/lib/runtime-flags";

export type Payable = {
  invoice_id: string;
  legal_entity_id: string;
  branch_id: string;
  vendor_id: string;
  document_number: string;
  currency: string;
  due_date: string | null;
  invoiced_amount: number;
  paid_amount: number;
  outstanding_amount: number;
  reconciliation_status: string;
};

export type PaymentDocument = {
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

export async function listOnexaPayables(): Promise<Payable[]> {
  if (!ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED) return [];
  const db = supabase as any;
  const { data, error } = await db.from("onexa_supplier_payables_reconciliation")
    .select("invoice_id,legal_entity_id,branch_id,vendor_id,document_number,currency,due_date,invoiced_amount,paid_amount,outstanding_amount,reconciliation_status")
    .eq("reconciliation_status", "reconciled")
    .gt("outstanding_amount", 0)
    .order("due_date", { ascending: true })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []) as Payable[];
}

export async function listOnexaPayments(): Promise<PaymentDocument[]> {
  if (!ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED) return [];
  const db = supabase as any;
  const { data, error } = await db.from("onexa_business_documents")
    .select("id,document_number,status,gross_total,currency,party_name_snapshot,accounting_date,created_by,posted_journal_id")
    .eq("document_type", "supplier_payment")
    .order("created_at", { ascending: false }).limit(100);
  if (error) throw new Error(error.message);
  return (data ?? []) as PaymentDocument[];
}

export async function createOnexaPayment(invoice: Payable, amount: number, date: string) {
  if (!ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED) throw new Error("ONEXA_PAYMENT_POSTING_DISABLED");
  if (invoice.reconciliation_status !== "reconciled" ||
      !Number.isFinite(amount) || amount <= 0 ||
      Math.abs(Math.round(amount * 100) - amount * 100) > 1e-7 ||
      amount > Number(invoice.outstanding_amount)) {
    throw new Error("ONEXA_PAYMENT_AMOUNT_INVALID");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("ONEXA_PAYMENT_DATE_INVALID");
  const id = await createBusinessDocument({
    legalEntityId: invoice.legal_entity_id,
    branchId: invoice.branch_id,
    module: "procurement",
    documentType: "supplier_payment",
    documentDate: date,
    accountingDate: date,
    currency: invoice.currency,
    party: { type: "vendor", id: invoice.vendor_id },
    subtotal: amount,
    taxTotal: 0,
    grossTotal: amount,
    sourceSnapshot: { invoice_allocations: [{ invoice_id: invoice.invoice_id, amount }] },
    memo: `Payment for ${invoice.document_number}`,
    lines: [{ lineNumber: 1, description: `Payment for ${invoice.document_number}`,
      quantity: 1, unitPrice: amount, netAmount: amount, taxAmount: 0, grossAmount: amount }],
  });
  await transitionBusinessDocument(id, "submitted");
  return id;
}

export async function approveOnexaPayment(id: string) {
  if (!ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED) throw new Error("ONEXA_PAYMENT_POSTING_DISABLED");
  return transitionBusinessDocument(id, "approved");
}

export async function postOnexaPayment(id: string, accountingDate: string): Promise<string> {
  if (!ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED) throw new Error("ONEXA_PAYMENT_POSTING_DISABLED");
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_supplier_payment", {
    _document_id: id, _period_code: accountingDate.slice(0, 7),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_PAYMENT_POST_INVALID_RESPONSE");
  return data;
}
