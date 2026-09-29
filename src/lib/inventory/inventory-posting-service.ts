import { supabase } from "@/integrations/supabase/client";
import {
  createBusinessDocument,
  listBusinessDocuments,
  transitionBusinessDocument,
  type BusinessDocumentListItem,
} from "@/lib/documents/business-document-service";
import { ONEXA_INVENTORY_POSTING_ENABLED } from "@/lib/runtime-flags";

export type InventoryDocumentKind = "receipt" | "issue";

export type InventoryDocumentLine = {
  itemId: string;
  itemLabel: string;
  warehouseId: string;
  quantity: number;
  unitCost: number;
  unitOfMeasure?: string;
  costCenter?: string;
};

export type CreateInventoryDocumentInput = {
  kind: InventoryDocumentKind;
  legalEntityId: string;
  branchId: string;
  date: string;
  currency?: string;
  reference?: string;
  memo?: string;
  costCenter?: string;
  lines: InventoryDocumentLine[];
};

const money = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;

export async function listOnexaInventoryDocuments(kind: InventoryDocumentKind): Promise<BusinessDocumentListItem[]> {
  if (!ONEXA_INVENTORY_POSTING_ENABLED) return [];
  const type = kind === "receipt" ? "inventory_receipt" : "inventory_issue";
  return (await listBusinessDocuments("inventory", 200)).filter((document) => document.document_type === type);
}

export async function createOnexaInventoryDocument(
  input: CreateInventoryDocumentInput,
): Promise<{ id: string; status: "submitted" | "draft" }> {
  if (!ONEXA_INVENTORY_POSTING_ENABLED) throw new Error("ONEXA_INVENTORY_POSTING_DISABLED");
  if (!input.legalEntityId || !input.branchId || !/^\d{4}-\d{2}-\d{2}$/.test(input.date)) {
    throw new Error("ONEXA_INVENTORY_SCOPE_REQUIRED");
  }
  if (!input.lines.length) throw new Error("ONEXA_DOCUMENT_LINES_REQUIRED");
  if (input.kind === "issue" && !input.costCenter?.trim()) {
    throw new Error("ONEXA_INVENTORY_ISSUE_COST_CENTER_REQUIRED");
  }
  const invalid = input.lines.some((line) =>
    !line.itemId || !line.warehouseId || !Number.isFinite(line.quantity) || line.quantity <= 0 ||
    !Number.isFinite(line.unitCost) || line.unitCost <= 0,
  );
  if (invalid) throw new Error("ONEXA_INVENTORY_LINE_INVALID");

  const totals = input.lines.map((line) => money(line.quantity * line.unitCost));
  const total = money(totals.reduce((sum, value) => sum + value, 0));
  const documentId = await createBusinessDocument({
    legalEntityId: input.legalEntityId,
    branchId: input.branchId,
    module: "inventory",
    documentType: input.kind === "receipt" ? "inventory_receipt" : "inventory_issue",
    documentDate: input.date,
    accountingDate: input.date,
    currency: input.currency ?? "SAR",
    externalReference: input.reference?.trim() || undefined,
    subtotal: total,
    taxTotal: 0,
    grossTotal: total,
    dimensions: input.costCenter?.trim() ? { costCenter: input.costCenter.trim() } : {},
    sourceSnapshot: {
      source_kind: input.kind === "receipt" ? "native_inventory_receipt" : "native_inventory_issue",
      valuation_method: "moving_weighted_average",
      issue_value_is_estimate: input.kind === "issue",
    },
    memo: input.memo?.trim() || undefined,
    lines: input.lines.map((line, index) => ({
      lineNumber: index + 1,
      description: line.itemLabel,
      quantity: line.quantity,
      unitOfMeasure: line.unitOfMeasure,
      unitPrice: line.unitCost,
      netAmount: totals[index],
      taxAmount: 0,
      grossAmount: totals[index],
      itemId: line.itemId,
      warehouseId: line.warehouseId,
      accountRole: input.kind === "receipt" ? "inventory" : "project_cost_cogs_or_expense",
      dimensions: line.costCenter?.trim() || input.costCenter?.trim()
        ? { costCenter: line.costCenter?.trim() || input.costCenter?.trim() }
        : {},
    })),
  });
  try {
    await transitionBusinessDocument(documentId, "submitted");
    return { id: documentId, status: "submitted" };
  } catch {
    return { id: documentId, status: "draft" };
  }
}

export async function postOnexaInventoryDocument(documentId: string, periodCode: string): Promise<string> {
  if (!ONEXA_INVENTORY_POSTING_ENABLED) throw new Error("ONEXA_INVENTORY_POSTING_DISABLED");
  if (!/^\d{4}-\d{2}$/.test(periodCode.trim())) throw new Error("ONEXA_FISCAL_PERIOD_REQUIRED");
  const { data, error } = await (supabase as any).rpc("onexa_post_inventory_document", {
    _document_id: documentId,
    _period_code: periodCode.trim(),
  });
  if (error) throw new Error(error.message || "ONEXA_INVENTORY_POSTING_FAILED");
  if (typeof data !== "string" || !data) throw new Error("ONEXA_INVENTORY_POSTING_INVALID_RESPONSE");
  return data;
}
