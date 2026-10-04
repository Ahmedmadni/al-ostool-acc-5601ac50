import { supabase } from "@/integrations/supabase/client";
import {
  createBusinessDocument,
  listBusinessDocuments,
  transitionBusinessDocument,
  type BusinessDocumentListItem,
} from "@/lib/documents/business-document-service";
import { ONEXA_MAINTENANCE_COST_POSTING_ENABLED } from "@/lib/runtime-flags";

export type MaintenanceCostSource = "material" | "subcontract" | "labor" | "other";

export type MaintenanceWorkOrderOption = {
  id: string;
  work_order_no: string;
  title: string;
  status: "completed" | "accepted";
  asset_id: string | null;
};

export type MaintenanceProjectCenter = {
  id: string;
  legal_entity_id: string;
  branch_id: string;
  project_code: string;
  project_name: string;
  cost_center_code: string;
};

export type MaintenanceWorkOrderScope = {
  id: string;
  legal_entity_id: string;
  branch_id: string;
  work_order_id: string;
  work_order_no: string;
  work_order_title: string;
  work_order_status: "completed" | "accepted";
  asset_id: string | null;
  project_code: string;
  project_name: string;
  cost_center_code: string;
};

const CREDIT_ROLES: Record<MaintenanceCostSource, string> = {
  material: "maintenance_material_clearing",
  subcontract: "maintenance_subcontract_clearing",
  labor: "maintenance_labor_clearing",
  other: "maintenance_other_clearing",
};

export async function listCompletedMaintenanceWorkOrders(): Promise<MaintenanceWorkOrderOption[]> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("ops_work_orders")
    .select("id,work_order_no,title,status,asset_id")
    .in("status", ["completed", "accepted"])
    .order("actual_end", { ascending: false, nullsFirst: false }).limit(200);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listMaintenanceProjectCenters(): Promise<MaintenanceProjectCenter[]> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_project_cost_centers")
    .select("id,legal_entity_id,branch_id,project_code,project_name,cost_center_code")
    .eq("is_active", true).order("project_code").limit(200);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function saveMaintenanceWorkOrderScope(
  workOrderId: string,
  projectCostCenterId: string,
): Promise<string> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) throw new Error("ONEXA_MAINTENANCE_COST_POSTING_DISABLED");
  const { data, error } = await (supabase as any).rpc("onexa_save_maintenance_work_order_scope", {
    _work_order_id: workOrderId,
    _project_cost_center_id: projectCostCenterId,
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_MAINTENANCE_SCOPE_INVALID_RESPONSE");
  return data;
}

export async function listMaintenanceWorkOrderScopes(): Promise<MaintenanceWorkOrderScope[]> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_maintenance_work_order_cost_scopes")
    .select("id,legal_entity_id,branch_id,work_order_id,work_order_no,work_order_title,work_order_status,asset_id,project_code,project_name,cost_center_code")
    .order("work_order_no").limit(200);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listOnexaMaintenanceCosts(): Promise<BusinessDocumentListItem[]> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) return [];
  return (await listBusinessDocuments("projects", 200))
    .filter((document) => document.document_type === "maintenance_work_order_cost");
}

export async function createOnexaMaintenanceCost(input: {
  scope: MaintenanceWorkOrderScope;
  amount: number;
  source: MaintenanceCostSource;
  date: string;
  reference: string;
  description: string;
}): Promise<{ id: string; status: "submitted" | "draft" }> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) throw new Error("ONEXA_MAINTENANCE_COST_POSTING_DISABLED");
  if (!Number.isFinite(input.amount) || input.amount <= 0 ||
      Math.abs(Math.round(input.amount * 100) - input.amount * 100) > 1e-7) {
    throw new Error("ONEXA_MAINTENANCE_COST_AMOUNT_INVALID");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.date) || !input.reference.trim() || !input.description.trim()) {
    throw new Error("ONEXA_MAINTENANCE_COST_DETAILS_REQUIRED");
  }
  const dimensions = {
    project: input.scope.project_code,
    costCenter: input.scope.cost_center_code,
    ...(input.scope.asset_id ? { asset: input.scope.asset_id } : {}),
  };
  const id = await createBusinessDocument({
    legalEntityId: input.scope.legal_entity_id,
    branchId: input.scope.branch_id,
    module: "projects",
    documentType: "maintenance_work_order_cost",
    documentDate: input.date,
    accountingDate: input.date,
    currency: "SAR",
    externalReference: input.reference.trim(),
    subtotal: input.amount,
    taxTotal: 0,
    grossTotal: input.amount,
    memo: input.description.trim(),
    dimensions,
    sourceSnapshot: {
      maintenance_scope_id: input.scope.id,
      work_order_id: input.scope.work_order_id,
      work_order_no: input.scope.work_order_no,
      source_kind: "unpaid_maintenance_cost",
      cost_source: input.source,
    },
    lines: [{
      lineNumber: 1,
      description: input.description.trim(),
      quantity: 1,
      unitPrice: input.amount,
      netAmount: input.amount,
      taxAmount: 0,
      grossAmount: input.amount,
      accountRole: CREDIT_ROLES[input.source],
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

export async function postOnexaMaintenanceCost(documentId: string, periodCode: string): Promise<string> {
  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) throw new Error("ONEXA_MAINTENANCE_COST_POSTING_DISABLED");
  if (!/^\d{4}-\d{2}$/.test(periodCode.trim())) throw new Error("ONEXA_FISCAL_PERIOD_REQUIRED");
  const { data, error } = await (supabase as any).rpc("onexa_post_maintenance_work_order_cost", {
    _document_id: documentId,
    _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_MAINTENANCE_COST_INVALID_RESPONSE");
  return data;
}
