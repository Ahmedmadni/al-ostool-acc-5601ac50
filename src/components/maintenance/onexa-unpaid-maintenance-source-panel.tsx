import { useQuery } from "@tanstack/react-query";
import { ClipboardCheck, ShieldAlert } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { fmtSAR } from "@/lib/format";
import { listNativeUnpaidMaintenanceSources } from "@/lib/maintenance/native-unpaid-source-service";

/** Reporting only. Approval, finance posting and document creation are NOT controls here. */
export function OnexaUnpaidMaintenanceSourcePanel() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["onexa-native-maintenance-unpaid-source-evidence"],
    queryFn: listNativeUnpaidMaintenanceSources,
    retry: false,
  });
  const pending = data?.filter((row) => row.status === "pending_review") ?? [];
  const approved = data?.filter((row) => row.status === "approved") ?? [];
  const anomalies = data?.filter((row) =>
    row.status === "linked" && row.current_reconciliation_status !== "reconciled",
  ) ?? [];
  return (
    <Card className="rounded-2xl">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <ClipboardCheck className="h-5 w-5 text-primary" />
          مصادر تكاليف الصيانة غير المرحلة
        </CardTitle>
        <p className="text-sm leading-6 text-muted-foreground">
          هذه متابعة أدلة المصروفات فقط، وليست إثباتًا محاسبيًا. لا تُدرج المواد المصروفة أو الفواتير والرواتب المرحلة مرة أخرى ضمن المصروفات الجديدة.
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && (
          <p role="alert" className="rounded-xl border border-destructive/30 p-3 text-sm text-destructive">
            تعذّر تحميل سجل مصادر الصيانة. راجع الترحيل والصلاحيات واعتماد Gate 75.
          </p>
        )}
        {isLoading && <p className="text-sm text-muted-foreground">جارٍ تحميل مصادر التكاليف...</p>}
        {!error && !isLoading && (
          <>
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded-xl border p-4">
                <div className="text-sm text-muted-foreground">بانتظار المراجعة المالية</div>
                <div className="mt-2 text-xl font-semibold">{pending.length}</div>
              </div>
              <div className="rounded-xl border p-4">
                <div className="text-sm text-muted-foreground">مصادر معتمدة لم تُربط بعد</div>
                <div className="mt-2 text-xl font-semibold">{approved.length}</div>
              </div>
              <div className="rounded-xl border p-4">
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  {anomalies.length > 0 && <ShieldAlert className="h-4 w-4 text-amber-600" />}
                  روابط تحتاج تسوية
                </div>
                <div className="mt-2 text-xl font-semibold">{anomalies.length}</div>
              </div>
            </div>
            <div className="space-y-2">
              {pending.slice(0, 5).map((source) => (
                <div key={source.id} className="flex items-center justify-between gap-4 rounded-xl border p-3 text-sm">
                  <span className="min-w-0 truncate">{source.source_reference}</span>
                  <span className="shrink-0 font-semibold">{fmtSAR(Number(source.amount))}</span>
                </div>
              ))}
              {data?.length === 0 && (
                <p className="text-sm text-muted-foreground">لا توجد مصادر تكاليف غير مرحلة مسجلة حتى الآن.</p>
              )}
            </div>
            {(data?.length ?? 0) === 100 && (
              <p className="text-xs text-amber-700">
                البيانات محدودة بأول 100 سجل؛ الأعداد والإجماليات هنا للمتابعة وليست تقريرًا ماليًا شاملًا.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
