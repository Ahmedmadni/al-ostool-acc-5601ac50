import { Link, useRouter, useRouterState } from "@tanstack/react-router";
import { type ReactNode, useEffect, useMemo, useState } from "react";
import {
  LayoutDashboard, Users, FolderKanban, Receipt, FileText,
  Calculator, Sparkles, Settings, LogOut,
  Moon, Sun, Search, ChevronLeft, ChevronsUpDown,
  Truck, Building2, Vault, Scale, ClipboardList, UserCog,
  Warehouse, LayoutGrid, Menu,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useTheme } from "@/components/theme-provider";
import { useAuth } from "@/hooks/use-auth";
import { Button } from "@/components/ui/button";
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { ScrollArea } from "@/components/ui/scroll-area";
import { roleLabel } from "@/lib/labels";
import { useI18n, LANGS, type Lang } from "@/lib/i18n";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { NotificationsBell } from "@/components/notifications/notifications-bell";
import { toast } from "sonner";
import { usePermissions } from "@/hooks/use-permissions";
import { pathToModule } from "@/lib/route-permissions";
import { useTenantContext } from "@/hooks/use-tenant-context";
import { OnexaBrandLockup } from "@/components/brand/onexa-brand";

type NavLink = { to: string; label: string; label_en: string };
type NavGroup = { key: string; label: string; label_en: string; icon: React.ComponentType<{ className?: string }>; links: NavLink[] };

