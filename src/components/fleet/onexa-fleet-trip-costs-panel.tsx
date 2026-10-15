import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ONEXA_FLEET_TRIP_COST_POSTING_ENABLED } from "@/lib/runtime-flags";
import { approveOnexaFleetTripCost,createOnexaFleetTripCost,listFleetTripScopes,
  listOnexaFleetTripCosts,postOnexaFleetTripCost } from "@/lib/fleet/fleet-trip-cost-service";

export function OnexaFleetTripCostsPanel() {
  const cache=useQueryClient();
  const [tripId,setTripId]=useState("");
  const [amount,setAmount]=useState("");
  const [reference,setReference]=useState("");
  const [description,setDescription]=useState("");
  // The local day, not UTC, determines the default accrual accounting date.
  const [date,setDate]=useState(()=>{
    const today=new Date();
    return [today.getFullYear(),String(today.getMonth()+1).padStart(2,"0"),
      String(today.getDate()).padStart(2,"0")].join("-");
  });
  const scopes=useQuery({queryKey:["onexa-fleet-trip-scopes"],queryFn:listFleetTripScopes,
    enabled:ONEXA_FLEET_TRIP_COST_POSTING_ENABLED});
  const documents=useQuery({queryKey:["onexa-fleet-trip-costs"],queryFn:listOnexaFleetTripCosts,
    enabled:ONEXA_FLEET_TRIP_COST_POSTING_ENABLED});
  const user=useQuery({queryKey:["onexa-fleet-trip-user"],
    queryFn:async()=>(await supabase.auth.getUser()).data.user?.id??null,
    enabled:ONEXA_FLEET_TRIP_COST_POSTING_ENABLED});
  const refresh=async()=>cache.invalidateQueries({queryKey:["onexa-fleet-trip-costs"]});
  const create=useMutation({
    mutationFn:async()=>{
      const scope=scopes.data?.find(item=>item.trip_id===tripId);
      if(!scope) throw new Error("حدد الرحلة المسجلة للكيان");
      await createOnexaFleetTripCost(scope,Number(amount),date,reference,description);
    },
    onSuccess:async()=>{toast.success("أُنشئ سند تكلفة الرحلة وأُرسل للاعتماد");
      setAmount("");setReference("");setDescription("");await refresh();},
    onError:(error)=>toast.error(error.message),
  });
  const transition=useMutation({
    mutationFn:async({id,action,accountingDate}:{id:string;action:"approve"|"post";accountingDate:string})=>{
      if(action==="approve") await approveOnexaFleetTripCost(id);
      else await postOnexaFleetTripCost(id,accountingDate);
    },
    onSuccess:async()=>{toast.success("حُدّث سند تكلفة الرحلة");await refresh();},
    onError:(error)=>toast.error(error.message),
  });
  if(!ONEXA_FLEET_TRIP_COST_POSTING_ENABLED) return <Card className="mb-5 p-5 text-sm text-muted-foreground">
    تكاليف رحلات ONEXA غير مفعّلة؛ يلزم فحص حزمة Gate 43 وتأكيد الحسابات وربط الرحلات.
  </Card>;
  return <Card className="space-y-4 p-5">
    <h2 className="font-bold">تكلفة رحلة مستحقة</h2>
    <p className="text-sm text-muted-foreground">تكلفة مباشرة جديدة غير مسجلة سابقاً في الوقود أو الصيانة أو المشتريات أو الرواتب أو تكاليف المشاريع.</p>
    {(scopes.isError||documents.isError)&&<p className="text-sm text-destructive">تعذر تحميل الرحلات أو سندات ONEXA.</p>}
    <div className="grid gap-3 md:grid-cols-3">
      <select aria-label="رحلة مكتملة" className="rounded-md border bg-background px-3 py-2 text-sm"
        value={tripId} onChange={(e)=>setTripId(e.target.value)}>
        <option value="">رحلة مكتملة معتمدة النطاق</option>
        {scopes.data?.map(scope=><option key={scope.trip_id} value={scope.trip_id}>
          {scope.trip_label} · {scope.vehicle_label} · {scope.cost_center_code}
        </option>)}
      </select>
      <Input aria-label="المبلغ" type="number" min="0.01" step="0.01" placeholder="المبلغ بالريال"
        value={amount} onChange={(e)=>setAmount(e.target.value)} />
      <Input aria-label="تاريخ التكلفة" type="date" value={date} onChange={(e)=>setDate(e.target.value)} />
      <Input aria-label="مرجع المصدر" placeholder="مرجع التكلفة الفريد" value={reference}
        onChange={(e)=>setReference(e.target.value)} />
      <Input aria-label="وصف التكلفة" placeholder="وصف المستحق" value={description}
        onChange={(e)=>setDescription(e.target.value)} />
    </div>
    <Button disabled={!tripId||!amount||Number(amount)<=0||!reference.trim()
      ||!description.trim()||create.isPending} onClick={()=>create.mutate()}>إنشاء وإرسال للاعتماد</Button>
    <div className="space-y-2">
      {documents.data?.map(document=><div key={document.id}
        className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
        <div><strong>{document.document_number}</strong> · {document.gross_total} ر.س
          <span className="ms-2 text-muted-foreground">{document.status} · {document.external_reference}</span></div>
        {document.status==="submitted"&&document.created_by!==user.data&&
          <Button size="sm" variant="outline" disabled={transition.isPending}
            onClick={()=>transition.mutate({id:document.id,action:"approve",accountingDate:document.accounting_date})}>
            اعتماد</Button>}
        {document.status==="approved"&&document.created_by!==user.data&&
          <Button size="sm" disabled={transition.isPending}
            onClick={()=>{if(window.confirm(`ترحيل التكلفة ${document.document_number}؟`))
              transition.mutate({id:document.id,action:"post",accountingDate:document.accounting_date});}}>
            ترحيل إلى الأستاذ</Button>}
      </div>)}
    </div>
  </Card>;
}
