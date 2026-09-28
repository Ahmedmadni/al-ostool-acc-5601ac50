import { supabase } from "@/integrations/supabase/client";
import {
  getPostingContract,
  type AccountingDimension,
  type DocumentStatus,
  type SourceDocumentType,
} from "@/lib/accounting/posting-contracts";
import type { OnexaModuleKey } from "@/lib/onexa-product";

export type DocumentOrigin = "native" | "import" | "api";
export type DocumentPartyType = "customer" | "vendor" | "employee" | "other";

export type BusinessDocumentLineInput = {
  lineNumber: number;
  description: string;
  quantity: number;
  unitOfMeasure?: string;
  unitPrice: number;
  discountAmount?: number;
  netAmount: number;
  taxCode?: string;
  taxRate?: number;
  taxAmount?: number;
  grossAmount: number;
  itemId?: string;
  warehouseId?: string;
  accountRole?: string;
  dimensions?: Partial<Record<AccountingDimension, string>>;
};

export type CreateBusinessDocumentInput = {
  legalEntityId: string;
  branchId?: string;
  module: OnexaModuleKey;
  documentType: SourceDocumentType;
  documentDate: string;
  accountingDate: string;
  dueDate?: string;
  currency: string;
  party?: { type: DocumentPartyType; id: string; nameSnapshot?: string };
  externalReference?: string;
  origin?: DocumentOrigin;
  importBatchId?: string;
  subtotal: number;
  discountTotal?: number;
  taxTotal?: number;
  grossTotal: number;
  dimensions?: Partial<Record<AccountingDimension, string>>;
  sourceSnapshot?: Record<string, unknown>;
  memo?: string;
  lines: BusinessDocumentLineInput[];
};

export type BusinessDocumentListItem = {
  id: string;
  module_key: OnexaModuleKey;
  document_type: SourceDocumentType;
  document_number: string;
  document_date: string;
  accounting_date: string;
  status: DocumentStatus;
  currency: string;
  party_name_snapshot: string | null;
  gross_total: number;
  origin: DocumentOrigin;
  posted_journal_id: string | null;
  updated_at: string;
};

export type ApprovalInboxItem = Pick<BusinessDocumentListItem,
  "id" | "module_key" | "document_type" | "document_number" | "document_date" |
  "accounting_date" | "currency" | "party_name_snapshot" | "gross_total"
> & {
  legal_entity_id: string;
  branch_id: string | null;
  created_by: string;
  submitted_by: string;
  submitted_at: string;
  revision: number;
  approval_instance_id: string | null;
  current_step_order: number | null;
  current_step_name: string | null;
  current_action_key: "review" | "approve" | null;
  assignee_kind: "user" | "role" | "department" | "manager" | null;
  minimum_approvals: number;
  approvals_received: number;
  can_current_user_act: boolean;
};

export type AccountingInboxItem = Pick<BusinessDocumentListItem,
  "id" | "module_key" | "document_type" | "document_number" | "document_date" |
  "accounting_date" | "currency" | "party_name_snapshot" | "gross_total"
> & {
  legal_entity_id: string;
  branch_id: string | null;
  approved_by: string;
  approved_at: string;
  revision: number;
  approval_instance_id: string | null;
  posting_step_name: string | null;
  can_current_user_post: boolean;
};

const roundMoney = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;

function validateDocument(input: CreateBusinessDocumentInput) {
  const contract = getPostingContract(input.documentType);
  if (!contract || contract.module !== input.module) throw new Error("ONEXA_DOCUMENT_TYPE_MODULE_MISMATCH");
  if (!input.lines.length) throw new Error("ONEXA_DOCUMENT_LINES_REQUIRED");
  if (!/^[A-Z]{3}$/.test(input.currency.toUpperCase())) throw new Error("ONEXA_INVALID_CURRENCY");
  if ((input.origin ?? "native") === "import" && !input.importBatchId) throw new Error("ONEXA_IMPORT_BATCH_REQUIRED");

  const duplicateLine = input.lines.some((line, index) =>
    !Number.isInteger(line.lineNumber) || line.lineNumber < 1 ||
    input.lines.findIndex((candidate) => candidate.lineNumber === line.lineNumber) !== index,
  );
  if (duplicateLine) throw new Error("ONEXA_INVALID_OR_DUPLICATE_LINE_NUMBER");

  const invalidLine = input.lines.some((line) =>
    !line.description.trim() || line.quantity <= 0 || line.unitPrice < 0 ||
    line.netAmount < 0 || line.grossAmount < 0 || (line.taxAmount ?? 0) < 0 ||
    Math.abs(roundMoney(line.grossAmount) - roundMoney(line.netAmount + (line.taxAmount ?? 0))) > 0.01,
  );
  if (invalidLine) throw new Error("ONEXA_INVALID_DOCUMENT_LINE");

  const linesGross = roundMoney(input.lines.reduce((total, line) => total + line.grossAmount, 0));
  if (Math.abs(linesGross - roundMoney(input.grossTotal)) > 0.01) throw new Error("ONEXA_DOCUMENT_LINE_TOTAL_MISMATCH");
}

