import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { AccountingIntegrationOverview } from "@/components/accounting/integration-overview";
import { AccountingOperationsHub } from "@/components/accounting/operations-hub";
import { AccountingDocumentWorkQueue } from "@/components/accounting/document-work-queue";
import { ManualJournalPanel } from "@/components/accounting/manual-journal-panel";
import { fmtSAR } from "@/lib/format";
import {
  Activity,
  AlertTriangle,
  ArrowLeft,
  BarChart3,
  BookOpen,
  CheckCircle2,
  CreditCard,
  Landmark,
  ListTree,
  Loader2,
  Receipt,
  Scale,
  TrendingUp,
  Wallet,
  Waves,
  PieChart,
} from "lucide-react";

export const Route = createFileRoute("/_authenticated/financials/")({ component: Page });

const ACCOUNTING_LINKS = [
  { to: "/financials", title: "نظرة عامة", icon: Activity },
  { to: "/trial-balance", title: "ميزان المراجعة", icon: Scale },
  { to: "/financials/balance-sheet", title: "الميزانية العمومية", icon: Landmark },
  { to: "/financials/income-statement", title: "قائمة الدخل", icon: TrendingUp },
  { to: "/financials/cash-flow", title: "التدفقات النقدية", icon: Waves },
  { to: "/financials/equity", title: "حقوق الملكية", icon: PieChart },
  { to: "/financials/kpis", title: "المؤشرات المالية", icon: BarChart3 },
  { to: "/financials/reports", title: "التقارير", icon: BookOpen },
] as const;

const STATEMENTS = [
  {
    to: "/financials/balance-sheet",
    title: "الميزانية العمومية",
    desc: "الأصول والالتزامات وحقوق الملكية في تاريخ محدد",
    icon: Landmark,
  },
  {
    to: "/financials/income-statement",
    title: "قائمة الدخل",
    desc: "الإيرادات والتكاليف وصافي نتيجة الفترة",
    icon: TrendingUp,
  },
  {
    to: "/financials/cash-flow",
    title: "التدفقات النقدية",
    desc: "التدفقات التشغيلية والاستثمارية والتمويلية",
    icon: Waves,
  },
  {
    to: "/financials/equity",
    title: "حقوق الملكية",
    desc: "حركة رأس المال والأرباح المحتجزة",
    icon: PieChart,
  },
] as const;

async function loadAccountingSnapshot() {
  const [banksResult, agingResult, suppliersResult, accountsResult, trialResult] = await Promise.all([
    supabase.from("bank_statements").select("bank_name,account_number,balance,txn_date").order("txn_date", { ascending: false }).limit(1000),
    supabase.from("aging_buckets").select("total_outstanding,period").order("period", { ascending: false }).limit(1000),
    supabase.from("supplier_balances").select("closing_credit,closing_debit,period").order("period", { ascending: false }).limit(1000),
    supabase.from("chart_of_accounts").select("id", { count: "exact", head: true }),
    supabase.from("trial_balance_entries").select("period,debit,credit").order("period", { ascending: false }).limit(2000),
  ]);

  const latestBanks = new Map<string, { balance: number; date: string }>();
  for (const row of banksResult.data ?? []) {
    const key = `${row.bank_name}|${row.account_number ?? ""}`;
    const current = latestBanks.get(key);
    if (!current || row.txn_date > current.date) {
      latestBanks.set(key, { balance: Number(row.balance ?? 0), date: row.txn_date });
    }
  }

  const agingRows = agingResult.data ?? [];
  const latestAgingPeriod = agingRows.reduce((latest, row) => row.period > latest ? row.period : latest, "");
  const supplierRows = suppliersResult.data ?? [];
  const latestSupplierPeriod = supplierRows.reduce((latest, row) => (row.period ?? "") > latest ? (row.period ?? "") : latest, "");
  const trialRows = trialResult.data ?? [];
  const trialPeriod = trialRows.reduce((latest, row) => row.period > latest ? row.period : latest, "");
  const currentTrial = trialRows.filter((row) => row.period === trialPeriod);
  const totalDebit = currentTrial.reduce((sum, row) => sum + Number(row.debit ?? 0), 0);
  const totalCredit = currentTrial.reduce((sum, row) => sum + Number(row.credit ?? 0), 0);

  return {
    cashPosition: Array.from(latestBanks.values()).reduce((sum, row) => sum + row.balance, 0),
    bankAccounts: latestBanks.size,
    receivables: agingRows
      .filter((row) => row.period === latestAgingPeriod)
      .reduce((sum, row) => sum + Number(row.total_outstanding ?? 0), 0),
    payables: supplierRows
      .filter((row) => row.period === latestSupplierPeriod)
      .reduce((sum, row) => sum + Math.max(0, Number(row.closing_credit ?? 0) - Number(row.closing_debit ?? 0)), 0),
    accountsCount: accountsResult.count ?? 0,
    trialPeriod,
    totalDebit,
    totalCredit,
    trialEntries: currentTrial.length,
    trialDelta: Math.abs(totalDebit - totalCredit),
  };
}

