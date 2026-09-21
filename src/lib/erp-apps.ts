import {
  BarChart3,
  Building2,
  Calculator,
  ClipboardList,
  FolderKanban,
  Landmark,
  PackageOpen,
  Receipt,
  Settings,
  ShieldCheck,
  Truck,
  UserCog,
  Users,
  Vault,
  Warehouse,
  type LucideIcon,
} from "lucide-react";
import type { OnexaModuleKey } from "@/lib/onexa-product";

export type ErpAppCategory = "overview" | "finance" | "operations" | "resources" | "admin";

export type LegacyCompanyGuard = {
  companyCode: "OM" | "RE" | "IT";
  moduleKey: "maintenance" | "real_estate" | "it_services";
};

export type ErpApp = {
  key: string;
  title: string;
  titleEn: string;
  subtitle: string;
  subtitleEn: string;
  to: string;
  icon: LucideIcon;
  category: ErpAppCategory;
  subscriptionModule: OnexaModuleKey;
  permissionModule?: string;
  legacyGuard?: LegacyCompanyGuard;
  featured?: boolean;
};

export const ERP_APP_CATEGORIES: Array<{ key: ErpAppCategory; label: string; labelEn: string }> = [
  { key: "overview", label: "الإدارة التنفيذية", labelEn: "Executive Management" },
  { key: "finance", label: "المالية والتجارة", labelEn: "Finance & Commerce" },
  { key: "operations", label: "المشاريع والتشغيل", labelEn: "Projects & Operations" },
  { key: "resources", label: "الموارد والأصول", labelEn: "Resources & Assets" },
  { key: "admin", label: "إدارة مساحة العمل", labelEn: "Workspace Administration" },
];

/**
 * Tenant-neutral ONEXA application catalogue. Subscription entitlements are
 * evaluated before role permissions; administrators cannot bypass plan limits.
 * Legacy company guards remain only while the Al-Ostool workspace is migrated.
 */
