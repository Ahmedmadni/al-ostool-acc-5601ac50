import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Calculator, Link2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { supabase } from "@/integrations/supabase/client";
import { fmtNumber, fmtSAR } from "@/lib/format";

/**
 * Read-only Gate74 source attribution, never an accounting or posting action.
 * Parent mounts only after ModuleAccessGuard and both native-feature gates.
 */
type NativeWorkOrderCostTotal = {
  work_order_id: string;
  reconciled_documents: number | string;
  anomaly_documents: number | string;
  reconciled_project_cost_total: number | string;
};

async function loadNativeMaintenanceAttribution() {
  const { data, error } = await (supabase as any)
    .from("onexa_native_maintenance_work_order_cost_totals")
    .select("work_order_id,reconciled_documents,anomaly_documents,reconciled_project_cost_total")
    .order("work_order_id")
    .limit(500);
  if (error) throw error;
  return (data ?? []) as NativeWorkOrderCostTotal[];
}

export function OnexaNativeCostAttributionPanel() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["onexa-native-maintenance-posted-cost-totals"],
    queryFn: loadNativeMaintenanceAttribution,
    retry: false,
  });
  const attributed = (data ?? []).reduce(
    (total, row) => total + Number(row.reconciled_project_cost_total || 0),
    0,
  );
  const reconciled = (data ?? []).reduce(
    (total, row) => total + Number(row.reconciled_documents || 0),
    0,
  );
  const anomalies = (data ?? []).reduce(
    (total, row) => total + Number(row.anomaly_documents || 0),
    0,
  );

  return (
    <Card className="rounded-2xl border-border">
      <CardHeader className="space-y-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <Calculator className="h-5 w-5 text-primary" />
          التكاليف المُرحّلة والمنسوبة لأوامر الصيانة
        </CardTitle>
        <p className="text-sm text-muted-foreground">
          ربط تحليلي فقط مع قيود تكاليف المشاريع المرحلة سابقًا؛ لا ينشئ قيودًا أو يعيد احتساب التكلفة في الأستاذ العام.
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        {error && (
          <p className="rounded-xl border border-destructive/30 p-3 text-sm text-destructive" role="alert">
            تعذر تحميل تسويات Gate 74. تحقق من الترحيل، صلاحيات القراءة وحالة القيود الأصلية.
          </p>
        )}
        {isLoading && <p className="text-sm text-muted-foreground">جارٍ تحميل التكاليف المسندة...</p>}
        {!error && !isLoading && (
          <>
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded-xl border p-4">
                <p className="text-sm text-muted-foreground">التكلفة المُسندة والمطابقة</p>
                <p className="mt-2 font-semibold">{fmtSAR(attributed)}</p>
              </div>
              <div className="rounded-xl border p-4">
                <p className="text-sm text-muted-foreground">المستندات المطابقة</p>
                <p className="mt-2 font-semibold">{fmtNumber(reconciled)}</p>
              </div>
              <div className="rounded-xl border p-4">
                <p className="text-sm text-muted-foreground">مستندات تحتاج مراجعة</p>
                <p className="mt-2 flex items-center gap-2 font-semibold">
                  {anomalies > 0 && <AlertTriangle className="h-4 w-4 text-amber-500" />}
                  {fmtNumber(anomalies)}
                </p>
              </div>
            </div>
            {data?.length === 0 && (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Link2 className="h-4 w-4" />
                لا توجد تكاليف مشاريع مرحلة ومنسوبة لأوامر العمل حتى الآن.
              </div>
            )}
            {(data?.length ?? 0) === 500 && (
              <p className="text-xs text-amber-700">
                المعروض أول 500 أمر عمل فقط. لا تعتمد هذه الإجماليات ككشف نهائي؛ استخدم تقرير SQL المالي الكامل.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