function Page() {
  const { data: snapshot, isLoading } = useQuery({
    queryKey: ["accounting-workspace-snapshot"],
    queryFn: loadAccountingSnapshot,
  });

  const hasTrialBalance = (snapshot?.trialEntries ?? 0) > 0;
  const isBalanced = hasTrialBalance && (snapshot?.trialDelta ?? 0) <= 0.01;
  const metrics = [
    { label: "المركز النقدي", value: fmtSAR(snapshot?.cashPosition ?? 0), hint: `${snapshot?.bankAccounts ?? 0} حساب بنكي`, icon: Wallet },
    { label: "الذمم المدينة", value: fmtSAR(snapshot?.receivables ?? 0), hint: "مستحقات العملاء", icon: Receipt },
    { label: "الذمم الدائنة", value: fmtSAR(snapshot?.payables ?? 0), hint: "التزامات الموردين", icon: CreditCard },
    { label: "دليل الحسابات", value: String(snapshot?.accountsCount ?? 0), hint: "حساب مسجل", icon: ListTree },
  ];

  return (
    <div className="space-y-7" dir="rtl">
      <PageHeader
        title="المحاسبة والتقارير المالية"
        description="مركز موحد لمتابعة الأرصدة وميزان المراجعة والقوائم المالية"
        actions={
          <>
            <Button asChild variant="outline"><Link to="/trial-balance"><Scale className="h-4 w-4" />ميزان المراجعة</Link></Button>
            <Button asChild><Link to="/financials/reports"><BookOpen className="h-4 w-4" />التقارير المالية</Link></Button>
          </>
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[260px_minmax(0,1fr)]">
        <aside className="xl:sticky xl:top-24">
          <Card className="overflow-hidden">
            <div className="border-b border-border px-5 py-4">
              <div className="text-sm font-bold">المحاسبة</div>
              <div className="mt-1 text-xs text-muted-foreground">الوصول السريع للأعمال المالية</div>
            </div>
            <nav className="space-y-1 p-3">
              {ACCOUNTING_LINKS.map((item) => {
                const Icon = item.icon;
                const active = item.to === "/financials";
                return (
                  <Link
                    key={item.to}
                    to={item.to}
                    className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm transition-colors ${active ? "bg-accent font-semibold text-accent-foreground" : "text-muted-foreground hover:bg-muted hover:text-foreground"}`}
                  >
                    <Icon className="h-[18px] w-[18px]" strokeWidth={1.8} />
                    <span className="flex-1">{item.title}</span>
                    {active && <ArrowLeft className="h-3.5 w-3.5" />}
                  </Link>
                );
              })}
            </nav>
          </Card>
        </aside>

        <section className="min-w-0 space-y-5">
          <AccountingOperationsHub />
          <AccountingDocumentWorkQueue />
          <ManualJournalPanel />
          <Card className="overflow-hidden">
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <div>
                <div className="text-sm font-bold">ملخص المركز المالي</div>
                <div className="mt-1 text-xs text-muted-foreground">قراءة مباشرة من البيانات المحاسبية الحالية</div>
              </div>
              {isLoading && <Loader2 className="h-4 w-4 animate-spin text-primary" />}
            </div>
            <div className="grid sm:grid-cols-2 xl:grid-cols-4">
              {metrics.map((metric, index) => {
                const Icon = metric.icon;
                return (
                  <div key={metric.label} className={`p-5 ${index > 0 ? "border-t sm:border-t-0 sm:border-s border-border" : ""} ${index === 2 ? "sm:border-t xl:border-t-0" : ""}`}>
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="text-xs font-medium text-muted-foreground">{metric.label}</div>
                        <div className="mt-2 text-xl font-bold tabular-nums">{metric.value}</div>
                        <div className="mt-2 text-[11px] text-muted-foreground">{metric.hint}</div>
                      </div>
                      <span className="grid h-10 w-10 place-items-center rounded-xl bg-primary/8 text-primary">
                        <Icon className="h-5 w-5" strokeWidth={1.8} />
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>

          <Card className="p-5 md:p-6">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-2 text-base font-bold">
                  <Scale className="h-5 w-5 text-primary" />
                  حالة ميزان المراجعة
                </div>
                <p className="mt-1 text-xs leading-5 text-muted-foreground">
                  آخر فترة متاحة: {snapshot?.trialPeriod || "لا توجد فترة محملة"}
                </p>
              </div>
              {hasTrialBalance && (
                <Badge variant="outline" className={isBalanced ? "border-success/30 bg-success/10 text-success" : "border-destructive/30 bg-destructive/10 text-destructive"}>
                  {isBalanced ? <CheckCircle2 className="me-1 h-3.5 w-3.5" /> : <AlertTriangle className="me-1 h-3.5 w-3.5" />}
                  {isBalanced ? "متوازن" : "يوجد فرق"}
                </Badge>
              )}
            </div>

            {hasTrialBalance ? (
              <div className="mt-5 grid gap-3 sm:grid-cols-3">
                <div className="rounded-xl border border-border bg-muted/30 p-4">
                  <div className="text-xs text-muted-foreground">إجمالي المدين</div>
                  <div className="mt-2 font-bold tabular-nums">{fmtSAR(snapshot?.totalDebit ?? 0)}</div>
                </div>
                <div className="rounded-xl border border-border bg-muted/30 p-4">
                  <div className="text-xs text-muted-foreground">إجمالي الدائن</div>
                  <div className="mt-2 font-bold tabular-nums">{fmtSAR(snapshot?.totalCredit ?? 0)}</div>
                </div>
                <div className="rounded-xl border border-border bg-muted/30 p-4">
                  <div className="text-xs text-muted-foreground">فرق الميزان</div>
                  <div className={`mt-2 font-bold tabular-nums ${isBalanced ? "text-success" : "text-destructive"}`}>{fmtSAR(snapshot?.trialDelta ?? 0)}</div>
                </div>
              </div>
            ) : (
              <div className="mt-5 flex flex-col items-center justify-center rounded-2xl border border-dashed border-border bg-muted/20 px-6 py-12 text-center">
                <span className="grid h-14 w-14 place-items-center rounded-2xl bg-accent text-primary"><Scale className="h-7 w-7" /></span>
                <div className="mt-4 font-bold">لا توجد بيانات ميزان مراجعة</div>
                <p className="mt-2 max-w-md text-xs leading-6 text-muted-foreground">حمّل ميزان المراجعة لبدء إعداد القوائم والمؤشرات المالية.</p>
                <Button asChild className="mt-4"><Link to="/trial-balance">تحميل ميزان المراجعة</Link></Button>
              </div>
            )}
          </Card>

          <AccountingIntegrationOverview />
        </section>
      </div>

      <section>
        <div className="mb-4">
          <h2 className="text-lg font-bold">القوائم المالية</h2>
          <p className="mt-1 text-xs text-muted-foreground">قوائم مترابطة تُبنى من الحسابات وميزان المراجعة</p>
        </div>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {STATEMENTS.map((item) => {
            const Icon = item.icon;
            return (
              <Link key={item.to} to={item.to} className="group">
                <Card className="h-full p-5 transition-[border-color,transform,box-shadow] group-hover:-translate-y-0.5 group-hover:border-primary/20 group-hover:shadow-md">
                  <div className="flex items-start justify-between gap-3">
                    <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent text-primary">
                      <Icon className="h-5 w-5" strokeWidth={1.8} />
                    </span>
                    <ArrowLeft className="h-4 w-4 text-muted-foreground transition-transform group-hover:-translate-x-1 group-hover:text-primary" />
                  </div>
                  <div className="mt-5 font-bold">{item.title}</div>
                  <p className="mt-2 text-xs leading-5 text-muted-foreground">{item.desc}</p>
                </Card>
              </Link>
            );
          })}
        </div>
      </section>
    </div>
  );
}
