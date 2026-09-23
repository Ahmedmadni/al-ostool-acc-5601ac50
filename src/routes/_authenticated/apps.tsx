import { createFileRoute, Link } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Layers3, Search, Sparkles, Star } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { useTenantContext } from "@/hooks/use-tenant-context";
import { ERP_APPS, ERP_APP_CATEGORIES, type ErpApp } from "@/lib/erp-apps";
import { AccountingIntegrationOverview } from "@/components/accounting/integration-overview";
import { WorkspaceSubscriptionPanel } from "@/components/tenancy/workspace-subscription-panel";
import { useI18n } from "@/lib/i18n";

export const Route = createFileRoute("/_authenticated/apps")({
  component: AppsLauncherPage,
});

type LegacyGuardKey = "maintenance" | "real_estate" | "it_services";
type LegacyAccessMap = Record<LegacyGuardKey, boolean>;

async function loadLegacyModuleAccess(): Promise<LegacyAccessMap> {
  const db = supabase as any;
  const pairs = [
    ["maintenance", "OM", "maintenance"],
    ["real_estate", "RE", "real_estate"],
    ["it_services", "IT", "it_services"],
  ] as const;
  const result: LegacyAccessMap = { maintenance: false, real_estate: false, it_services: false };
  await Promise.all(pairs.map(async ([key, companyCode, moduleKey]) => {
    const { data, error } = await db.rpc("group_has_module_access", { _company_code: companyCode, _module_key: moduleKey });
    result[key] = !error && data === true;
  }));
  return result;
}

