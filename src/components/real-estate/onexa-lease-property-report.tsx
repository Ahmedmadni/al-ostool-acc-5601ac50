import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BarChart3 } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { fmtSAR } from "@/lib/format";
import { ONEXA_LEASE_PROPERTY_REPORT_ENABLED } from "@/lib/runtime-flags";
import {
  getLeasePropertyFinancialReport,
  type LeaseAccountingScope,
} from "@/lib/real-estate/lease-accounting-service";

const localDate = (date: Date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;

export function OnexaLeasePropertyReport({ scopes }: { scopes: LeaseAccountingScope[] }) {
  const [propertyId, setPropertyId] = useState("");
  const [from, setFrom] = useState(() => localDate(new Date(new Date().getFullYear(), 0, 1)));
  const [to, setTo] = useState(() => localDate(new Date()));
  const properties = Array.from(new Map(scopes.map((scope) => [scope.property_id, scope])).values());
  const validPeriod = Boolean(from && to && from <= to);
  const report = useQuery({
    queryKey: ["onexa-lease-property-report", propertyId, from, to],
    queryFn: () => getLeasePropertyFinancialReport(propertyId, from, to),
    enabled: ONEXA_LEASE_PROPERTY_REPORT_ENABLED && Boolean(propertyId) && validPeriod,
    retry: false,
  });
  if (!ONEXA_LEASE_PROPERTY_REPORT_ENABLED) return null;

  const totals = (report.data ?? []).reduce(
    (sum, item) => ({
      invoices: sum.invoices + item.invoice_count,
      net: sum.net + item.invoiced_net,
      tax: sum.tax + item.invoiced_tax,
      gross: sum.gross + item.invoiced_gross,
      collected: sum.collected + item.collected_gross,
      outstanding: sum.outstanding + item.outstanding_as_of,
    }),
    { invoices: 0, net: 0, tax: 0, gross: 0, collected: 0, outstanding: 0 },
  );

  return (
    <section className="space-y-4 rounded-2xl border p-4">
      <div className="flex items-center gap-2 font-semibold"><BarChart3 className="h-4 w-4 text-primary" />تقرير فواتير الإيجار للعقار</div>
      <p className="text-xs leading-6 text-muted-foreground">الفواتير والتحصيلات المرحلة فقط بحسب تاريخ القيد المحاسبي. الرصيد يشمل الفواتير السابقة حتى تاريخ النهاية. الاستحقاقات غير المفوترة ليست إيرادًا في هذا التقرير.</p>
      <div className="grid gap-3 md:grid-cols-3">
        <div className="space-y-1.5"><Label htmlFor="lease-report-property">العقار</Label><select id="lease-report-property" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={propertyId} onChange={(event) => setPropertyId(event.target.value)}><option value="">اختر عقارًا مرتبطًا</option>{properties.map((scope) => <option key={scope.property_id} value={scope.property_id}>{scope.property_code} · {scope.property_name}</option>)}</select></div>
        <div className="space-y-1.5"><Label htmlFor="lease-report-from">من تاريخ</Label><Input id="lease-report-from" type="date" value={from} onChange={(event) => setFrom(event.target.value)} /></div>
        <div className="space-y-1.5"><Label htmlFor="lease-report-to">إلى تاريخ</Label><Input id="lease-report-to" type="date" value={to} onChange={(event) => setTo(event.target.value)} /></div>
      </div>
      {!validPeriod && <p className="text-sm text-destructive">أدخل تاريخ بداية يسبق تاريخ النهاية أو يساويه.</p>}
      {report.isLoading && <p className="text-sm text-muted-foreground">جارٍ حساب التقرير...</p>}
      {report.isError && <p className="text-sm text-destructive">تعذر تحميل التقرير. تحقق من تطبيق Gate 69 والصلاحيات.</p>}
      {report.isSuccess && !report.data.length && <p className="rounded-xl border border-dashed p-4 text-center text-sm text-muted-foreground">لا توجد حركات مرحلة لهذا العقار حتى التاريخ المحدد.</p>}
      {report.isSuccess && report.data.length > 0 && <>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <ReportMetric label="صافي الفواتير المرحلة خلال المدة" value={fmtSAR(totals.net)} />
          <ReportMetric label="ضريبة الفواتير خلال المدة" value={fmtSAR(totals.tax)} />
          <ReportMetric label="التحصيل المرحّل خلال المدة" value={fmtSAR(totals.collected)} />
          <ReportMetric label="الرصيد القائم حتى تاريخ النهاية" value={fmtSAR(totals.outstanding)} />
        </div>
        <div className="space-y-2">
          <div className="text-sm font-semibold">التفصيل حسب الكيان القانوني · {totals.invoices} فاتورة خلال المدة</div>
          {report.data.map((item) => <div key={item.legal_entity_id} className="grid gap-2 rounded-xl border p-3 text-sm md:grid-cols-4">
            <span className="font-semibold">{item.legal_entity_code} · {item.invoice_count} فاتورة</span>
            <span>الصافي: {fmtSAR(item.invoiced_net)}</span>
            <span>التحصيل: {fmtSAR(item.collected_gross)}</span>
            <span>الرصيد: {fmtSAR(item.outstanding_as_of)}</span>
          </div>)}
        </div>
      </>}
    </section>
  );
}

function ReportMetric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-muted/40 p-3"><div className="text-xs text-muted-foreground">{label}</div><div className="mt-2 font-bold">{value}</div></div>;
}
