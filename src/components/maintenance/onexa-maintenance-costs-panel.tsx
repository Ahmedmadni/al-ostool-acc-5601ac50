import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Calculator, Link2, Send } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { fmtDate, fmtSAR } from "@/lib/format";
import { ONEXA_MAINTENANCE_COST_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  createOnexaMaintenanceCost,
  listCompletedMaintenanceWorkOrders,
  listMaintenanceProjectCenters,
  listMaintenanceWorkOrderScopes,
  listOnexaMaintenanceCosts,
  saveMaintenanceWorkOrderScope,
  type MaintenanceCostSource,
} from "@/lib/maintenance/maintenance-cost-service";

const SOURCE_LABELS: Record<MaintenanceCostSource, string> = {
  material: "مواد غير مرحلة من المخزون",
  subcontract: "مقاول باطن غير مفوتر",
  labor: "عمالة غير مرحلة من الرواتب",
  other: "تكلفة تشغيلية مستحقة أخرى",
};

const STATUS_LABELS: Record<string, string> = {
  draft: "مسودة", submitted: "بانتظار الاعتماد", approved: "معتمدة",
  posted: "مرحّلة", rejected: "مرفوضة", cancelled: "ملغاة", reversed: "معكوسة",
};

const today = () => new Date().toISOString().slice(0, 10);

