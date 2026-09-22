import { supabase } from "@/integrations/supabase/client";
import { ONEXA_ASSET_POSTING_ENABLED } from "@/lib/runtime-flags";

export type AssetDepreciationPostingResult =
  | { status: "disabled"; code: "ONEXA_ASSET_POSTING_DISABLED" }
  | { status: "posted"; journalId: string };

export type AssetAccountingReconciliation = {
  asset_id: string;
  tenant_id: string;
  legal_entity_id: string | null;
  branch_id: string | null;
  asset_code: string | null;
  asset_name: string;
  category: string | null;
  project_id: string | null;
  department_id: string | null;
  purchase_date: string | null;
  depreciation_start_date: string | null;
  depreciation_method: string;
  cost: number;
  salvage_value: number;
  annual_depreciation: number;
  opening_accumulated_depreciation: number;
  accumulated_depreciation: number;
  net_book_value: number;
  posted_periods: number;
  gate38_depreciation: number;
  latest_posted_period: string | null;
  latest_posted_at: string | null;
  reconciliation_status:
    | "legal_entity_required"
    | "branch_required"
    | "invalid_legal_entity"
    | "invalid_branch"
    | "cost_required"
    | "invalid_salvage_value"
    | "useful_life_required"
    | "depreciation_start_required"
    | "unsupported_method"
    | "register_mismatch"
    | "fully_depreciated"
    | "ready";
};

export type AssetPostingConfigurationGap = {
  legal_entity_id: string;
  legal_entity_code: string;
  account_role: string;
};

export async function postAssetDepreciation(
  assetId: string,
  periodCode: string,
  accountingDate: string,
): Promise<AssetDepreciationPostingResult> {
  if (!ONEXA_ASSET_POSTING_ENABLED) {
    return { status: "disabled", code: "ONEXA_ASSET_POSTING_DISABLED" };
  }
  if (![assetId, periodCode, accountingDate].every((value) => value.trim())) {
    throw new Error("ONEXA_ASSET_POSTING_CONTEXT_REQUIRED");
  }

  const db = supabase as any;
  const { data, error } = await db.rpc("onexa_post_asset_depreciation", {
    _asset_id: assetId,
    _period_code: periodCode.trim(),
    _accounting_date: accountingDate,
  });
  if (error) throw new Error(error.message || "ONEXA_ASSET_DEPRECIATION_POSTING_FAILED");
  if (typeof data !== "string" || !data) {
    throw new Error("ONEXA_ASSET_DEPRECIATION_INVALID_RESPONSE");
  }
  return { status: "posted", journalId: data };
}

export async function fetchAssetAccountingReconciliation(
  limit = 500,
): Promise<AssetAccountingReconciliation[]> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_asset_accounting_reconciliation")
    .select(
      "asset_id,tenant_id,legal_entity_id,branch_id,asset_code,asset_name,category,project_id,department_id,purchase_date,depreciation_start_date,depreciation_method,cost,salvage_value,annual_depreciation,opening_accumulated_depreciation,accumulated_depreciation,net_book_value,posted_periods,gate38_depreciation,latest_posted_period,latest_posted_at,reconciliation_status",
    )
    .order("asset_code")
    .limit(Math.min(Math.max(limit, 1), 2000));

  if (error) throw new Error(error.message || "ONEXA_ASSET_RECONCILIATION_FAILED");
  return (data ?? []) as AssetAccountingReconciliation[];
}

export async function fetchAssetPostingConfigurationGaps(): Promise<
  AssetPostingConfigurationGap[]
> {
  const db = supabase as any;
  const { data, error } = await db
    .from("onexa_asset_posting_configuration_gaps")
    .select("legal_entity_id,legal_entity_code,account_role")
    .order("legal_entity_code")
    .order("account_role");

  if (error) throw new Error(error.message || "ONEXA_ASSET_CONFIGURATION_GAPS_FAILED");
  return (data ?? []) as AssetPostingConfigurationGap[];
}
