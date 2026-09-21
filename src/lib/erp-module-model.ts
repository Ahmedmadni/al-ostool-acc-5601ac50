import type { SourceDocumentType } from "@/lib/accounting/posting-contracts";
import type { OnexaModuleKey } from "@/lib/onexa-product";
import { reportsForModule } from "@/lib/reporting/report-catalog";

export type OnexaModuleBlueprint = {
  key: OnexaModuleKey;
  labelAr: string;
  labelEn: string;
  entryRoute: string;
  reportsRoute: string;
  operationalDependencies: readonly OnexaModuleKey[];
  sourceDocuments: readonly SourceDocumentType[];
  controlAccountRoles: readonly string[];
};

/**
 * Accounting-first module graph. Operational dependencies move quantity/value;
 * control account roles are the module's summarized link to the general ledger.
 */
export const ONEXA_MODULE_BLUEPRINTS: readonly OnexaModuleBlueprint[] = [
  { key: "finance", labelAr: "الحسابات العامة والخزينة", labelEn: "General Ledger & Treasury", entryRoute: "/financials", reportsRoute: "/financials/reports", operationalDependencies: [], sourceDocuments: ["bank_transfer"], controlAccountRoles: ["cash_or_bank", "destination_bank", "source_bank"] },
  { key: "sales", labelAr: "العملاء والمبيعات", labelEn: "Sales & Customers", entryRoute: "/customers/invoices", reportsRoute: "/customers/reports", operationalDependencies: ["inventory", "finance"], sourceDocuments: ["sales_invoice", "customer_receipt"], controlAccountRoles: ["accounts_receivable", "sales_revenue", "output_vat", "cost_of_goods_sold", "inventory"] },
  { key: "procurement", labelAr: "الموردون والمشتريات", labelEn: "Procurement & Suppliers", entryRoute: "/vendors/invoices", reportsRoute: "/vendors/reports", operationalDependencies: ["inventory", "assets", "finance"], sourceDocuments: ["purchase_invoice", "supplier_payment"], controlAccountRoles: ["accounts_payable", "input_vat", "inventory", "purchase_expense", "fixed_asset_cost"] },
  { key: "inventory", labelAr: "المخزون والمستودعات", labelEn: "Inventory & Warehouses", entryRoute: "/warehouses", reportsRoute: "/warehouses/reports", operationalDependencies: ["finance"], sourceDocuments: ["inventory_receipt", "inventory_issue"], controlAccountRoles: ["inventory", "goods_received_not_invoiced", "project_cost_cogs_or_expense"] },
  { key: "projects", labelAr: "المشاريع والتشغيل", labelEn: "Projects & Operations", entryRoute: "/projects", reportsRoute: "/projects/reports", operationalDependencies: ["inventory", "people", "procurement", "finance"], sourceDocuments: ["project_cost", "maintenance_work_order_cost"], controlAccountRoles: ["project_wip_or_expense", "maintenance_project_cost", "cost_source_or_clearing"] },
  { key: "facilities", labelAr: "المرافق والعقارات", labelEn: "Facilities & Real Estate", entryRoute: "/real-estate", reportsRoute: "/real-estate/reports", operationalDependencies: ["sales", "finance"], sourceDocuments: ["lease_invoice", "lease_receipt"], controlAccountRoles: ["accounts_receivable", "rental_revenue", "output_vat"] },
  { key: "logistics", labelAr: "النقليات واللوجستيات", labelEn: "Fleet & Logistics", entryRoute: "/fleet", reportsRoute: "/fleet/reports", operationalDependencies: ["inventory", "projects", "finance"], sourceDocuments: ["fleet_trip_cost", "fuel_issue"], controlAccountRoles: ["logistics_or_project_cost", "fuel_or_project_cost", "cash_ap_or_clearing"] },
  { key: "assets", labelAr: "الأصول الثابتة", labelEn: "Fixed Assets", entryRoute: "/fixed-assets", reportsRoute: "/fixed-assets/reports", operationalDependencies: ["procurement", "finance"], sourceDocuments: ["fixed_asset_acquisition", "depreciation_run"], controlAccountRoles: ["fixed_asset_cost", "depreciation_expense", "accumulated_depreciation"] },
  { key: "people", labelAr: "الموارد البشرية والرواتب", labelEn: "People & Payroll", entryRoute: "/hr/payroll", reportsRoute: "/hr/reports", operationalDependencies: ["projects", "finance"], sourceDocuments: ["payroll_run"], controlAccountRoles: ["payroll_expense_or_project_cost", "employee_payables", "gosi_payable", "employee_loans_receivable"] },
] as const;

export function getModuleBlueprint(module: OnexaModuleKey) {
  return ONEXA_MODULE_BLUEPRINTS.find((item) => item.key === module);
}

export function moduleAccountingCoverage(module: OnexaModuleKey) {
  const blueprint = getModuleBlueprint(module);
  return {
    blueprint,
    reports: reportsForModule(module),
    isConfigured: Boolean(blueprint && blueprint.sourceDocuments.length && blueprint.controlAccountRoles.length),
  };
}