export const ERP_APPS: ErpApp[] = [
  { key: "executive", title: "الإدارة التنفيذية والتقارير", titleEn: "Executive Management & Reports", subtitle: "المؤشرات والتنبيهات والتوقعات ومركز التقارير الموحد", subtitleEn: "KPIs, alerts, forecasts, and the consolidated reports center", to: "/executive", icon: BarChart3, category: "overview", subscriptionModule: "finance", permissionModule: "dashboard", featured: true },
  { key: "general_ledger", title: "الحسابات العامة", titleEn: "General Ledger", subtitle: "القيود والدفاتر والقوائم والتقارير المالية", subtitleEn: "Journals, ledgers, statements, and financial reporting", to: "/financials", icon: Landmark, category: "finance", subscriptionModule: "finance", permissionModule: "financials", featured: true },
  { key: "sales", title: "العملاء والمبيعات", titleEn: "Sales & Customers", subtitle: "العملاء والعقود والفواتير والتحصيل", subtitleEn: "Customers, contracts, invoices, and collections", to: "/customers", icon: Users, category: "finance", subscriptionModule: "sales", permissionModule: "customers" },
  { key: "procurement", title: "الموردون والمشتريات", titleEn: "Procurement & Suppliers", subtitle: "الموردون والعقود والفواتير والمدفوعات", subtitleEn: "Suppliers, contracts, bills, and payments", to: "/vendors", icon: Truck, category: "finance", subscriptionModule: "procurement", permissionModule: "vendors" },
  { key: "costs", title: "التكاليف والميزانيات", titleEn: "Costs & Budgets", subtitle: "التكلفة والربحية والرقابة", subtitleEn: "Cost control, profitability, and budgets", to: "/costs", icon: Receipt, category: "finance", subscriptionModule: "finance", permissionModule: "costs" },
  { key: "treasury", title: "الخزينة والسيولة", titleEn: "Treasury & Liquidity", subtitle: "النقدية والبنوك والتوقعات", subtitleEn: "Cash, banking, and liquidity forecasting", to: "/treasury", icon: Vault, category: "finance", subscriptionModule: "finance", permissionModule: "treasury" },
  { key: "tax", title: "الزكاة والضريبة", titleEn: "Zakat & Tax", subtitle: "ضريبة القيمة المضافة والزكاة والامتثال", subtitleEn: "VAT, Zakat, and compliance workflows", to: "/tax-tools", icon: Calculator, category: "finance", subscriptionModule: "finance", permissionModule: "tax" },
  { key: "projects", title: "المشاريع والتشغيل", titleEn: "Projects & Operations", subtitle: "المقاولات • الصيانة والتشغيل • العقود الخدمية", subtitleEn: "Contracting, O&M, and service contracts", to: "/projects", icon: FolderKanban, category: "operations", subscriptionModule: "projects", permissionModule: "projects.list", featured: true },
  { key: "maintenance", title: "أوامر الصيانة والتشغيل", titleEn: "Maintenance & Operations", subtitle: "الأصول • SLA • الأوامر • الزيارات • التكلفة", subtitleEn: "Assets, SLAs, work orders, visits, and cost", to: "/maintenance", icon: ClipboardList, category: "operations", subscriptionModule: "projects", legacyGuard: { companyCode: "OM", moduleKey: "maintenance" } },
  { key: "facilities", title: "إدارة المرافق والعقارات", titleEn: "Facilities & Real Estate", subtitle: "العقارات والوحدات والإيجارات والإشغال والمرافق", subtitleEn: "Properties, units, leases, occupancy, and facilities", to: "/real-estate", icon: Building2, category: "operations", subscriptionModule: "facilities", legacyGuard: { companyCode: "RE", moduleKey: "real_estate" }, featured: true },
  { key: "logistics", title: "النقليات واللوجستيات", titleEn: "Fleet & Logistics", subtitle: "المركبات والرحلات والسائقون والوقود", subtitleEn: "Vehicles, trips, drivers, and fuel", to: "/fleet", icon: Truck, category: "operations", subscriptionModule: "logistics", permissionModule: "fleet" },
  { key: "inventory", title: "المخزون والمستودعات", titleEn: "Inventory & Warehouses", subtitle: "الأصناف والتوريد والصرف والتقييم", subtitleEn: "Items, receipts, issues, and valuation", to: "/warehouses", icon: Warehouse, category: "resources", subscriptionModule: "inventory", permissionModule: "inventory.warehouses" },
  { key: "assets", title: "الأصول الثابتة", titleEn: "Fixed Assets", subtitle: "سجل الأصول والإهلاك والحركة والتقارير", subtitleEn: "Asset register, depreciation, movements, and reports", to: "/fixed-assets", icon: PackageOpen, category: "resources", subscriptionModule: "assets", permissionModule: "assets" },
  { key: "people", title: "الموارد البشرية والرواتب", titleEn: "People & Payroll", subtitle: "الموظفون والحضور والإجازات والرواتب", subtitleEn: "Employees, attendance, leave, and payroll", to: "/hr", icon: UserCog, category: "resources", subscriptionModule: "people", permissionModule: "hr" },
  { key: "tasks", title: "سير العمل والمهام", titleEn: "Workflow & Tasks", subtitle: "المهام والتقويم والمتابعة وأداء الفريق", subtitleEn: "Tasks, calendar, follow-up, and team performance", to: "/tasks", icon: ClipboardList, category: "resources", subscriptionModule: "people", permissionModule: "tasks" },
  { key: "settings", title: "إعدادات مساحة العمل", titleEn: "Workspace Settings", subtitle: "الشركات والفروع والمستخدمون والإعدادات", subtitleEn: "Entities, branches, users, and configuration", to: "/settings/users", icon: Settings, category: "admin", subscriptionModule: "finance", permissionModule: "settings.users" },
  { key: "permissions", title: "المستخدمون والصلاحيات", titleEn: "Users & Permissions", subtitle: "الأدوار وحدود الوصول والتدقيق", subtitleEn: "Roles, access boundaries, and audit", to: "/settings/permissions", icon: ShieldCheck, category: "admin", subscriptionModule: "finance", permissionModule: "settings.permissions" },
];
