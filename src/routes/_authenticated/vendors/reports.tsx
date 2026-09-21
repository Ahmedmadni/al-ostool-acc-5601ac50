import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Boxes, CheckCircle2, Landmark, ReceiptText } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { useI18n } from "@/lib/i18n";
import { ONEXA_PROCUREMENT_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  fetchPurchaseInventoryReconciliation,
  fetchPurchasePostingConfigurationGaps,
} from "@/lib/procurement/purchase-posting-service";

export const Route = createFileRoute("/_authenticated/vendors/reports")({
  component: ProcurementReportsPage,
});

const amount = (value: number, currency = "SAR") => new Intl.NumberFormat("ar-SA", {
  style: "currency",
  currency,
  maximumFractionDigits: 2,
}).format(value);

function ProcurementReportsPage() {
  const { lang, dir } = useI18n();
  const english = lang === "en";
  const reconciliation = useQuery({
    queryKey: ["purchase-inventory-reconciliation"],
    queryFn: () => fetchPurchaseInventoryReconciliation(),
    enabled: ONEXA_PROCUREMENT_POSTING_ENABLED,
  });
  const configuration = useQuery({
    queryKey: ["purchase-posting-configuration-gaps"],
    queryFn: fetchPurchasePostingConfigurationGaps,
    enabled: ONEXA_PROCUREMENT_POSTING_ENABLED,
  });

  const rows = reconciliation.data ?? [];
  const posted = rows.filter((row) => row.status === "posted");
  const reconciled = posted.filter((row) => row.reconciliation_status === "reconciled");
  const inventory = posted.reduce((total, row) => total + Number(row.posted_inventory_amount), 0);
  const expenses = posted.reduce((total, row) => total + Number(row.expense_amount), 0);
  const assets = posted.reduce((total, row) => total + Number(row.asset_amount), 0);

  if (!ONEXA_PROCUREMENT_POSTING_ENABLED) {
    return (
      <main className="mx-auto w-full max-w-[1400px] p-4 md:p-8" dir={dir}>
        <section className="rounded-3xl border border-amber-500/25 bg-amber-500/[0.06] p-7">
          <AlertTriangle className="h-7 w-7 text-amber-600" />
          <h1 className="mt-4 text-2xl font-black">{english ? "Procurement accounting is staged" : "المحاسبة المتكاملة للمشتريات جاهزة مرحليًا"}</h1>
          <p className="mt-3 max-w-3xl text-sm leading-7 text-muted-foreground">
            {english
              ? "Apply and verify Gate 36, configure the five purchase account roles, then enable the procurement-posting switch."
              : "طبّق واختبر Gate 36، ثم اربط أدوار حسابات المشتريات الخمسة قبل تفعيل مفتاح الترحيل."}
          </p>
        </section>
      </main>
    );
  }

  return (
    <main className="mx-auto w-full max-w-[1500px] space-y-6 p-4 md:p-6 lg:p-8" dir={dir}>
      <section className="overflow-hidden rounded-3xl border border-border bg-card shadow-sm">
        <div className="h-1.5 bg-[linear-gradient(90deg,var(--brand-blue)_0_62%,var(--brand-cyan)_62%_84%,var(--brand-amber)_84%)]" />
        <div className="p-6 md:p-8">
          <Badge variant="secondary">{english ? "Procurement control report" : "تقرير رقابة المشتريات"}</Badge>
          <h1 className="mt-4 text-3xl font-black">{english ? "Purchases, Inventory & GL Reconciliation" : "مطابقة المشتريات والمخزون والأستاذ العام"}</h1>
          <p className="mt-3 max-w-3xl text-sm leading-7 text-muted-foreground">
            {english ? "Supplier invoices are reconciled to AP, input VAT, stock receipts, expenses, assets and the posted journal." : "مطابقة فواتير الموردين مع الذمم وضريبة المدخلات واستلام المخزون والمصروفات والأصول والقيد المرحل."}
          </p>
        </div>
      </section>

      {(configuration.data?.length ?? 0) > 0 && (
        <section className="rounded-2xl border border-destructive/25 bg-destructive/[0.04] p-5">
          <div className="flex items-center gap-2 font-black text-destructive"><AlertTriangle className="h-5 w-5" />{english ? "Posting configuration is incomplete" : "إعدادات الترحيل غير مكتملة"}</div>
          <div className="mt-3 flex flex-wrap gap-2">
            {configuration.data?.map((gap) => <Badge key={`${gap.legal_entity_id}:${gap.account_role}`} variant="outline">{gap.legal_entity_code} • {gap.account_role}</Badge>)}
          </div>
        </section>
      )}

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        {[
          { label: english ? "Posted bills" : "الفواتير المرحلة", value: posted.length, icon: ReceiptText },
          { label: english ? "Reconciled" : "مطابق بالكامل", value: reconciled.length, icon: CheckCircle2 },
          { label: english ? "Inventory" : "مشتريات مخزنية", value: amount(inventory), icon: Boxes },
          { label: english ? "Expenses" : "مصروفات", value: amount(expenses), icon: ReceiptText },
          { label: english ? "Capitalized assets" : "أصول مرسملة", value: amount(assets), icon: Landmark },
        ].map((card) => {
          const Icon = card.icon;
          return <article key={card.label} className="rounded-2xl border border-border bg-card p-5 shadow-sm"><Icon className="h-5 w-5 text-primary" /><div className="mt-4 text-xl font-black">{card.value}</div><div className="mt-1 text-xs font-semibold text-muted-foreground">{card.label}</div></article>;
        })}
      </section>

      <section className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1120px] text-sm">
            <thead className="bg-muted/60 text-xs text-muted-foreground"><tr>{[
              english ? "Bill" : "الفاتورة", english ? "Date" : "التاريخ", english ? "Payable" : "ذمم الموردين",
              english ? "Input VAT" : "ضريبة المدخلات", english ? "Inventory" : "المخزون", english ? "Expense" : "المصروف",
              english ? "Asset" : "الأصل", english ? "Receipts" : "حركات الاستلام", english ? "Status" : "المطابقة",
            ].map((heading) => <th key={heading} className="px-4 py-3 text-start font-black">{heading}</th>)}</tr></thead>
            <tbody className="divide-y divide-border">
              {rows.map((row) => (
                <tr key={row.document_id} className="hover:bg-muted/25">
                  <td className="px-4 py-3 font-bold">{row.document_number}</td>
                  <td className="px-4 py-3 text-muted-foreground">{row.document_date}</td>
                  <td className="px-4 py-3">{amount(Number(row.payable_amount), row.currency)}</td>
                  <td className="px-4 py-3">{amount(Number(row.tax_amount), row.currency)}</td>
                  <td className="px-4 py-3">{amount(Number(row.posted_inventory_amount), row.currency)}</td>
                  <td className="px-4 py-3">{amount(Number(row.expense_amount), row.currency)}</td>
                  <td className="px-4 py-3">{amount(Number(row.asset_amount), row.currency)}</td>
                  <td className="px-4 py-3">{row.actual_movement_count}/{row.expected_movement_count}</td>
                  <td className="px-4 py-3"><Badge variant={row.reconciliation_status === "reconciled" ? "secondary" : "destructive"}>{row.reconciliation_status}</Badge></td>
                </tr>
              ))}
              {!rows.length && !reconciliation.isLoading && <tr><td colSpan={9} className="px-4 py-12 text-center text-muted-foreground">{english ? "No purchase invoices found." : "لا توجد فواتير مشتريات لعرضها."}</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
