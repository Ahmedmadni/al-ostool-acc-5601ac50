import { supabase } from "@/integrations/supabase/client";
import {
  createBusinessDocument,
  listBusinessDocuments,
  transitionBusinessDocument,
  type BusinessDocumentListItem,
} from "@/lib/documents/business-document-service";
import { ONEXA_LEASE_ACCOUNTING_ENABLED } from "@/lib/runtime-flags";

export type TenantLeaseOption = {
  id: string;
  lease_no: string;
  customer_id: string;
  monthly_rent: number;
  status: "approved" | "active";
  unit_code: string;
  property_id: string;
  property_code: string;
  property_name: string;
};

export type OnexaBranchOption = {
  id: string;
  legal_entity_id: string;
  code: string;
};

export type LeaseAccountingScope = {
  id: string;
  legal_entity_id: string;
  branch_id: string;
  branch_code: string;
  tenant_lease_id: string;
  lease_no: string;
  customer_id: string;
  customer_name: string;
  contract_id: string | null;
  property_id: string;
  property_code: string;
  property_name: string;
  unit_id: string;
  unit_code: string;
};

export type LeaseBillingCandidate = LeaseAccountingScope & {
  schedule_id: string;
  due_date: string;
  period_start: string;
  period_end: string;
  net_amount: number;
};

export type LeaseReceivable = {
  invoice_id: string;
  legal_entity_id: string;
  branch_id: string;
  customer_id: string;
  customer_name: string | null;
  document_number: string;
  currency: string;
  due_date: string;
  property_id: string;
  property_code: string;
  invoiced_amount: number;
  collected_amount: number;
  outstanding_amount: number;
  reconciliation_status: string;
};

const money = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;

export async function listActiveTenantLeases(): Promise<TenantLeaseOption[]> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return [];
  const { data, error } = await (supabase as any)
    .from("re_tenant_leases")
    .select("id,lease_no,customer_id,monthly_rent,status,unit:re_units!inner(id,unit_code,building:re_buildings!inner(property:re_properties!inner(id,property_code,name_ar)))")
    .in("status", ["approved", "active"])
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw new Error(error.message);
  return (data ?? []).map((row: any) => ({
    id: row.id,
    lease_no: row.lease_no,
    customer_id: row.customer_id,
    monthly_rent: Number(row.monthly_rent),
    status: row.status,
    unit_code: row.unit.unit_code,
    property_id: row.unit.building.property.id,
    property_code: row.unit.building.property.property_code,
    property_name: row.unit.building.property.name_ar,
  }));
}

export async function listOnexaBranches(): Promise<OnexaBranchOption[]> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_branches")
    .select("id,legal_entity_id,code").eq("is_active", true).order("code").limit(200);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function saveLeaseAccountingScope(tenantLeaseId: string, branchId: string): Promise<string> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) throw new Error("ONEXA_LEASE_ACCOUNTING_DISABLED");
  const { data, error } = await (supabase as any).rpc("onexa_save_lease_accounting_scope", {
    _tenant_lease_id: tenantLeaseId,
    _branch_id: branchId,
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_LEASE_SCOPE_INVALID_RESPONSE");
  return data;
}

export async function listLeaseAccountingScopes(): Promise<LeaseAccountingScope[]> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_lease_accounting_scope_details")
    .select("id,legal_entity_id,branch_id,branch_code,tenant_lease_id,lease_no,customer_id,customer_name,contract_id,property_id,property_code,property_name,unit_id,unit_code")
    .order("lease_no").limit(300);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listLeaseBillingCandidates(): Promise<LeaseBillingCandidate[]> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_lease_billing_candidates")
    .select("id,legal_entity_id,branch_id,branch_code,tenant_lease_id,lease_no,customer_id,customer_name,contract_id,property_id,property_code,property_name,unit_id,unit_code,schedule_id,due_date,period_start,period_end,net_amount")
    .order("due_date").limit(500);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listOnexaLeaseDocuments(): Promise<BusinessDocumentListItem[]> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return [];
  return (await listBusinessDocuments("facilities", 200))
    .filter((document) => document.document_type === "lease_invoice" || document.document_type === "lease_receipt");
}