function AppsLauncherPage() {
  const { can, isAdmin } = usePermissions();
  const tenant = useTenantContext();
  const { lang, dir } = useI18n();
  const english = lang === "en";
  const copy = english ? {
    title: "Business applications",
    description: `Modules available to ${tenant.label.name} based on the subscription and your permissions. Every operational flow connects to one governed accounting source.`,
    plan: "Plan",
    search: "Search applications…",
    favorites: "Favorites",
    module: "app",
    modules: "apps",
    empty: "No applications match the current search, subscription, and permissions.",
    featured: "Core",
    addFavorite: "Add to favorites",
    removeFavorite: "Remove from favorites",
    all: "All applications",
    available: "Available",
    categories: "Categories",
    pinned: "Pinned",
    browse: "Browse by business area",
    governance: "Workspace governance & accounting integration",
    clear: "Clear filters",
  } : {
    title: "تطبيقات الأعمال",
    description: `الموديولات المتاحة لمساحة عمل ${tenant.label.name} وفق الباقة وصلاحيات المستخدم. ترتبط كل العمليات بمصدر محاسبي موحد ومحكوم.`,
    plan: "الباقة",
    search: "ابحث عن تطبيق…",
    favorites: "المفضلة",
    module: "تطبيق",
    modules: "تطبيقات",
    empty: "لا توجد تطبيقات مطابقة للبحث والباقة والصلاحيات الحالية.",
    featured: "رئيسي",
    addFavorite: "إضافة إلى المفضلة",
    removeFavorite: "إزالة من المفضلة",
    all: "كل التطبيقات",
    available: "المتاح",
    categories: "التصنيفات",
    pinned: "المثبتة",
    browse: "استعراض حسب مجال العمل",
    governance: "حوكمة مساحة العمل والتكامل المحاسبي",
    clear: "مسح عوامل التصفية",
  };
  const [search, setSearch] = useState("");
  const [activeCategory, setActiveCategory] = useState<"all" | ErpApp["category"]>("all");
  const [favorites, setFavorites] = useState<string[]>(() => {
    if (typeof window === "undefined") return [];
    try { return JSON.parse(window.localStorage.getItem("onexa:erp-app-favorites") || "[]") as string[]; } catch { return []; }
  });
  const { data: legacyAccess = { maintenance: false, real_estate: false, it_services: false } } = useQuery({
    queryKey: ["erp-app-legacy-company-access"],
    queryFn: loadLegacyModuleAccess,
    enabled: tenant.mode === "legacy",
    retry: false,
  });

  const allowed = useMemo(() => ERP_APPS.filter((app) => {
    if (!tenant.canUseModule(app.subscriptionModule)) return false;
    if (isAdmin) return true;
    if (tenant.mode === "legacy" && app.legacyGuard) return legacyAccess[app.legacyGuard.moduleKey];
    return app.permissionModule ? can(app.permissionModule, "view") : true;
  }), [isAdmin, can, legacyAccess, tenant.mode, tenant.claims]); // eslint-disable-line react-hooks/exhaustive-deps

  const availableCategories = useMemo(
    () => ERP_APP_CATEGORIES.filter((category) => allowed.some((app) => app.category === category.key)),
    [allowed],
  );

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return allowed.filter((app) => {
      if (activeCategory !== "all" && app.category !== activeCategory) return false;
      if (!query) return true;
      return `${app.title} ${app.titleEn} ${app.subtitle} ${app.subtitleEn} ${app.key}`.toLowerCase().includes(query);
    });
  }, [activeCategory, allowed, search]);

  const toggleFavorite = (key: string) => {
    setFavorites((current) => {
      const next = current.includes(key) ? current.filter((item) => item !== key) : [...current, key];
      try { localStorage.setItem("onexa:erp-app-favorites", JSON.stringify(next)); } catch {}
      return next;
    });
  };

  return (
    <div className="mx-auto w-full max-w-[1500px] space-y-8 p-4 md:p-6 lg:p-8" dir={dir}>
      <section className="overflow-hidden rounded-3xl border border-border bg-card shadow-sm">
        <div className="h-1.5 bg-[linear-gradient(90deg,var(--brand-blue)_0_58%,var(--brand-cyan)_58%_82%,var(--brand-amber)_82%)]" />
        <div className="p-6 md:p-8">
        <div className="grid gap-7 lg:grid-cols-[1fr_380px] lg:items-end">
          <div>
            <div className="inline-flex items-center gap-2 rounded-full border border-primary/15 bg-primary/[0.06] px-3 py-1.5 text-xs font-bold text-primary"><Sparkles className="h-3.5 w-3.5" /> ONEXA ERP</div>
            <h1 className="mt-4 text-3xl font-black tracking-tight md:text-4xl">{copy.title}</h1>
            <p className="mt-3 max-w-3xl text-sm leading-7 text-muted-foreground md:text-base">{copy.description}</p>
            <div className="mt-4 inline-flex rounded-lg border border-border bg-background px-3 py-2 text-xs font-bold"><span className="text-muted-foreground">{copy.plan}:</span><span className="ms-2 text-primary">{tenant.label.plan}</span></div>
          </div>
          <div className="space-y-3">
            <div className="relative"><Search className="absolute end-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={copy.search} className="h-12 rounded-xl bg-background pe-10" /></div>
            <div className="grid grid-cols-3 gap-2">
              {[
                [copy.available, allowed.length],
                [copy.categories, availableCategories.length],
                [copy.pinned, allowed.filter((app) => favorites.includes(app.key)).length],
              ].map(([label, value]) => (
                <div key={String(label)} className="rounded-xl border border-border bg-background px-3 py-3 text-center">
                  <div className="text-xl font-black text-foreground">{value}</div>
                  <div className="mt-0.5 text-[10px] font-semibold text-muted-foreground">{label}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
        </div>
      </section>

      <section className="rounded-2xl border border-border bg-card p-4 md:p-5">
        <div className="mb-4 flex items-center gap-2">
          <span className="grid h-9 w-9 place-items-center rounded-xl bg-primary/10 text-primary"><Layers3 className="h-4 w-4" /></span>
          <div>
            <h2 className="text-sm font-black">{copy.browse}</h2>
            <p className="mt-0.5 text-xs text-muted-foreground">{filtered.length} {filtered.length === 1 ? copy.module : copy.modules}</p>
          </div>
        </div>
        <div className="flex flex-wrap gap-2" role="group" aria-label={copy.browse}>
          <button type="button" aria-pressed={activeCategory === "all"} onClick={() => setActiveCategory("all")} className={`rounded-xl border px-3 py-2 text-xs font-bold transition ${activeCategory === "all" ? "border-primary bg-primary text-primary-foreground" : "border-border bg-background text-muted-foreground hover:border-primary/25 hover:text-foreground"}`}>{copy.all}</button>
          {availableCategories.map((category) => (
            <button key={category.key} type="button" aria-pressed={activeCategory === category.key} onClick={() => setActiveCategory(category.key)} className={`rounded-xl border px-3 py-2 text-xs font-bold transition ${activeCategory === category.key ? "border-primary bg-primary text-primary-foreground" : "border-border bg-background text-muted-foreground hover:border-primary/25 hover:text-foreground"}`}>
              {english ? category.labelEn : category.label}
              <span className="ms-2 opacity-70">{allowed.filter((app) => app.category === category.key).length}</span>
            </button>
          ))}
        </div>
      </section>

      {favorites.length > 0 && !search && activeCategory === "all" && (
        <section>
          <div className="mb-3 flex items-center gap-2"><Star className="h-4 w-4 fill-amber-400 text-amber-400" /><h2 className="text-sm font-black">{copy.favorites}</h2></div>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
            {allowed.filter((app) => favorites.includes(app.key)).map((app) => <AppTile key={app.key} app={app} favorite onToggleFavorite={() => toggleFavorite(app.key)} english={english} copy={copy} />)}
          </div>
        </section>
      )}

      {availableCategories.map((category) => {
        const apps = filtered.filter((app) => app.category === category.key);
        if (!apps.length) return null;
        return (
          <section key={category.key}>
            <div className="mb-3 flex items-center justify-between"><h2 className="text-sm font-black">{english ? category.labelEn : category.label}</h2><span className="text-xs text-muted-foreground">{apps.length} {apps.length === 1 ? copy.module : copy.modules}</span></div>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
              {apps.map((app) => <AppTile key={app.key} app={app} favorite={favorites.includes(app.key)} onToggleFavorite={() => toggleFavorite(app.key)} english={english} copy={copy} />)}
            </div>
          </section>
        );
      })}

      {!filtered.length && (
        <div className="rounded-2xl border border-dashed border-border bg-card px-6 py-14 text-center">
          <p className="text-sm text-muted-foreground">{copy.empty}</p>
          <button type="button" onClick={() => { setSearch(""); setActiveCategory("all"); }} className="mt-4 rounded-xl border border-border bg-background px-4 py-2 text-xs font-bold text-primary transition hover:border-primary/25">{copy.clear}</button>
        </div>
      )}

      <section className="space-y-4 border-t border-border pt-8">
        <h2 className="text-sm font-black">{copy.governance}</h2>
        <AccountingIntegrationOverview />
        <WorkspaceSubscriptionPanel />
      </section>
    </div>
  );
}

function AppTile({ app, favorite, onToggleFavorite, english, copy }: { app: ErpApp; favorite: boolean; onToggleFavorite: () => void; english: boolean; copy: { featured: string; addFavorite: string; removeFavorite: string } }) {
  const Icon = app.icon;
  return (
    <div className="group relative min-h-[175px] overflow-hidden rounded-2xl border border-border bg-card transition duration-200 hover:-translate-y-0.5 hover:border-primary/25 hover:shadow-md">
      <Link to={app.to as any} className="flex h-full min-h-[175px] flex-col p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="grid h-12 w-12 place-items-center rounded-2xl bg-primary/10 text-primary transition group-hover:bg-primary group-hover:text-primary-foreground"><Icon className="h-6 w-6" /></div>
          {app.featured && <Badge variant="secondary" className="text-[10px]">{copy.featured}</Badge>}
        </div>
        <h3 className="mt-5 font-black leading-6">{english ? app.titleEn : app.title}</h3>
        <p className="mt-2 text-xs leading-5 text-muted-foreground">{english ? app.subtitleEn : app.subtitle}</p>
      </Link>
      <button type="button" onClick={onToggleFavorite} aria-label={favorite ? copy.removeFavorite : copy.addFavorite} className="absolute bottom-3 end-3 grid h-8 w-8 place-items-center rounded-full text-muted-foreground transition hover:bg-muted hover:text-foreground">
        <Star className={`h-4 w-4 ${favorite ? "fill-amber-400 text-amber-400" : ""}`} />
      </button>
    </div>
  );
}
