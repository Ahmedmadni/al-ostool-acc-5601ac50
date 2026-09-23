import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument, transitionBusinessDocument } from "@/lib/documents/business-document-service";
import { ONEXA_PROJECT_COST_POSTING_ENABLED } from "@/lib/runtime-flags";

export type ProjectCostCenter = {
  id: string;
  legal_entity_id: string;
  branch_id: string;
  project_code: string;
  project_name: string;
  cost_center_code: string;
};

export type ProjectCostDocument = {
  id: string;
  document_number: string;
  status: string;
  gross_total: number;
  accounting_date: string;
  created_by: string;
  external_reference: string;
};

export async function listProjectCostCenters(): Promise<ProjectCostCenter[]> {
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_project_cost_centers")
    .select("id,legal_entity_id,branch_id,project_code,project_name,cost_center_code")
    .eq("is_active", true).order("project_code").limit(200);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function listOnexaProjectCosts(): Promise<ProjectCostDocument[]> {
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_business_documents")
    .select("id,document_number,status,gross_total,accounting_date,created_by,external_reference")
    .eq("document_type", "project_cost").order("created_at", { ascending: false }).limit(100);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function createOnexaProjectCost(
  center: ProjectCostCenter, amount: number, date: string, reference: string, description: string,
) {
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED) throw new Error("ONEXA_PROJECT_COST_POSTING_DISABLED");
  if (!Number.isFinite(amount) || amount <= 0 || Math.abs(Math.round(amount * 100) - amount * 100) > 1e-7)
    throw new Error("ONEXA_PROJECT_COST_AMOUNT_INVALID");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !reference.trim() || !description.trim())
    throw new Error("ONEXA_PROJECT_COST_DETAILS_REQUIRED");
  const id = await createBusinessDocument({
    legalEntityId: center.legal_entity_id, branchId: center.branch_id,
    module: "projects", documentType: "project_cost",
    documentDate: date, accountingDate: date, currency: "SAR",
    subtotal: amount, grossTotal: amount, taxTotal: 0,
    externalReference: reference.trim(), memo: description.trim(),
    dimensions: { project: center.project_code, costCenter: center.cost_center_code },
    sourceSnapshot: { project_cost_center_id: center.id, source_kind: "unpaid_direct_cost" },
    lines: [{ lineNumber: 1, description: description.trim(), quantity: 1,
      unitPrice: amount, netAmount: amount, taxAmount: 0, grossAmount: amount }],
  });
  await transitionBusinessDocument(id, "submitted");
  return id;
}

export async function approveOnexaProjectCost(id: string) {
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED) throw new Error("ONEXA_PROJECT_COST_POSTING_DISABLED");
  return transitionBusinessDocument(id, "approved");
}

export async function postOnexaProjectCost(id: string, accountingDate: string): Promise<string> {
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED) throw new Error("ONEXA_PROJECT_COST_POSTING_DISABLED");
  const { data, error } = await (supabase as any).rpc("onexa_post_project_cost", {
    _document_id: id, _period_code: accountingDate.slice(0, 7),
  });
  if (error) throw new Error(error.message);
  if (typeof data !== "string" || !data) throw new Error("ONEXA_PROJECT_COST_INVALID_RESPONSE");
  return data;
}
