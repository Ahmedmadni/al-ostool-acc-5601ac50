import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument, transitionBusinessDocument } from "@/lib/documents/business-document-service";
import { ONEXA_FLEET_TRIP_COST_POSTING_ENABLED } from "@/lib/runtime-flags";

export type FleetTripScope = {
  trip_id: string;
  vehicle_id: string;
  legal_entity_id: string;
  branch_id: string;
  trip_label: string;
  vehicle_label: string;
  cost_center_code: string;
};
export type FleetTripCostDocument = {
  id: string;
  document_number: string;
  status: string;
  gross_total: number;
  accounting_date: string;
  created_by: string;
  external_reference: string;
};

export async function listFleetTripScopes(): Promise<FleetTripScope[]> {
  if (!ONEXA_FLEET_TRIP_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_fleet_trip_scopes")
    .select("trip_id,vehicle_id,legal_entity_id,branch_id,trip_label,vehicle_label,cost_center_code")
    .eq("is_active",true).order("trip_label").limit(200);
  if (error) throw new Error(error.message);
  return data ?? [];
}
export async function listOnexaFleetTripCosts(): Promise<FleetTripCostDocument[]> {
  if (!ONEXA_FLEET_TRIP_COST_POSTING_ENABLED) return [];
  const { data, error } = await (supabase as any).from("onexa_business_documents")
    .select("id,document_number,status,gross_total,accounting_date,created_by,external_reference")
    .eq("document_type","fleet_trip_cost").order("created_at",{ascending:false}).limit(100);
  if (error) throw new Error(error.message);
  return data ?? [];
}
export async function createOnexaFleetTripCost(
  scope: FleetTripScope, amount: number, date: string, reference: string, description: string,
) {
  if (!ONEXA_FLEET_TRIP_COST_POSTING_ENABLED) throw new Error("ONEXA_FLEET_TRIP_COST_POSTING_DISABLED");
  if (!Number.isFinite(amount) || amount<=0 || Math.abs(Math.round(amount*100)-amount*100)>1e-7)
    throw new Error("ONEXA_FLEET_TRIP_COST_AMOUNT_INVALID");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !reference.trim() || !description.trim())
    throw new Error("ONEXA_FLEET_TRIP_COST_DETAILS_REQUIRED");
  const id=await createBusinessDocument({
    legalEntityId:scope.legal_entity_id,branchId:scope.branch_id,
    module:"logistics",documentType:"fleet_trip_cost",
    documentDate:date,accountingDate:date,currency:"SAR",
    subtotal:amount,grossTotal:amount,taxTotal:0,
    externalReference:reference.trim(),memo:description.trim(),
    dimensions:{vehicle:scope.vehicle_id,costCenter:scope.cost_center_code},
    sourceSnapshot:{trip_id:scope.trip_id,source_kind:"unpaid_trip_charge"},
    lines:[{lineNumber:1,description:description.trim(),quantity:1,
      unitPrice:amount,netAmount:amount,taxAmount:0,grossAmount:amount}],
  });
  await transitionBusinessDocument(id,"submitted");
  return id;
}
export async function approveOnexaFleetTripCost(id:string) {
  if (!ONEXA_FLEET_TRIP_COST_POSTING_ENABLED) throw new Error("ONEXA_FLEET_TRIP_COST_POSTING_DISABLED");
  return transitionBusinessDocument(id,"approved");
}
export async function postOnexaFleetTripCost(id:string,date:string):Promise<string> {
  if (!ONEXA_FLEET_TRIP_COST_POSTING_ENABLED) throw new Error("ONEXA_FLEET_TRIP_COST_POSTING_DISABLED");
  const {data,error}=await (supabase as any).rpc("onexa_post_fleet_trip_cost",{
    _document_id:id,_period_code:date.slice(0,7),
  });
  if(error) throw new Error(error.message);
  if(typeof data!=="string" || !data) throw new Error("ONEXA_FLEET_TRIP_COST_INVALID_RESPONSE");
  return data;
}
