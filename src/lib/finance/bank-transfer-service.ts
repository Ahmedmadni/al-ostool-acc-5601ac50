import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument, transitionBusinessDocument } from "@/lib/documents/business-document-service";
import { ONEXA_BANK_TRANSFER_POSTING_ENABLED } from "@/lib/runtime-flags";

export type TreasuryAccount = {
  id: string;
  legal_entity_id: string;
  branch_id: string;
  account_code: string;
  display_name: string;
  currency: string;
};

export type BankTransferDocument = {
  id: string;
  document_number: string;
  status: string;
  gross_total: number;
  accounting_date: string;
  created_by: string;
  posted_journal_id: string | null;
};

export async function listTreasuryAccounts(): Promise<TreasuryAccount[]> {
  if (!ONEXA_BANK_TRANSFER_POSTING_ENABLED) return [];
  const db = supabase as any;
  const { data, error } = await db.from("onexa_treasury_accounts")
    .select("id,legal_entity_id,branch_id,account_code,display_name,currency")
    .eq("is_active", true).order("display_name").limit(200);
  if (error) throw new Error(error.message);
  return (data ?? []) as TreasuryAccount[];
}

export async function listOnexaBankTransfers(): Promise<BankTransferDocument[]> {
  if (!ONEXA_BANK_TRANSFER_POSTING_ENABLED) return [];
  const db = supabase as any;
  const { data, error } = await db.from("onexa_business_documents")
    .select("id,document_number,status,gross_total,accounting_date,created_by,posted_journal_id")
    .eq("document_type", "bank_transfer")
    .order("created_at", { ascending: false }).limit(100);
  if (error) throw new Error(error.message);
  return (data ?? []) as BankTransferDocument[];
}

export async function createOnexaBankTransfer(
  source: TreasuryAccount, destination: TreasuryAccount,
  amount: number, date: string,
) {
  if (!ONEXA_BANK_TRANSFER_POSTING_ENABLED) throw new Error("ONEXA_BANK_TRANSFER_POSTING_DISABLED");
  if (source.id === destination.id || source.account_code === destination.account_code
    || source.legal_entity_id !== destination.legal_entity_id
    || source.branch_id !== destination.branch_id
    || source.currency !== "SAR" || destination.currency !== "SAR") {
    throw new Error("ONEXA_BANK_TRANSFER_ACCOUNT_SCOPE_INVALID");
  }
  if (!Number.isFinite(amount) || amount <= 0
    || Math.abs(Math.round(amount * 100) - amount * 100) > 1e-7) {
    throw new Error("ONEXA_BANK_TRANSFER_AMOUNT_INVALID");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("ONEXA_BANK_TRANSFER_DATE_INVALID");
  const id = await createBusinessDocument({
    legalEntityId: source.legal_entity_id,
    branchId: source.branch_id,
    module: "finance",
    documentType: "bank_transfer",
    documentDate: date,
    accountingDate: date,
    currency: "SAR",
    subtotal: amount,
    grossTotal: amount,
    taxTotal: 0,
    sourceSnapshot: { source_account_id: source.id, destination_account_id: destination.id },
    memo: `Bank transfer: ${source.display_name} → ${destination.display_name}`,
    lines: [{ lineNumber: 1, description: "Bank transfer", quantity: 1,
      unitPrice: amount, netAmount: amount, taxAmount: 0, grossAmount: amount }],
  });
  await transitionBusinessDocument(id, "submitted");
  return id;
}

export async function approveOnexaBankTransfer(id: string) {
  if (!ONEXA_BANK_TRANSFER_POSTING_ENABLED) throw new Error("ONEXA_BANK_TRANSFER_POSTING_DISABLED");
  return transitionBusinessDocument(id, "approved");
}

export async function postOnexaBankTransfer(id: string, accountingDate: string): Promise<string> {
  if (!ONEXA_BANK_TRANSFER_POSTING_ENABLED) throw new Error("ONEXA_BANK_TRANSFER_POSTING_DISABLED");
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_bank_transfer", {
    _document_id: id, _period_code: accountingDate.slice(0, 7),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_BANK_TRANSFER_INVALID_RESPONSE");
  return data;
}
