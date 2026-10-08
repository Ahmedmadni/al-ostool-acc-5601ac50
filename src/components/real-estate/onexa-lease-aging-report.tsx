import { useQuery } from "@tanstack/react-query";
import { Clock3 } from "lucide-react";
import { fmtDate, fmtSAR } from "@/lib/format";
import { ONEXA_LEASE_AGING_ENABLED } from "@/lib/runtime-flags";
import { getLeaseReceivablesAging } from "@/lib/real-estate/lease-accounting-service";

export function OnexaLeaseAgingReport({ propertyId, asOf }: { propertyId: string; asOf: string }) {
  const report = useQuery({
    queryKey: ["onexa-lease-aging", propertyId, asOf],
    queryFn: () => getLeaseReceivablesAging(propertyId, asOf),
    enabled: ONEXA_LEASE_AGING_ENABLED && Boolean(propertyId) && /^\d{4}-\d{2}-\d{2}$/.test(asOf),
    retry: false,
  });
  if (!ONEXA_LEASE_AGING_ENABLED || !propertyId) return null;

  return <section className="space-y-3 rounded-2xl border p-4">
    <div className="flex items-center gap-2 font-semibold"><Clock3 className="h-4 w-4 text-primary" />أعمار مديونيات الإيجار حتى {fmtDate(asOf)}</div>
    <p className="text-xs leading-6 text-muted-foreground">تُحسب من الرصيد الإجمالي للفواتير المرحلة بعد التحصيلات المرحلة حتى التاريخ المحدد. اليوم المحدد ضمن غير المتأخر، وتُعرض أعلى 25 حالة بحسب المبلغ المتأخر.</p>
    {report.isLoading && <p className="text-sm text-muted-foreground">جارٍ حساب أعمار المديونيات...</p>}
    {report.isError && <p className="text-sm text-destructive">تعذر تحميل الأعمار. تحقق من تطبيق Gate 70 والصلاحيات.</p>}
    {report.isSuccess && <>
      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
        {[
          ["غير متأخر", report.data.current_amount],
          ["1–30 يومًا", report.data.days_1_30],
          ["31–60 يومًا", report.data.days_31_60],
          ["61–90 يومًا", report.data.days_61_90],
          ["أكثر من 90 يومًا", report.data.days_over_90],
        ].map(([label, amount]) => <div key={label} className="rounded-xl bg-muted/40 p-3"><div className="text-xs text-muted-foreground">{label}</div><div className="mt-2 font-bold">{fmtSAR(Number(amount))}</div></div>)}
      </div>
      <div className="text-sm font-semibold">إجمالي قائم {fmtSAR(report.data.outstanding)} · {report.data.invoice_count} فاتورة · {report.data.customer_count} عميل/كيان</div>
      {report.data.outstanding === 0 && <p className="text-sm text-muted-foreground">لا توجد مديونيات إيجار مفتوحة لهذا العقار.</p>}
      {report.data.top_customers.length > 0 && <div className="space-y-2">
        <div className="text-sm font-semibold">أعلى المديونيات المتأخرة</div>
        {report.data.top_customers.map((item) => <div key={`${item.legal_entity_id}:${item.customer_id}`} className="grid gap-2 rounded-xl border p-3 text-sm md:grid-cols-4">
          <span className="font-semibold">{item.customer_name} · {item.legal_entity_code}</span>
          <span>القائم: {fmtSAR(item.outstanding)}</span>
          <span>المتأخر: {fmtSAR(item.overdue)}</span>
          <span>أقدم استحقاق: {fmtDate(item.oldest_due_date)}</span>
        </div>)}
        {report.data.customer_count > 25 && <p className="text-xs text-muted-foreground">تُعرض أول 25 حالة؛ الإجماليات تشمل جميع العملاء.</p>}
      </div>}
    </>}
  </section>;
}
