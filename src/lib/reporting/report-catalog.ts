import type { OnexaModuleKey } from "@/lib/onexa-product";
import type { SourceDocumentType } from "@/lib/accounting/posting-contracts";

export type OnexaReport = {
  key: string;
  labelAr: string;
  labelEn: string;
  owner: OnexaModuleKey;
  sourceDocuments: readonly SourceDocumentType[];
  dimensions: readonly string[];
  route?: string;
};

const allDocuments: readonly SourceDocumentType[] = [
  "sales_invoice", "customer_receipt", "purchase_invoice", "supplier_payment",
  "inventory_receipt", "inventory_issue", "payroll_run", "fixed_asset_acquisition",
  "depreciation_run", "project_cost", "maintenance_work_order_cost", "lease_invoice",
  "lease_receipt", "fleet_trip_cost", "fuel_issue", "bank_transfer",
];

export const ONEXA_REPORTS: readonly OnexaReport[] = [
  { key: "general_ledger", labelAr: "دفتر الأستاذ العام", labelEn: "General ledger", owner: "finance", sourceDocuments: allDocuments, dimensions: ["entity", "branch", "account", "period"], route: "/financials/reports" },
  { key: "trial_balance", labelAr: "ميزان المراجعة", labelEn: "Trial balance", owner: "finance", sourceDocuments: allDocuments, dimensions: ["entity", "branch", "account", "period"], route: "/trial-balance" },
  { key: "balance_sheet", labelAr: "الميزانية العمومية", labelEn: "Balance sheet", owner: "finance", sourceDocuments: allDocuments, dimensions: ["entity", "branch", "period"], route: "/financials/balance-sheet" },
  { key: "income_statement", labelAr: "قائمة الدخل", labelEn: "Income statement", owner: "finance", sourceDocuments: allDocuments, dimensions: ["entity", "branch", "cost_center", "period"], route: "/financials/income-statement" },
  { key: "cash_flow", labelAr: "قائمة التدفقات النقدية", labelEn: "Cash flow statement", owner: "finance", sourceDocuments: ["customer_receipt", "supplier_payment", "lease_receipt", "bank_transfer"], dimensions: ["entity", "bank", "period"], route: "/financials/cash-flow" },
  { key: "vat_return", labelAr: "إقرار ضريبة القيمة المضافة", labelEn: "VAT return", owner: "finance", sourceDocuments: ["sales_invoice", "purchase_invoice", "fixed_asset_acquisition", "lease_invoice"], dimensions: ["entity", "tax_period"], route: "/tax-tools" },
  { key: "ar_aging", labelAr: "أعمار ذمم العملاء", labelEn: "Receivables aging", owner: "sales", sourceDocuments: ["sales_invoice", "customer_receipt", "lease_invoice", "lease_receipt"], dimensions: ["entity", "customer", "due_date"], route: "/customers/aging" },
  { key: "sales_margin", labelAr: "هامش وربحية المبيعات", labelEn: "Sales margin and profitability", owner: "sales", sourceDocuments: ["sales_invoice"], dimensions: ["entity", "branch", "customer", "warehouse", "item", "date"], route: "/customers/reports" },
  { key: "ap_aging", labelAr: "أعمار ذمم الموردين", labelEn: "Payables aging", owner: "procurement", sourceDocuments: ["purchase_invoice", "supplier_payment"], dimensions: ["entity", "vendor", "due_date"], route: "/vendors/aging" },
  { key: "purchase_reconciliation", labelAr: "مطابقة المشتريات والمخزون والأستاذ", labelEn: "Purchase, inventory and GL reconciliation", owner: "procurement", sourceDocuments: ["purchase_invoice"], dimensions: ["entity", "branch", "vendor", "warehouse", "item", "date"], route: "/vendors/reports" },
  { key: "purchase_classification", labelAr: "تحليل المشتريات حسب التصنيف", labelEn: "Purchases by accounting classification", owner: "procurement", sourceDocuments: ["purchase_invoice"], dimensions: ["entity", "vendor", "inventory", "expense", "asset", "tax_period"], route: "/vendors/reports" },
  { key: "inventory_valuation", labelAr: "تقييم المخزون", labelEn: "Inventory valuation", owner: "inventory", sourceDocuments: ["sales_invoice", "inventory_receipt", "inventory_issue"], dimensions: ["entity", "warehouse", "item", "date"], route: "/warehouses/reports" },
  { key: "project_profitability", labelAr: "ربحية المشاريع والعقود", labelEn: "Project and contract profitability", owner: "projects", sourceDocuments: ["sales_invoice", "purchase_invoice", "inventory_issue", "payroll_run", "project_cost", "maintenance_work_order_cost", "fleet_trip_cost", "fuel_issue"], dimensions: ["entity", "project", "contract", "cost_center"], route: "/projects/reports" },
  { key: "maintenance_cost", labelAr: "تكلفة الصيانة والتشغيل", labelEn: "Maintenance and operations cost", owner: "projects", sourceDocuments: ["maintenance_work_order_cost", "inventory_issue", "payroll_run", "purchase_invoice"], dimensions: ["entity", "project", "work_order", "asset"], route: "/projects/reports" },
  { key: "fixed_asset_register", labelAr: "سجل الأصول والإهلاك", labelEn: "Fixed asset register", owner: "assets", sourceDocuments: ["fixed_asset_acquisition", "depreciation_run"], dimensions: ["entity", "asset", "asset_class", "period"], route: "/fixed-assets/reports" },
  { key: "payroll_cost", labelAr: "تكلفة الرواتب", labelEn: "Payroll cost", owner: "people", sourceDocuments: ["payroll_run"], dimensions: ["entity", "department", "employee", "cost_center", "project"], route: "/hr/reports" },
  { key: "payroll_accounting_reconciliation", labelAr: "مطابقة الرواتب والتكاليف والأستاذ", labelEn: "Payroll, cost ledger and GL reconciliation", owner: "people", sourceDocuments: ["payroll_run"], dimensions: ["entity", "branch", "period", "department", "employee", "project"], route: "/hr/reports" },
  { key: "lease_portfolio", labelAr: "محفظة الإيجارات والإشغال", labelEn: "Lease and occupancy portfolio", owner: "facilities", sourceDocuments: ["lease_invoice", "lease_receipt"], dimensions: ["entity", "property", "unit", "customer", "contract"], route: "/real-estate/reports" },
  { key: "fleet_cost", labelAr: "تكلفة الأسطول والرحلات", labelEn: "Fleet and trip cost", owner: "logistics", sourceDocuments: ["fleet_trip_cost", "fuel_issue", "maintenance_work_order_cost"], dimensions: ["entity", "vehicle", "trip", "driver", "project"], route: "/fleet/reports" },
];

export function reportsForDocument(documentType: SourceDocumentType) {
  return ONEXA_REPORTS.filter((report) => report.sourceDocuments.includes(documentType));
}

export function reportsForModule(module: OnexaModuleKey) {
  return ONEXA_REPORTS.filter((report) => report.owner === module);
}

/** Consolidated catalogue for Executive Management; report ownership stays with each module. */
export function executiveReportCatalog(enabledModules?: readonly OnexaModuleKey[]) {
  if (!enabledModules) return ONEXA_REPORTS;
  const enabled = new Set<OnexaModuleKey>(["finance", ...enabledModules]);
  return ONEXA_REPORTS.filter((report) => enabled.has(report.owner));
}
