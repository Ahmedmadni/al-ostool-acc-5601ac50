import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ONEXA_PROJECT_COST_POSTING_ENABLED } from "@/lib/runtime-flags";
import { approveOnexaProjectCost, createOnexaProjectCost,
  listOnexaProjectCosts, listProjectCostCenters, postOnexaProjectCost } from "@/lib/projects/project-cost-service";

export function OnexaProjectCostsPanel() {
  const cache = useQueryClient();
  const [centerId, setCenterId] = useState("");
  const [amount, setAmount] = useState("");
  const [reference, setReference] = useState("");
  const [description, setDescription] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const centers = useQuery({ queryKey: ["onexa-project-cost-centers"],
    queryFn: listProjectCostCenters, enabled: ONEXA_PROJECT_COST_POSTING_ENABLED });
  const documents = useQuery({ queryKey: ["onexa-project-costs"],
    queryFn: listOnexaProjectCosts, enabled: ONEXA_PROJECT_COST_POSTING_ENABLED });
  const user = useQuery({ queryKey: ["onexa-project-cost-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    enabled: ONEXA_PROJECT_COST_POSTING_ENABLED });
  const refresh = async () => cache.invalidateQueries({ queryKey: ["onexa-project-costs"] });
  const create = useMutation({
    mutationFn: async () => {
      const center = centers.data?.find((item) => item.id === centerId);
      if (!center) throw new Error("حدد المشروع ومركز التكلفة");
      await createOnexaProjectCost(center, Number(amount), date, reference, description);
    },
    onSuccess: async () => { toast.success("أُنشئ مستند التكلفة وأُرسل للاعتماد");
      setAmount(""); setReference(""); setDescription(""); await refresh(); },
    onError: (error) => toast.error(error.message),
  });
  const transition = useMutation({
    mutationFn: async ({ id, action, accountingDate }: {
      id: string; action: "approve" | "post"; accountingDate: string;
    }) => {
      if (action === "approve") await approveOnexaProjectCost(id);
      else await postOnexaProjectCost(id, accountingDate);
    },
    onSuccess: async () => { toast.success("حُدّث مستند التكلفة"); await refresh(); },
    onError: (error) => toast.error(error.message),
  });
  if (!ONEXA_PROJECT_COST_POSTING_ENABLED) return <Card className="mb-5 p-5 text-sm text-muted-foreground">
    تكاليف مشاريع ONEXA غير مفعّلة؛ يلزم تطبيق حزمة Gate 42 والتحقق من ربط الحسابات والمشروعات.
  </Card>;
  return <Card className="mb-5 space-y-4 p-5">
    <h2 className="font-bold">تكاليف المشاريع المستحقة</h2>
    <p className="text-sm text-muted-foreground">للنفقة المباشرة غير المسجلة في الرواتب أو فواتير الموردين أو حركات المخزون. لا تُعد ترحيل تكلفة موجودة في الأستاذ.</p>
    {(centers.isError || documents.isError) && <p className="text-sm text-destructive">تعذر تحميل بيانات تكاليف ONEXA.</p>}
    <div className="grid gap-3 md:grid-cols-3">
      <select aria-label="المشروع ومركز التكلفة" className="rounded-md border bg-background px-3 py-2 text-sm"
        value={centerId} onChange={(e) => setCenterId(e.target.value)}>
        <option value="">المشروع ومركز التكلفة</option>
        {centers.data?.map((center) => <option key={center.id} value={center.id}>
          {center.project_name} · {center.project_code} · {center.cost_center_code}
        </option>)}
      </select>
      <Input aria-label="المبلغ" type="number" min="0.01" step="0.01" placeholder="المبلغ بالريال"
        value={amount} onChange={(e) => setAmount(e.target.value)} />
      <Input aria-label="تاريخ التكلفة" type="date" value={date}
        onChange={(e) => setDate(e.target.value)} />
      <Input aria-label="مرجع المصدر" placeholder="مرجع المصدر الفريد" value={reference}
        onChange={(e) => setReference(e.target.value)} />
      <Input aria-label="وصف التكلفة" placeholder="وصف التكلفة المستحقة" value={description}
        onChange={(e) => setDescription(e.target.value)} />
    </div>
    <Button disabled={!centerId || !amount || Number(amount) <= 0 || !reference.trim()
      || !description.trim() || create.isPending} onClick={() => create.mutate()}>
      إنشاء وإرسال للاعتماد</Button>
    <div className="space-y-2">
      {documents.data?.map((document) => <div key={document.id}
        className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
        <div><strong>{document.document_number}</strong> · {document.gross_total} ر.س
          <span className="ms-2 text-muted-foreground">{document.status} · {document.external_reference}</span></div>
        {document.status === "submitted" && document.created_by !== user.data &&
          <Button size="sm" variant="outline" disabled={transition.isPending}
            onClick={() => transition.mutate({ id: document.id, action: "approve", accountingDate: document.accounting_date })}>
            اعتماد</Button>}
        {document.status === "approved" && document.created_by !== user.data &&
          <Button size="sm" disabled={transition.isPending}
            onClick={() => { if (window.confirm(`ترحيل تكلفة ${document.document_number}؟`))
              transition.mutate({ id: document.id, action: "post", accountingDate: document.accounting_date }); }}>
            ترحيل إلى الأستاذ</Button>}
      </div>)}
    </div>
  </Card>;
}