export function OnexaMaintenanceCostsPanel() {
  const cache = useQueryClient();
  const [workOrderId, setWorkOrderId] = useState("");
  const [centerId, setCenterId] = useState("");
  const [scopeId, setScopeId] = useState("");
  const [source, setSource] = useState<MaintenanceCostSource>("subcontract");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(today);
  const [reference, setReference] = useState("");
  const [description, setDescription] = useState("");

  const workOrders = useQuery({
    queryKey: ["onexa-maintenance-completed-work-orders"],
    queryFn: listCompletedMaintenanceWorkOrders,
    enabled: ONEXA_MAINTENANCE_COST_POSTING_ENABLED,
  });
  const centers = useQuery({
    queryKey: ["onexa-maintenance-project-centers"],
    queryFn: listMaintenanceProjectCenters,
    enabled: ONEXA_MAINTENANCE_COST_POSTING_ENABLED,
  });
  const scopes = useQuery({
    queryKey: ["onexa-maintenance-work-order-scopes"],
    queryFn: listMaintenanceWorkOrderScopes,
    enabled: ONEXA_MAINTENANCE_COST_POSTING_ENABLED,
  });
  const documents = useQuery({
    queryKey: ["onexa-maintenance-costs"],
    queryFn: listOnexaMaintenanceCosts,
    enabled: ONEXA_MAINTENANCE_COST_POSTING_ENABLED,
  });

  const refresh = async () => Promise.all([
    cache.invalidateQueries({ queryKey: ["onexa-maintenance-work-order-scopes"] }),
    cache.invalidateQueries({ queryKey: ["onexa-maintenance-costs"] }),
    cache.invalidateQueries({ queryKey: ["onexa-document-approval-inbox"] }),
    cache.invalidateQueries({ queryKey: ["onexa-accounting-posting-inbox"] }),
  ]);

  const saveScope = useMutation({
    mutationFn: () => saveMaintenanceWorkOrderScope(workOrderId, centerId),
    onSuccess: async (id) => {
      toast.success("تم ربط أمر العمل بالمشروع ومركز التكلفة");
      setScopeId(id);
      await refresh();
    },
    onError: (error) => toast.error(error.message),
  });

  const create = useMutation({
    mutationFn: async () => {
      const scope = scopes.data?.find((item) => item.id === scopeId);
      if (!scope) throw new Error("حدد أمر عمل مربوطًا بالمشروع");
      return createOnexaMaintenanceCost({
        scope, source, amount: Number(amount), date, reference, description,
      });
    },
    onSuccess: async (result) => {
      if (result.status === "submitted") toast.success("تم إنشاء تكلفة أمر العمل وإرسالها لخريطة الاعتماد");
      else toast.warning("تم حفظ التكلفة كمسودة؛ أكمل إعداد خريطة الاعتماد ثم أرسلها");
      setAmount(""); setReference(""); setDescription("");
      await refresh();
    },
    onError: (error) => toast.error(error.message),
  });

  if (!ONEXA_MAINTENANCE_COST_POSTING_ENABLED) return null;
  const hasError = workOrders.isError || centers.isError || scopes.isError || documents.isError;

  return (
    <Card className="overflow-hidden rounded-3xl border-primary/20">
      <CardHeader className="border-b bg-primary/[0.035]">
        <CardTitle className="flex items-center gap-2 text-lg">
          <Calculator className="h-5 w-5 text-primary" /> تكلفة أوامر الصيانة والتشغيل
        </CardTitle>
        <p className="text-xs leading-6 text-muted-foreground">
          اربط أمر العمل المكتمل بالمشروع، ثم سجّل فقط التكلفة المستحقة التي لم تُرحّل سابقًا من المشتريات أو الرواتب أو المخزون.
        </p>
      </CardHeader>
      <CardContent className="space-y-6 p-5">
        {hasError && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">تعذر تحميل إعدادات تكاليف الصيانة. تحقق من Gate 42 وGate 66 والصلاحيات.</p>}

        <section className="space-y-3 rounded-2xl border p-4">
          <div className="flex items-center gap-2 font-semibold"><Link2 className="h-4 w-4 text-primary" />ربط أمر العمل بالمشروع</div>
          <div className="grid gap-3 lg:grid-cols-[1fr_1fr_auto]">
            <select aria-label="أمر العمل المكتمل" className="h-10 rounded-md border bg-background px-3 text-sm" value={workOrderId} onChange={(event) => setWorkOrderId(event.target.value)}>
              <option value="">اختر أمر العمل المكتمل</option>
              {workOrders.data?.map((order) => <option key={order.id} value={order.id}>{order.work_order_no} · {order.title}</option>)}
            </select>
            <select aria-label="المشروع ومركز التكلفة" className="h-10 rounded-md border bg-background px-3 text-sm" value={centerId} onChange={(event) => setCenterId(event.target.value)}>
              <option value="">اختر المشروع ومركز التكلفة</option>
              {centers.data?.map((center) => <option key={center.id} value={center.id}>{center.project_name} · {center.project_code} · {center.cost_center_code}</option>)}
            </select>
            <Button type="button" variant="outline" disabled={!workOrderId || !centerId || saveScope.isPending} onClick={() => saveScope.mutate()}>
              <Link2 className="h-4 w-4" />{saveScope.isPending ? "جارٍ الربط..." : "حفظ الربط"}
            </Button>
          </div>
        </section>

        <section className="space-y-4">
          <div className="font-semibold">إنشاء مستند تكلفة مستحقة</div>
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            <div className="space-y-1.5"><Label htmlFor="maintenance-scope">أمر العمل والمشروع</Label>
              <select id="maintenance-scope" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={scopeId} onChange={(event) => setScopeId(event.target.value)}>
                <option value="">اختر الربط المعتمد</option>
                {scopes.data?.map((scope) => <option key={scope.id} value={scope.id}>{scope.work_order_no} · {scope.project_name} · {scope.cost_center_code}</option>)}
              </select></div>
            <div className="space-y-1.5"><Label htmlFor="maintenance-source">مصدر التكلفة</Label>
              <select id="maintenance-source" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={source} onChange={(event) => setSource(event.target.value as MaintenanceCostSource)}>
                {(Object.keys(SOURCE_LABELS) as MaintenanceCostSource[]).map((key) => <option key={key} value={key}>{SOURCE_LABELS[key]}</option>)}
              </select></div>
            <div className="space-y-1.5"><Label htmlFor="maintenance-amount">المبلغ</Label><Input id="maintenance-amount" type="number" min="0.01" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0.00" /></div>
            <div className="space-y-1.5"><Label htmlFor="maintenance-date">التاريخ المحاسبي</Label><Input id="maintenance-date" type="date" value={date} onChange={(event) => setDate(event.target.value)} /></div>
            <div className="space-y-1.5"><Label htmlFor="maintenance-reference">مرجع المصدر الفريد</Label><Input id="maintenance-reference" value={reference} onChange={(event) => setReference(event.target.value)} placeholder="WO-COST-..." /></div>
            <div className="space-y-1.5"><Label htmlFor="maintenance-description">الوصف</Label><Input id="maintenance-description" value={description} onChange={(event) => setDescription(event.target.value)} placeholder="وصف التكلفة المستحقة" /></div>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-amber-500/10 p-3 text-xs leading-5 text-amber-900 dark:text-amber-100">
            <span>لا تستخدم هذا المسار لإعادة تسجيل تكلفة ظهرت بالفعل في الأستاذ عبر فاتورة مورد أو راتب أو صرف مخزون.</span>
            <Button type="button" disabled={!scopeId || Number(amount) <= 0 || !reference.trim() || !description.trim() || create.isPending} onClick={() => create.mutate()}>
              <Send className="h-4 w-4" />{create.isPending ? "جارٍ الإنشاء..." : "إنشاء وإرسال للاعتماد"}
            </Button>
          </div>
        </section>

        <section className="space-y-2">
          <div className="font-semibold">آخر مستندات تكلفة أوامر العمل</div>
          {documents.data?.length ? <div className="grid gap-2 md:grid-cols-2">
            {documents.data.map((document) => <div key={document.id} className="flex items-center justify-between gap-3 rounded-xl border p-3 text-sm">
              <div className="min-w-0"><div className="truncate font-semibold">{document.document_number}</div><div className="mt-1 text-xs text-muted-foreground">{fmtDate(document.document_date)} · {fmtSAR(document.gross_total)}</div></div>
              <Badge variant={document.status === "posted" ? "default" : "secondary"}>{STATUS_LABELS[document.status] ?? document.status}</Badge>
            </div>)}
          </div> : <p className="rounded-xl border border-dashed py-6 text-center text-sm text-muted-foreground">لا توجد مستندات تكلفة أوامر عمل بعد.</p>}
        </section>
      </CardContent>
    </Card>
  );
}