/** Creates the header, lines, sequence number, and audit event in one database transaction. */
export async function createBusinessDocument(input: CreateBusinessDocumentInput): Promise<string> {
  validateDocument(input);
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_create_business_document", {
    _legal_entity_id: input.legalEntityId,
    _branch_id: input.branchId ?? null,
    _module_key: input.module,
    _document_type: input.documentType,
    _document_date: input.documentDate,
    _accounting_date: input.accountingDate,
    _due_date: input.dueDate ?? null,
    _currency: input.currency.toUpperCase(),
    _party_type: input.party?.type ?? null,
    _party_id: input.party?.id ?? null,
    _party_name_snapshot: input.party?.nameSnapshot ?? null,
    _external_reference: input.externalReference ?? null,
    _origin: input.origin ?? "native",
    _import_batch_id: input.importBatchId ?? null,
    _subtotal: input.subtotal,
    _discount_total: input.discountTotal ?? 0,
    _tax_total: input.taxTotal ?? 0,
    _gross_total: input.grossTotal,
    _dimensions: input.dimensions ?? {},
    _source_snapshot: input.sourceSnapshot ?? {},
    _memo: input.memo ?? null,
    _lines: input.lines.map((line) => ({
      line_number: line.lineNumber,
      description: line.description.trim(),
      quantity: line.quantity,
      unit_of_measure: line.unitOfMeasure ?? null,
      unit_price: line.unitPrice,
      discount_amount: line.discountAmount ?? 0,
      net_amount: line.netAmount,
      tax_code: line.taxCode ?? null,
      tax_rate: line.taxRate ?? 0,
      tax_amount: line.taxAmount ?? 0,
      gross_amount: line.grossAmount,
      item_id: line.itemId ?? null,
      warehouse_id: line.warehouseId ?? null,
      account_role: line.accountRole ?? null,
      dimensions: line.dimensions ?? {},
    })),
  });
  if (error) throw new Error(error.message || "ONEXA_CREATE_DOCUMENT_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_CREATE_DOCUMENT_INVALID_RESPONSE");
  return data;
}

export async function transitionBusinessDocument(
  documentId: string,
  toStatus: Extract<DocumentStatus, "draft" | "submitted" | "approved" | "rejected" | "cancelled">,
  reason?: string,
): Promise<DocumentStatus> {
  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_transition_business_document", {
    _document_id: documentId,
    _to_status: toStatus,
    _reason: reason?.trim() || null,
  });
  if (error) throw new Error(error.message || "ONEXA_DOCUMENT_TRANSITION_FAILED");
  return data as DocumentStatus;
}

export async function listBusinessDocuments(module: OnexaModuleKey, limit = 100): Promise<BusinessDocumentListItem[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_business_documents")
    .select("id,module_key,document_type,document_number,document_date,accounting_date,status,currency,party_name_snapshot,gross_total,origin,posted_journal_id,updated_at")
    .eq("module_key", module)
    .order("document_date", { ascending: false })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_DOCUMENT_LIST_FAILED");
  return (data ?? []) as BusinessDocumentListItem[];
}

/** Submitted source documents waiting for an approver other than their creator. */
export async function listApprovalInbox(limit = 100): Promise<ApprovalInboxItem[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_approval_task_inbox")
    .select("id,legal_entity_id,branch_id,module_key,document_type,document_number,document_date,accounting_date,currency,party_name_snapshot,gross_total,created_by,submitted_by,submitted_at,revision,approval_instance_id,current_step_order,current_step_name,current_action_key,assignee_kind,minimum_approvals,approvals_received,can_current_user_act")
    .order("submitted_at", { ascending: true })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_APPROVAL_INBOX_FAILED");
  return (data ?? []) as ApprovalInboxItem[];
}

/** Approved, unposted source documents waiting for the accountant. */
export async function listAccountingInbox(limit = 100): Promise<AccountingInboxItem[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_accounting_inbox")
    .select("id,legal_entity_id,branch_id,module_key,document_type,document_number,document_date,accounting_date,currency,party_name_snapshot,gross_total,approved_by,approved_at,revision,approval_instance_id,posting_step_name,can_current_user_post")
    .order("approved_at", { ascending: true })
    .limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error(error.message || "ONEXA_ACCOUNTING_INBOX_FAILED");
  return (data ?? []) as AccountingInboxItem[];
}
