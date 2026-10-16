import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument } from "@/lib/documents/business-document-service";
import {
  ONEXA_NATIVE_UNPAID_SOURCES_ENABLED,
  ONEXA_PROJECT_COST_POSTING_ENABLED,
} from "@/lib/runtime-flags";

export type NativeUnpaidMaintenanceSource = {
  id: string;
  tenant_id: string;
  legal_entity_id: string;
  branch_id: string;
  work_order_id: string;
  project_cost_center_id: string;
  source_kind: "unbilled_subcontract" | "other_unpaid_direct";
  source_reference: string;
  amount: number | string;
  status: "pending_review" | "approved" | "rejected" | "linked";
  reviewed_by: string | null;
  linked_document_id: string | null;
  current_reconciliation_status: string;
};

const assertEnabled = () => {
  if (!ONEXA_NATIVE_UNPAID_SOURCES_ENABLED)
    throw new Error("ONEXA_NATIVE_UNPAID_MAINTENANCE_DISABLED");
};

export async function listNativeUnpaidMaintenanceSources(): Promise<NativeUnpaidMaintenanceSource[]> {
  if (!ONEXA_NATIVE_UNPAID_SOURCES_ENABLED) return [];
  const { data, error } = await (supabase as any)
    .from("onexa_native_maintenance_source_reconciliation")
    .select("id,tenant_id,legal_entity_id,branch_id,work_order_id,project_cost_center_id,source_kind,source_reference,amount,status,reviewed_by,linked_document_id,current_reconciliation_status")
    .order("id")
    .limit(100);
  if (error) throw new Error(error.message);
  return (data ?? []) as NativeUnpaidMaintenanceSource[];
}

export async function registerNativeUnpaidMaintenanceSource(input: {
  workOrderId: string;
  sourceKind: "unbilled_subcontract" | "other_unpaid_direct";
  reference: string;
  evidenceReference: string;
  amount: number;
}): Promise<string> {
  assertEnabled();
  if (!Number.isFinite(input.amount) || input.amount <= 0)
    throw new Error("ONEXA_NATIVE_UNPAID_COST_AMOUNT_INVALID");
  if (input.reference.trim().length < 5 || input.evidenceReference.trim().length < 5)
    throw new Error("ONEXA_NATIVE_UNPAID_EVIDENCE_REQUIRED");
  const { data, error } = await (supabase as any).rpc(
    "onexa_register_native_unpaid_maintenance_source",
    {
      _work_order_id: input.workOrderId,
      _source_kind: input.sourceKind,
      _source_reference: input.reference.toUpperCase().trim(),
      _amount: input.amount,
      _evidence_reference: input.evidenceReference.trim(),
    },
  );
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_NATIVE_UNPAID_SOURCE_INVALID_RESPONSE");
  return data;
}

export async function reviewNativeUnpaidMaintenanceSource(
  sourceId: string,
  approve: boolean,
  reason: string,
): Promise<string> {
  assertEnabled();
  if (!reason.trim()) throw new Error("ONEXA_NATIVE_UNPAID_REVIEW_REASON_REQUIRED");
  const { data, error } = await (supabase as any).rpc(
    "onexa_review_native_unpaid_maintenance_source",
    { _source_id: sourceId, _approve: approve, _reason: reason.trim() },
  );
  if (error) throw new Error(error.message);
  return data as string;
}

/** Final verification: only AFTER normal G42 approval/posting AND Gate74 attribution. */
export async function linkPostedNativeUnpaidMaintenanceSource(
  sourceId: string,
  postedDocumentId: string,
): Promise<string> {
  assertEnabled();
  const { data, error } = await (supabase as any).rpc(
    "onexa_link_native_unpaid_maintenance_source",
    { _source_id: sourceId, _document_id: postedDocumentId },
  );
  if (error) throw new Error(error.message);
  return data as string;
}

/**
 * Creates an ordinary G42 project-cost DRAFT (not approved/posted).
 * G75 trigger validates the reviewed source claim server-side. This does not
 * replace independent evidence review or the G42/G64 approval-post sequence.
 * Do not use for stock issues, wages, already invoiced subcontractors, or payroll.
 */
export async function prepareNativeUnpaidMaintenanceProjectCost(
  sourceId: string,
  accountingDate: string,
  description: string,
): Promise<string> {
  assertEnabled();
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED)
    throw new Error("ONEXA_GATE42_PROJECT_COST_NOT_ENABLED");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(accountingDate) || !description.trim())
    throw new Error("ONEXA_NATIVE_UNPAID_PROJECT_COST_DETAILS_REQUIRED");

  const db = supabase as any;
  const { data: source, error: sourceError } = await db
    .from("onexa_native_maintenance_source_reconciliation")
    .select("id,legal_entity_id,branch_id,project_cost_center_id,source_kind,source_reference,amount,status")
    .eq("id", sourceId).single();
  if (sourceError || !source || source.status !== "approved")
    throw new Error("ONEXA_NATIVE_UNPAID_SOURCE_NOT_APPROVED");

  const { data: center, error: centerError } = await db
    .from("onexa_project_cost_centers")
    .select("id,tenant_id,legal_entity_id,branch_id,project_code,cost_center_code,is_active")
    .eq("id", source.project_cost_center_id).single();
  if (centerError || !center || !center.is_active
      || center.legal_entity_id !== source.legal_entity_id
      || center.branch_id !== source.branch_id)
    throw new Error("ONEXA_NATIVE_UNPAID_PROJECT_CENTER_SCOPE_MISMATCH");

  const amount = Number(source.amount);
  if (!Number.isFinite(amount) || amount <= 0)
    throw new Error("ONEXA_NATIVE_UNPAID_AMOUNT_INVALID");

  const dimensions = { project: center.project_code, costCenter: center.cost_center_code };
  return createBusinessDocument({
    legalEntityId: source.legal_entity_id,
    branchId: source.branch_id,
    module: "projects",
    documentType: "project_cost",
    documentDate: accountingDate,
    accountingDate,
    currency: "SAR",
    externalReference: source.source_reference,
    subtotal: amount,
    grossTotal: amount,
    taxTotal: 0,
    memo: description.trim(),
    dimensions,
    sourceSnapshot: {
      source_kind: "unpaid_direct_cost",
      project_cost_center_id: center.id,
      maintenance_source_claim_id: source.id,
      maintenance_source_kind: source.source_kind,
    },
    lines: [{
      lineNumber: 1,
      description: description.trim(),
      quantity: 1,
      unitPrice: amount,
      netAmount: amount,
      taxAmount: 0,
      grossAmount: amount,
      dimensions,
    }],
  });
}