const GROUPS: NavGroup[] = [
  {
    key: "executive", label: "الإدارة التنفيذية", label_en: "Executive Management", icon: LayoutDashboard,
    links: [
      { to: "/executive", label: "مركز القيادة التنفيذي الموحد", label_en: "Unified Executive Command Center" },
      { to: "/reports", label: "مركز التقارير الموحد", label_en: "Consolidated Reports Center" },
      { to: "/imports", label: "مركز الاستيراد والتهيئة", label_en: "Import & Staging Center" },
      { to: "/forecasting", label: "محرك التوقعات", label_en: "Forecasting Engine" },
      { to: "/scenarios", label: "تحليل السيناريوهات", label_en: "Scenario Analysis" },
      { to: "/alerts", label: "مركز التنبيهات", label_en: "Alert Center" },
      { to: "/board", label: "تقارير مجلس الإدارة", label_en: "Board Reports" },
      { to: "/copilot", label: "المساعد الذكي (Copilot) 🤖", label_en: "AI Copilot 🤖" },
    ],
  },
  {
    key: "customers", label: "العملاء والمبيعات", label_en: "Sales & Customers", icon: Users,
    links: [
      { to: "/customers", label: "العملاء", label_en: "Customers" },
      { to: "/customers/contracts", label: "العقود", label_en: "Contracts" },
      { to: "/customers/invoices", label: "فواتير البيع", label_en: "Sales Invoices" },
      { to: "/customers/collections", label: "التحصيلات", label_en: "Collections" },
      { to: "/customers/retention", label: "ضمانات الاحتجاز", label_en: "Retention Guarantees" },
      { to: "/customers/aging", label: "تحليل الأعمار", label_en: "Aging Analysis" },
      { to: "/customers/intelligence", label: "ذكاء العملاء والذمم المدينة", label_en: "Customer & AR Intelligence" },
      { to: "/customers/reports", label: "التقارير", label_en: "Reports" },
    ],
  },
  {
    key: "vendors", label: "الموردون والمشتريات", label_en: "Procurement & Suppliers", icon: Truck,
    links: [
      { to: "/vendors", label: "الموردين", label_en: "Vendors" },
      { to: "/vendors/contracts", label: "العقود", label_en: "Contracts" },
      { to: "/vendors/invoices", label: "فواتير الشراء", label_en: "Purchase Invoices" },
      { to: "/vendors/payments", label: "المدفوعات", label_en: "Payments" },
      { to: "/vendors/aging", label: "تحليل الأعمار", label_en: "Aging Analysis" },
      { to: "/vendors/intelligence", label: "ذكاء الموردين والذمم الدائنة", label_en: "Vendor & AP Intelligence" },
      { to: "/vendors/reports", label: "التقارير", label_en: "Reports" },
    ],
  },
  {
    key: "projects", label: "المشاريع والتشغيل", label_en: "Projects & Operations", icon: FolderKanban,
    links: [
      { to: "/projects", label: "المشاريع", label_en: "Projects" },
      { to: "/maintenance", label: "مشاريع الصيانة والتشغيل", label_en: "Maintenance & Operations Projects" },
      { to: "/projects/progress", label: "متابعة الإنجاز", label_en: "Progress Tracking" },
      { to: "/control/projects", label: "التحكم بالمشاريع", label_en: "Project Control" },
      { to: "/projects/reports", label: "تقارير المشاريع والتشغيل", label_en: "Projects & Operations Reports" },
    ],
  },
  {
    key: "facilities", label: "إدارة المرافق والعقارات", label_en: "Facilities & Real Estate", icon: Building2,
    links: [
      { to: "/real-estate", label: "العقارات والمرافق", label_en: "Properties & Facilities" },
      { to: "/real-estate/reports", label: "تقارير العقارات والمرافق", label_en: "Facilities & Real Estate Reports" },
    ],
  },
  {
    key: "billing", label: "التكاليف والميزانيات", label_en: "Costs & Budgets", icon: Receipt,
    links: [
      { to: "/costs", label: "ذكاء التكاليف", label_en: "Cost Intelligence" },
      { to: "/control/costs", label: "التحكم بالتكاليف", label_en: "Cost Control" },
    ],
  },
  {
    key: "treasury", label: "الخزينة والنقدية", label_en: "Treasury & Cash", icon: Vault,
    links: [
      { to: "/treasury", label: "الخزينة والمركز النقدي", label_en: "Treasury & Cash Position" },
      { to: "/treasury/forecast", label: "توقعات السيولة (90 يوم)", label_en: "90-Day Liquidity Forecast" },
      { to: "/cash-flow/matrix", label: "مصفوفة التدفقات النقدية", label_en: "Cash Flow Matrix" },
      { to: "/banks", label: "البنوك والنقدية", label_en: "Banks & Cash" },
      { to: "/treasury/reports", label: "تقارير الخزينة والسيولة", label_en: "Treasury & Liquidity Reports" },
    ],
  },
  {
    key: "assets", label: "الأصول الثابتة", label_en: "Fixed Assets", icon: Building2,
    links: [
      { to: "/fixed-assets", label: "الأصول الثابتة", label_en: "Fixed Assets" },
      { to: "/fixed-assets/reports", label: "تقارير الأصول والإهلاك", label_en: "Assets & Depreciation Reports" },
    ],
  },
  {
    key: "financials", label: "الحسابات العامة والتقارير المالية", label_en: "General Ledger & Financials", icon: Scale,
    links: [
      { to: "/financials", label: "مركز التحليل المالي", label_en: "Financial Analysis Center" },
      { to: "/trial-balance", label: "ميزان المراجعة", label_en: "Trial Balance" },
      { to: "/financials/balance-sheet", label: "الميزانية العمومية", label_en: "Balance Sheet" },
      { to: "/financials/income-statement", label: "قائمة الدخل", label_en: "Income Statement" },
      { to: "/financials/cash-flow", label: "قائمة التدفقات النقدية", label_en: "Cash Flow Statement" },
      { to: "/financials/equity", label: "قائمة حقوق الملكية", label_en: "Statement of Equity" },
      { to: "/financials/kpis", label: "محرك المؤشرات (KPI)", label_en: "KPI Engine" },
      { to: "/financials/reports", label: "تقارير الحسابات العامة", label_en: "General Ledger Reports" },
    ],
  },
  {
    key: "hr", label: "الموارد البشرية (HCM)", label_en: "Human Resources (HCM)", icon: UserCog,
    links: [
      { to: "/hr", label: "لوحة الموارد البشرية", label_en: "HR Dashboard" },
      { to: "/hr/employees", label: "الموظفون", label_en: "Employees" },
      { to: "/hr/contracts", label: "العقود", label_en: "Contracts" },
      { to: "/hr/compliance", label: "امتثال العقود", label_en: "Contract Compliance" },
      { to: "/hr/workflow", label: "الطلبات وسير الاعتماد", label_en: "Requests & Approval Workflow" },
      { to: "/hr/leaves", label: "الإجازات", label_en: "Leaves" },
      { to: "/hr/attendance", label: "الحضور والانصراف", label_en: "Attendance" },
      { to: "/hr/loans", label: "السلف", label_en: "Loans" },
      { to: "/hr/assets", label: "العهد", label_en: "Custody Assets" },
      { to: "/hr/payroll", label: "مسيرات الرواتب", label_en: "Payroll Runs" },
      { to: "/hr/termination", label: "إنهاء الخدمة", label_en: "End of Service" },
      { to: "/hr/qiwa", label: "تكامل قوى", label_en: "Qiwa Integration" },
      { to: "/hr/qiwa/mapping", label: "تعيين حقول قوى", label_en: "Qiwa Field Mapping" },
      { to: "/hr/audit", label: "سجل التدقيق", label_en: "Audit Log" },
      { to: "/hr/reports", label: "التقارير", label_en: "Reports" },
    ],
  },
  {
    key: "fleet", label: "النقليات واللوجستيات", label_en: "Transport & Logistics", icon: Truck,
    links: [
      { to: "/fleet", label: "لوحة النقليات", label_en: "Fleet Dashboard" },
      { to: "/fleet/vehicles", label: "المركبات", label_en: "Vehicles" },
      { to: "/fleet/drivers", label: "السائقون", label_en: "Drivers" },
      { to: "/fleet/trips", label: "الرحلات", label_en: "Trips" },
      { to: "/fleet/tracking", label: "تتبع مباشر (خريطة)", label_en: "Live Tracking (Map)" },
      { to: "/fleet/maintenance", label: "الصيانة", label_en: "Maintenance" },
      { to: "/fleet/fuel", label: "الوقود", label_en: "Fuel" },
      { to: "/fleet/reports", label: "تقارير الأسطول والرحلات", label_en: "Fleet & Trip Reports" },
    ],
  },
  {
    key: "inventory", label: "المخزون والمستودعات", label_en: "Inventory & Warehouses", icon: Warehouse,
    links: [
      { to: "/warehouses", label: "المخازن", label_en: "Warehouses" },
      { to: "/warehouses/items", label: "الأصناف", label_en: "Items" },
      { to: "/warehouses/receipts", label: "سندات التوريد", label_en: "Goods Receipts" },
      { to: "/warehouses/issues", label: "سندات الصرف", label_en: "Goods Issues" },
      { to: "/warehouses/stock", label: "رصيد وتقييم المخزون", label_en: "Stock Balance & Valuation" },
      { to: "/warehouses/reports", label: "تقارير المخزون", label_en: "Inventory Reports" },
    ],
  },
  {
    key: "tasks", label: "سير العمل والمهام", label_en: "Workflow & Tasks", icon: ClipboardList,
    links: [
      { to: "/tasks", label: "المهام والتقويم", label_en: "Tasks & Calendar" },
      { to: "/tasks/team", label: "أداء الفريق (المهام)", label_en: "Team Performance (Tasks)" },
    ],
  },
  {
    key: "tools", label: "الضرائب والامتثال", label_en: "Tax & Compliance", icon: Calculator,
    links: [
      { to: "/tax-tools", label: "إقرارات الزكاة وضريبة القيمة المضافة", label_en: "Zakat & VAT Returns" },
      { to: "/templates", label: "مصمم القوالب", label_en: "Template Designer" },
    ],
  },
];
export function AppShell({ children }: { children: ReactNode }) {
  const [commandOpen, setCommandOpen] = useState(false);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const { theme, toggle } = useTheme();
  const { lang, setLang, t, dir } = useI18n();
  const { user, roles, isAdmin } = useAuth();
  const tenant = useTenantContext();
  const { can } = usePermissions();
  const router = useRouter();
  const path = useRouterState({ select: (s) => s.location.pathname });

  const settingsGroup: NavGroup = useMemo(() => ({
    key: "settings", label: "الإعدادات", label_en: "Settings", icon: Settings,
    links: [
      { to: "/settings/regional", label: "الإعدادات الإقليمية", label_en: "Regional Settings" },
      { to: "/settings/approvals", label: "اعتماد المستخدمين الجدد", label_en: "Approve New Users" },
      { to: "/settings/users", label: "إدارة المستخدمين", label_en: "User Management" },
      { to: "/settings/permissions", label: "الصلاحيات", label_en: "Permissions" },
      { to: "/settings/permissions-dashboard", label: "لوحة الصلاحيات والجاهزية", label_en: "Permissions & Readiness Dashboard" },
    ],
  }), []);

  const filterLink = (to: string) => {
    if (!tenant.canUsePath(to)) return false;
    if (isAdmin) return true;
    const m = pathToModule(to);
    if (!m) return true;
    return can(m, "view");
  };

  const allGroups = useMemo(
    () => [...GROUPS, settingsGroup]
      .map((g) => ({ ...g, links: g.links.filter((l) => filterLink(l.to)) }))
      .filter((g) => g.links.length > 0),
    [settingsGroup, isAdmin, can, tenant.mode, tenant.claims], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const activeGroup = useMemo(
    () => allGroups.find((group) => group.links.some((link) => path === link.to || path.startsWith(`${link.to}/`))) ?? null,
    [allGroups, path],
  );
  const activeGroupLabel = activeGroup ? (lang === "en" ? activeGroup.label_en : activeGroup.label) : (lang === "en" ? "Choose an application" : "اختر تطبيقًا");
  const ActiveGroupIcon = activeGroup?.icon ?? LayoutGrid;

  useEffect(() => {
    const handleShortcut = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setCommandOpen((open) => !open);
      }
    };

    document.addEventListener("keydown", handleShortcut);
    return () => document.removeEventListener("keydown", handleShortcut);
  }, []);

  useEffect(() => setMobileNavOpen(false), [path]);

  const navigateFromCommand = (to: string) => {
    setCommandOpen(false);
    router.navigate({ to });
  };

  const logout = async () => {
    await supabase.auth.signOut();
    toast.success(lang === "en" ? "Signed out" : "تم تسجيل الخروج");
    router.navigate({ to: "/login" });
  };

  return (
    <div className="flex min-h-screen bg-background">
      <Sheet open={mobileNavOpen} onOpenChange={setMobileNavOpen}>
        <SheetContent
          side={dir === "rtl" ? "right" : "left"}
          className="w-[min(90vw,22rem)] border-sidebar-border bg-sidebar p-0 text-sidebar-foreground sm:max-w-sm md:hidden"
          dir={dir}
        >
          <SheetHeader className="min-h-24 border-b border-sidebar-border px-5 py-4 text-start">
            <SheetTitle className="sr-only">{lang === "en" ? "Application navigation" : "التنقل بين التطبيقات"}</SheetTitle>
            <OnexaBrandLockup language={lang === "ar" ? "ar" : "en"} compact showDescriptor={false} />
            <div className="truncate ps-[52px] text-[10px] font-medium text-sidebar-foreground/50">{tenant.label.name} • {tenant.label.plan}</div>
          </SheetHeader>

          <ScrollArea className="h-[calc(100dvh-10.5rem)]">
            <nav className="space-y-5 px-3 py-4">
              <SheetClose asChild>
                <Link
                  to="/apps"
                  className={`flex items-center gap-3 rounded-xl border px-3 py-3 text-sm font-semibold transition ${path === "/apps" ? "border-sidebar-primary/15 bg-sidebar-accent text-sidebar-primary" : "border-sidebar-border bg-sidebar text-sidebar-foreground"}`}
                >
                  <span className="grid h-9 w-9 place-items-center rounded-lg bg-sidebar-accent text-sidebar-primary"><LayoutGrid className="h-4.5 w-4.5" strokeWidth={1.8} /></span>
                  <span className="flex-1 text-start">{lang === "en" ? "App launcher" : "مشغّل التطبيقات"}</span>
                  <ChevronLeft className={`h-3.5 w-3.5 ${dir === "ltr" ? "rotate-180" : ""}`} />
                </Link>
              </SheetClose>

              {allGroups.map((group) => {
                const Icon = group.icon;
                return (
                  <section key={group.key} aria-labelledby={`mobile-group-${group.key}`}>
                    <div id={`mobile-group-${group.key}`} className="mb-1.5 flex items-center gap-2 px-2 text-[11px] font-bold text-sidebar-foreground/55">
                      <Icon className="h-3.5 w-3.5 text-sidebar-primary" />
                      <span>{lang === "en" ? group.label_en : group.label}</span>
                    </div>
                    <div className="space-y-1">
                      {group.links.map((link) => {
                        const active = path === link.to || (path.startsWith(`${link.to}/`) && path.split("/").length === link.to.split("/").length);
                        return (
                          <SheetClose asChild key={link.to}>
                            <Link
                              to={link.to}
                              className={`flex min-h-11 items-center gap-2.5 rounded-lg px-3 py-2.5 text-[13px] transition ${active ? "bg-sidebar-accent font-semibold text-sidebar-primary" : "text-sidebar-foreground/70 hover:bg-sidebar-accent/65 hover:text-sidebar-foreground"}`}
                            >
                              <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${active ? "bg-sidebar-primary" : "bg-sidebar-foreground/20"}`} />
                              <span className="flex-1 text-start">{lang === "en" ? link.label_en : link.label}</span>
                            </Link>
                          </SheetClose>
                        );
                      })}
                    </div>
                  </section>
                );
              })}
            </nav>
          </ScrollArea>

          <div className="absolute inset-x-0 bottom-0 border-t border-sidebar-border bg-sidebar p-3">
            <div className="flex items-center gap-3 rounded-xl border border-sidebar-border p-2.5">
              <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-sidebar-accent text-sm font-bold text-sidebar-primary">{user?.email?.slice(0, 1).toUpperCase() ?? "A"}</div>
              <div className="min-w-0 flex-1 text-start">
                <div className="truncate text-xs">{user?.email}</div>
                <div className="truncate text-[10px] text-sidebar-foreground/50">{roles.map((r) => roleLabel[r] ?? r).join(" • ") || "—"}</div>
              </div>
              <Button variant="ghost" size="icon" onClick={logout} title={t("logout")} aria-label={t("logout")}>
                <LogOut className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </SheetContent>
      </Sheet>

      <aside className="fixed inset-y-0 end-0 z-30 hidden w-[17rem] flex-col border-s border-sidebar-border bg-sidebar text-sidebar-foreground md:flex no-print">
        <div className="min-h-24 shrink-0 border-b border-sidebar-border px-5 py-4">
          <OnexaBrandLockup language={lang === "ar" ? "ar" : "en"} compact showDescriptor={false} />
          <div className="mt-2 truncate ps-[52px] text-[10px] font-medium text-sidebar-foreground/50">{tenant.label.name} • {tenant.label.plan}</div>
        </div>

        <nav className="flex-1 overflow-y-auto px-3 py-4 scrollbar-thin">
          <Link
            to="/apps"
            className={`flex items-center gap-3 rounded-xl border px-3 py-3 text-sm font-semibold transition ${path === "/apps" ? "border-sidebar-primary/15 bg-sidebar-accent text-sidebar-primary" : "border-sidebar-border bg-sidebar text-sidebar-foreground hover:border-sidebar-primary/20 hover:bg-sidebar-accent/60"}`}
          >
            <span className="grid h-9 w-9 place-items-center rounded-lg bg-sidebar-accent text-sidebar-primary"><LayoutGrid className="h-4.5 w-4.5" strokeWidth={1.8} /></span>
            <span className="flex-1 text-start">{lang === "en" ? "App launcher" : "مشغّل التطبيقات"}</span>
            <ChevronLeft className={`h-3.5 w-3.5 ${dir === "ltr" ? "rotate-180" : ""}`} />
          </Link>

          <div className="mt-5">
            <div className="mb-2 px-2 text-[10px] font-bold uppercase tracking-[0.12em] text-sidebar-foreground/45">{lang === "en" ? "Current application" : "التطبيق الحالي"}</div>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button type="button" className="flex w-full items-center gap-3 rounded-xl border border-sidebar-primary/15 bg-sidebar-accent px-3 py-3 text-start text-sidebar-accent-foreground transition hover:border-sidebar-primary/30">
                  <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-sidebar-primary/10 text-sidebar-primary">
                    <ActiveGroupIcon className="h-4.5 w-4.5" strokeWidth={1.8} />
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm font-bold">{activeGroupLabel}</span>
                  <ChevronsUpDown className="h-4 w-4 text-sidebar-foreground/50" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" className="max-h-[420px] w-64 overflow-y-auto">
                {allGroups.map((group) => {
                  const Icon = group.icon;
                  return (
                    <DropdownMenuItem asChild key={group.key}>
                      <Link to={group.links[0].to} className="flex cursor-pointer items-center gap-3 py-2.5">
                        <Icon className="h-4 w-4 text-primary" />
                        <span>{lang === "en" ? group.label_en : group.label}</span>
                      </Link>
                    </DropdownMenuItem>
                  );
                })}
              </DropdownMenuContent>
            </DropdownMenu>
          </div>

          {activeGroup && (
            <div className="mt-5">
              <div className="mb-2 px-2 text-[10px] font-bold uppercase tracking-[0.12em] text-sidebar-foreground/45">{lang === "en" ? "Navigation" : "التنقل"}</div>
              <div className="space-y-1">
                {activeGroup.links.map((link) => {
                  const active = path === link.to || (path.startsWith(`${link.to}/`) && path.split("/").length === link.to.split("/").length);
                  return (
                    <Link
                      key={link.to}
                      to={link.to}
                      className={`flex items-center gap-2.5 rounded-lg px-3 py-2.5 text-[13px] transition ${active ? "bg-sidebar-accent font-semibold text-sidebar-primary" : "text-sidebar-foreground/65 hover:bg-sidebar-accent/65 hover:text-sidebar-foreground"}`}
                    >
                      <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${active ? "bg-sidebar-primary" : "bg-sidebar-foreground/20"}`} />
                      <span className="flex-1">{lang === "en" ? link.label_en : link.label}</span>
                      {active && <ChevronLeft className={`h-3 w-3 ${dir === "ltr" ? "rotate-180" : ""}`} />}
                    </Link>
                  );
                })}
              </div>
            </div>
          )}
        </nav>


        <div className="p-3 border-t border-sidebar-border">
          <div className="flex items-center gap-3 rounded-xl border border-sidebar-border bg-sidebar p-2.5">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-sidebar-accent text-sm font-bold text-sidebar-primary">{user?.email?.slice(0, 1).toUpperCase() ?? "A"}</div>
            <div className="min-w-0 flex-1">
              <div className="text-xs text-sidebar-foreground truncate">{user?.email}</div>
              <div className="text-[10px] text-sidebar-foreground/50 truncate">{roles.map((r) => roleLabel[r] ?? r).join(" • ") || "—"}</div>
            </div>
            <Button variant="ghost" size="icon" onClick={logout} title={t("logout")} aria-label={t("logout")} className="text-sidebar-foreground/60 hover:bg-sidebar-accent hover:text-sidebar-foreground">
              <LogOut className="w-4 h-4" />
            </Button>
          </div>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col md:me-[17rem]">
        <header className="sticky top-0 z-20 flex h-[4.5rem] items-center gap-2 border-b border-border/80 bg-card/95 px-4 backdrop-blur md:px-6 no-print">
          <Button
            variant="outline"
            size="icon"
            onClick={() => setMobileNavOpen(true)}
            className="shrink-0 md:hidden"
            title={lang === "en" ? "Open navigation" : "فتح قائمة التنقل"}
            aria-label={lang === "en" ? "Open navigation" : "فتح قائمة التنقل"}
          >
            <Menu className="h-5 w-5" />
          </Button>
          <div className="hidden min-w-0 items-center gap-3 lg:flex">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-primary/8 text-primary">
              <ActiveGroupIcon className="h-[18px] w-[18px]" strokeWidth={1.8} />
            </span>
            <div className="min-w-0">
              <div className="truncate text-xs font-semibold text-foreground">{activeGroupLabel}</div>
              <div className="mt-0.5 flex items-center gap-1 text-[10px] text-muted-foreground">
                <Building2 className="h-3 w-3" />
                <span className="max-w-40 truncate">{tenant.label.name}</span>
                <span>•</span>
                <span className="font-semibold text-primary">{tenant.label.plan}</span>
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={() => setCommandOpen(true)}
            className="relative hidden h-10 w-full max-w-lg items-center rounded-xl border border-border bg-muted/55 pe-10 ps-14 text-start text-sm text-muted-foreground transition hover:border-primary/20 hover:bg-card focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:flex lg:ms-4"
            aria-label={lang === "en" ? "Open global search" : "فتح البحث الشامل"}
          >
            <Search className="absolute end-3 top-1/2 h-4 w-4 -translate-y-1/2" />
            <span className="truncate">{lang === "en" ? "Search pages and applications..." : "ابحث في الصفحات والتطبيقات..."}</span>
            <span className="onexa-kbd absolute start-2.5 top-1/2 -translate-y-1/2">Ctrl K</span>
          </button>
          <Button
            variant="outline"
            size="icon"
            onClick={() => setCommandOpen(true)}
            className="shrink-0 sm:hidden"
            title={lang === "en" ? "Search" : "البحث"}
            aria-label={lang === "en" ? "Open global search" : "فتح البحث الشامل"}
          >
            <Search className="h-4 w-4" />
          </Button>
          <div className="ms-auto flex items-center gap-1" />
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="sm" title="Language" className="hidden font-semibold gap-1 text-muted-foreground sm:inline-flex">
                {LANGS.find((l) => l.code === lang)?.native ?? lang}
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {LANGS.map((l) => (
                <DropdownMenuItem key={l.code} onClick={() => setLang(l.code as Lang)}>
                  <span className="font-medium">{l.native}</span>
                  <span className="text-xs text-muted-foreground ms-2">{l.label}</span>
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
          <Button
            variant="outline" size="icon"
            className="hidden shrink-0 sm:inline-flex"
            title={lang === "en" ? "Calculator" : "الآلة الحاسبة"}
            aria-label={lang === "en" ? "Calculator" : "الآلة الحاسبة"}
            onClick={() => window.dispatchEvent(new CustomEvent("toggle-floating-calculator"))}
          >
            <Calculator className="w-5 h-5" />
          </Button>
          <Button
            variant="outline" size="icon"
            className="hidden shrink-0 sm:inline-flex"
            title={t("copilot")}
            aria-label={t("copilot")}
            onClick={() => window.dispatchEvent(new CustomEvent("toggle-floating-copilot"))}
          >
            <Sparkles className="w-5 h-5" />
          </Button>
          <NotificationsBell />
          <Button variant="ghost" size="icon" asChild className="hidden sm:inline-flex" title={lang === "en" ? "My Notes" : "ملاحظاتي الشخصية"}>
            <Link to="/notes"><FileText className="w-5 h-5" /></Link>
          </Button>
          <Button variant="ghost" size="icon" asChild className="hidden sm:inline-flex" title={lang === "en" ? "My Account" : "حسابي"}>
            <Link to="/account"><Users className="w-5 h-5" /></Link>
          </Button>
          <Button variant="ghost" size="icon" onClick={toggle} className="hidden sm:inline-flex" title={t("toggleTheme")}>
            {theme === "dark" ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
          </Button>

        </header>

        <CommandDialog open={commandOpen} onOpenChange={setCommandOpen}>
          <CommandInput
            autoFocus
            placeholder={lang === "en" ? "Search by page, application, or path..." : "ابحث باسم الصفحة أو التطبيق أو المسار..."}
            dir={dir}
          />
          <CommandList className="max-h-[min(60vh,34rem)] p-2" dir={dir}>
            <CommandEmpty className="py-12 text-muted-foreground">
              {lang === "en" ? "No accessible page matches your search." : "لا توجد صفحة متاحة تطابق بحثك."}
            </CommandEmpty>
            {allGroups.map((group) => {
              const Icon = group.icon;
              return (
                <CommandGroup key={group.key} heading={lang === "en" ? group.label_en : group.label}>
                  {group.links.map((link) => (
                    <CommandItem
                      key={link.to}
                      value={`${link.label} ${link.label_en} ${group.label} ${group.label_en} ${link.to}`}
                      onSelect={() => navigateFromCommand(link.to)}
                      className="min-h-12 cursor-pointer rounded-lg px-3"
                    >
                      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-primary/8 text-primary">
                        <Icon className="h-4 w-4" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-medium">{lang === "en" ? link.label_en : link.label}</span>
                        <span className="block truncate text-[11px] text-muted-foreground" dir="ltr">{link.to}</span>
                      </span>
                    </CommandItem>
                  ))}
                </CommandGroup>
              );
            })}
          </CommandList>
        </CommandDialog>

        <div className="onexa-shell-pattern pointer-events-none absolute inset-x-0 top-[4.5rem] h-20 opacity-60" />
        <main className="relative flex-1 overflow-x-hidden p-4 md:p-6 lg:p-8 xl:p-9">{children}</main>
      </div>
    </div>
  );
}