export async function createOnexaLeaseInvoice(input: {
  candidate: LeaseBillingCandidate;
  documentDate: string;
  taxRate: 0 | 0.15;
  externalReference: string;
}): Promise<{ id: string; status: "submitted" | "draft" }> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) throw new Error("ONEXA_LEASE_ACCOUNTING_DISABLED");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.documentDate) || !input.externalReference.trim())
    throw new Error("ONEXA_LEASE_INVOICE_DETAILS_REQUIRED");
  const net = money(Number(input.candidate.net_amount));
  const tax = money(net * input.taxRate);
  const gross = money(net + tax);
  if (!Number.isFinite(net) || net <= 0) throw new Error("ONEXA_LEASE_INVOICE_AMOUNT_INVALID");
  const dimensions = {
    property: input.candidate.property_id,
    customer: input.candidate.customer_id,
    ...(input.candidate.contract_id ? { contract: input.candidate.contract_id } : {}),
  };
  const description = `إيجار ${input.candidate.property_code} / ${input.candidate.unit_code} للفترة ${input.candidate.period_start} - ${input.candidate.period_end}`;
  const id = await createBusinessDocument({
    legalEntityId: input.candidate.legal_entity_id,
    branchId: input.candidate.branch_id,
    module: "facilities",
    documentType: "lease_invoice",
    documentDate: input.documentDate,
    accountingDate: input.documentDate,
    dueDate: input.candidate.due_date < input.documentDate ? input.documentDate : input.candidate.due_date,
    currency: "SAR",
    party: { type: "customer", id: input.candidate.customer_id, nameSnapshot: input.candidate.customer_name },
    externalReference: input.externalReference.trim(),
    subtotal: net,
    taxTotal: tax,
    grossTotal: gross,
    memo: description,
    dimensions,
    sourceSnapshot: {
      lease_scope_id: input.candidate.id,
      schedule_id: input.candidate.schedule_id,
      tenant_lease_id: input.candidate.tenant_lease_id,
      property_id: input.candidate.property_id,
      source_kind: "tenant_lease_schedule",
    },
    lines: [{
      lineNumber: 1,
      description,
      quantity: 1,
      unitPrice: net,
      netAmount: net,
      taxCode: input.taxRate ? "VAT15" : "EXEMPT",
      taxRate: input.taxRate,
      taxAmount: tax,
      grossAmount: gross,
      accountRole: "rental_revenue",
      dimensions,
    }],
  });
  try {
    await transitionBusinessDocument(id, "submitted");
    return { id, status: "submitted" };
  } catch {
    return { id, status: "draft" };
  }
}

export async function listLeaseReceivables(): Promise<LeaseReceivable[]> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_lease_receivables_reconciliation")
    .select("invoice_id,legal_entity_id,branch_id,customer_id,customer_name,document_number,currency,due_date,property_id,property_code,invoiced_amount,collected_amount,outstanding_amount,reconciliation_status")
    .eq("reconciliation_status", "reconciled").gt("outstanding_amount", 0)
    .order("due_date").limit(500);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function createOnexaLeaseReceipt(input: {
  receivable: LeaseReceivable;
  amount: number;
  date: string;
  externalReference: string;
}): Promise<{ id: string; status: "submitted" | "draft" }> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) throw new Error("ONEXA_LEASE_ACCOUNTING_DISABLED");
  const amount = money(input.amount);
  if (!Number.isFinite(input.amount) || Math.abs(amount - input.amount) > 1e-7 ||
      amount <= 0 || amount > Number(input.receivable.outstanding_amount))
    throw new Error("ONEXA_LEASE_RECEIPT_AMOUNT_INVALID");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.date) || !input.externalReference.trim())
    throw new Error("ONEXA_LEASE_RECEIPT_DETAILS_REQUIRED");
  const description = `تحصيل إيجار للفاتورة ${input.receivable.document_number}`;
  const dimensions = { property: input.receivable.property_id, customer: input.receivable.customer_id };
  const id = await createBusinessDocument({
    legalEntityId: input.receivable.legal_entity_id,
    branchId: input.receivable.branch_id,
    module: "facilities",
    documentType: "lease_receipt",
    documentDate: input.date,
    accountingDate: input.date,
    currency: input.receivable.currency,
    party: { type: "customer", id: input.receivable.customer_id, nameSnapshot: input.receivable.customer_name ?? undefined },
    externalReference: input.externalReference.trim(),
    subtotal: amount,
    taxTotal: 0,
    grossTotal: amount,
    memo: description,
    dimensions,
    sourceSnapshot: { lease_invoice_id: input.receivable.invoice_id, source_kind: "lease_invoice_collection" },
    lines: [{ lineNumber: 1, description, quantity: 1, unitPrice: amount,
      netAmount: amount, taxAmount: 0, grossAmount: amount, dimensions }],
  });
  try {
    await transitionBusinessDocument(id, "submitted");
    return { id, status: "submitted" };
  } catch {
    return { id, status: "draft" };
  }
}

export async function postOnexaLeaseInvoice(documentId: string, periodCode: string): Promise<string> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) throw new Error("ONEXA_LEASE_ACCOUNTING_DISABLED");
  if (!/^\d{4}-\d{2}$/.test(periodCode.trim())) throw new Error("ONEXA_FISCAL_PERIOD_REQUIRED");
  const { data, error } = await (supabase as any).rpc("onexa_post_lease_invoice", {
    _document_id: documentId, _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_LEASE_INVOICE_POST_INVALID_RESPONSE");
  return data;
}

export async function postOnexaLeaseReceipt(documentId: string, periodCode: string): Promise<string> {
  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) throw new Error("ONEXA_LEASE_ACCOUNTING_DISABLED");
  if (!/^\d{4}-\d{2}$/.test(periodCode.trim())) throw new Error("ONEXA_FISCAL_PERIOD_REQUIRED");
  const { data, error } = await (supabase as any).rpc("onexa_post_lease_receipt", {
    _document_id: documentId, _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_LEASE_RECEIPT_POST_INVALID_RESPONSE");
  return data;
}
