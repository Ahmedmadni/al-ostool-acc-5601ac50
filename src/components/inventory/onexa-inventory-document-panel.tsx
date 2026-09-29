import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Boxes, Plus, Send, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import {
  createOnexaInventoryDocument,
  listOnexaInventoryDocuments,
  type InventoryDocumentKind,
} from "@/lib/inventory/inventory-posting-service";
import { fmtDate, fmtSAR } from "@/lib/format";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

type DraftLine = { key: number; itemId: string; quantity: string; unitCost: string };
type Props = { kind: InventoryDocumentKind };
const today = () => new Date().toISOString().slice(0, 10);
const newLine = (key: number): DraftLine => ({ key, itemId: "", quantity: "1", unitCost: "" });
const STATUS_LABELS: Record<string, string> = {
  draft: "مسودة", submitted: "بانتظار الاعتماد", approved: "معتمدة",
  posted: "مرحّلة", rejected: "مرفوضة", cancelled: "ملغاة", reversed: "معكوسة",
};

export function OnexaInventoryDocumentPanel({ kind }: Props) {
  const receipt = kind === "receipt";
  const cache = useQueryClient();
  const [open, setOpen] = useState(false);
  const [legalEntityId, setLegalEntityId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [warehouseId, setWarehouseId] = useState("");
  const [date, setDate] = useState(today);
  const [currency, setCurrency] = useState("SAR");
  const [reference, setReference] = useState("");
  const [costCenter, setCostCenter] = useState("");
  const [memo, setMemo] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([newLine(1)]);

  const setup = useQuery({
    queryKey: ["onexa-inventory-document-setup"],
    queryFn: async () => {
      const db = supabase as any;
      const [entities, branches, warehouses, items] = await Promise.all([
        db.from("onexa_legal_entities").select("id,name_ar,base_currency,is_default").eq("is_active",true).order("is_default",{ascending:false}),
        db.from("onexa_branches").select("id,name_ar,legal_entity_id,is_default").eq("is_active",true).order("is_default",{ascending:false}),
        db.from("inventory_warehouses").select("id,name_ar").eq("is_active",true).order("name_ar"),
        db.from("inventory_items").select("id,sku,name_ar,unit").eq("is_active",true).order("name_ar"),
      ]);
      const error=entities.error??branches.error??warehouses.error??items.error;
      if(error) throw error;
      return {entities:entities.data??[],branches:branches.data??[],warehouses:warehouses.data??[],items:items.data??[]};
    },
  });

  const valuation = useQuery({
    queryKey: ["onexa-inventory-valuation", legalEntityId, branchId, warehouseId],
    enabled: !receipt && !!legalEntityId && !!branchId && !!warehouseId,
    queryFn: async () => {
      const {data,error}=await (supabase as any).from("onexa_inventory_stock_valuation")
        .select("item_id,quantity_on_hand,average_unit_cost")
        .eq("legal_entity_id",legalEntityId).eq("branch_id",branchId).eq("warehouse_id",warehouseId)
        .eq("valuation_currency",currency);
      if(error) throw error;
      return data??[];
    },
  });

  const documents = useQuery({
    queryKey: ["onexa-inventory-documents",kind],
    queryFn: () => listOnexaInventoryDocuments(kind),
  });
  const availableBranches=(setup.data?.branches??[]).filter((row:any)=>row.legal_entity_id===legalEntityId);
  const valuationByItem=useMemo(()=>new Map((valuation.data??[]).map((row:any)=>[row.item_id,row])),[valuation.data]);
  const normalized=useMemo(()=>lines.map((line)=>{
    const item=(setup.data?.items??[]).find((row:any)=>row.id===line.itemId);
    const stock:any=valuationByItem.get(line.itemId);
    const unitCost=receipt?Number(line.unitCost):Number(stock?.average_unit_cost??0);
    return {...line,item,quantity:Number(line.quantity),unitCost,available:Number(stock?.quantity_on_hand??0)};
  }),[lines,receipt,setup.data?.items,valuationByItem]);
  const total=normalized.reduce((sum,line)=>sum+(Number.isFinite(line.quantity*line.unitCost)?line.quantity*line.unitCost:0),0);

  const reset=()=>{setDate(today());setReference("");setCostCenter("");setMemo("");setLines([newLine(Date.now())]);};
  const create=useMutation({
    mutationFn:async()=>{
      if(!legalEntityId||!branchId||!warehouseId) throw new Error("حدد الكيان والفرع والمخزن");
      if(!normalized.length||normalized.some((line)=>!line.item||!Number.isFinite(line.quantity)||line.quantity<=0||
        !Number.isFinite(line.unitCost)||line.unitCost<=0||(!receipt&&line.quantity>line.available)))
        throw new Error(receipt?"راجع الأصناف والكميات وتكاليف الوحدات":"راجع الأصناف والكميات؛ يجب ألا تتجاوز الرصيد المتاح");
      return createOnexaInventoryDocument({kind,legalEntityId,branchId,date,currency,reference,memo,costCenter,
        lines:normalized.map((line)=>({itemId:line.item.id,itemLabel:`${line.item.name_ar} (${line.item.sku})`,
          warehouseId,quantity:line.quantity,unitCost:line.unitCost,unitOfMeasure:line.item.unit,costCenter}))});
    },
    onSuccess:async(result)=>{
      if(result.status==="submitted") toast.success(`تم إنشاء سند ${receipt?"الاستلام":"الصرف"} وإرساله حسب خريطة الاعتماد`);
      else toast.warning(`تم حفظ سند ${receipt?"الاستلام":"الصرف"} كمسودة؛ أكمل إعداد خريطة الاعتماد ثم أرسله`);
      setOpen(false);reset();
      await Promise.all([
        cache.invalidateQueries({queryKey:["onexa-inventory-documents",kind]}),
        cache.invalidateQueries({queryKey:["onexa-document-approval-inbox"]}),
      ]);
    },
    onError:(error)=>toast.error(error.message),
  });

  const openForm=(next:boolean)=>{
    setOpen(next);
    if(!next||!setup.data) return;
    const entity=setup.data.entities.find((row:any)=>row.is_default)??setup.data.entities[0];
    if(entity&&!legalEntityId){
      setLegalEntityId(entity.id);setCurrency(entity.base_currency||"SAR");
      const branch=setup.data.branches.find((row:any)=>row.legal_entity_id===entity.id&&row.is_default)
        ??setup.data.branches.find((row:any)=>row.legal_entity_id===entity.id);
      setBranchId(branch?.id??"");
    }
  };

  return <Card className="mb-5 overflow-hidden border-primary/15">
    <div className="flex flex-wrap items-center justify-between gap-4 border-b bg-primary/[0.035] px-5 py-4">
      <div>
        <div className="flex items-center gap-2 font-bold"><Boxes className="h-5 w-5 text-primary" />
          {receipt?"استلام مخزون محكوم":"صرف مخزون محكوم"}
        </div>
        <p className="mt-1 text-xs leading-5 text-muted-foreground">
          {receipt?"يرفع الكمية والقيمة ثم يقيد المخزون مقابل البضاعة المستلمة غير المفوترة.":
            "يتحقق من الرصيد ويحتسب التكلفة الفعلية بالمتوسط المرجّح ثم يرسلها للاعتماد والترحيل."}
        </p>
      </div>
      <Dialog open={open} onOpenChange={openForm}>
        <DialogTrigger asChild><Button><Plus className="h-4 w-4" />سند {receipt?"استلام":"صرف"} جديد</Button></DialogTrigger>
        <DialogContent className="max-h-[90vh] max-w-5xl overflow-y-auto" dir="rtl">
          <DialogHeader><DialogTitle>إنشاء سند {receipt?"استلام":"صرف"}</DialogTitle>
            <DialogDescription>يُحفظ كسند ONEXA أصلي ثم ينتقل تلقائيًا إلى خريطة اعتماد الشركة.</DialogDescription>
          </DialogHeader>
          {setup.isError?<p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">تعذر تحميل إعدادات المخزون.</p>:
          <form className="space-y-5" onSubmit={(event)=>{event.preventDefault();create.mutate();}}>
            <div className="grid gap-4 md:grid-cols-3">
              <div className="space-y-2"><Label htmlFor={`${kind}-entity`}>الكيان القانوني</Label>
                <select id={`${kind}-entity`} className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={legalEntityId}
                  onChange={(event)=>{const id=event.target.value;setLegalEntityId(id);const entity=setup.data?.entities.find((row:any)=>row.id===id);
                    setCurrency(entity?.base_currency||"SAR");const branch=setup.data?.branches.find((row:any)=>row.legal_entity_id===id&&row.is_default)
                      ??setup.data?.branches.find((row:any)=>row.legal_entity_id===id);setBranchId(branch?.id??"");}} required>
                  <option value="">اختر الكيان</option>{setup.data?.entities.map((row:any)=><option key={row.id} value={row.id}>{row.name_ar}</option>)}
                </select></div>
              <div className="space-y-2"><Label htmlFor={`${kind}-branch`}>الفرع</Label>
                <select id={`${kind}-branch`} className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={branchId} onChange={(e)=>setBranchId(e.target.value)} required>
                  <option value="">اختر الفرع</option>{availableBranches.map((row:any)=><option key={row.id} value={row.id}>{row.name_ar}</option>)}
                </select></div>
              <div className="space-y-2"><Label htmlFor={`${kind}-warehouse`}>المخزن</Label>
                <select id={`${kind}-warehouse`} className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={warehouseId} onChange={(e)=>setWarehouseId(e.target.value)} required>
                  <option value="">اختر المخزن</option>{setup.data?.warehouses.map((row:any)=><option key={row.id} value={row.id}>{row.name_ar}</option>)}
                </select></div>
              <div className="space-y-2"><Label htmlFor={`${kind}-date`}>التاريخ</Label><Input id={`${kind}-date`} type="date" value={date} onChange={(e)=>setDate(e.target.value)} required /></div>
              <div className="space-y-2"><Label htmlFor={`${kind}-reference`}>المرجع</Label><Input id={`${kind}-reference`} value={reference} onChange={(e)=>setReference(e.target.value)} /></div>
              {!receipt&&<div className="space-y-2"><Label htmlFor="issue-cost-center">مركز التكلفة *</Label><Input id="issue-cost-center" value={costCenter} onChange={(e)=>setCostCenter(e.target.value)} required placeholder="مثال: PROJECT-001" /></div>}
            </div>
            <div className="space-y-3">
              <div className="flex items-center justify-between"><Label>الأصناف</Label><Button type="button" size="sm" variant="outline" onClick={()=>setLines((v)=>[...v,newLine(Date.now())])}><Plus className="h-4 w-4" />إضافة صنف</Button></div>
              {normalized.map((line,index)=><div key={line.key} className="grid gap-3 rounded-xl border bg-muted/20 p-3 md:grid-cols-[1fr_120px_150px_44px]">
                <select aria-label={`الصنف ${index+1}`} className="h-10 rounded-md border bg-background px-3 text-sm" value={line.itemId}
                  onChange={(e)=>setLines((rows)=>rows.map((row)=>row.key===line.key?{...row,itemId:e.target.value}:row))} required>
                  <option value="">اختر الصنف</option>{setup.data?.items.map((row:any)=><option key={row.id} value={row.id}>{row.name_ar} ({row.sku})</option>)}
                </select>
                <Input aria-label={`الكمية ${index+1}`} type="number" min="0.000001" step="any" value={line.quantity} onChange={(e)=>setLines((rows)=>rows.map((row)=>row.key===line.key?{...row,quantity:e.target.value}:row))} />
                {receipt?<Input aria-label={`تكلفة الوحدة ${index+1}`} type="number" min="0.0001" step="0.0001" placeholder="تكلفة الوحدة" value={line.unitCost}
                  onChange={(e)=>setLines((rows)=>rows.map((row)=>row.key===line.key?{...row,unitCost:e.target.value}:row))}/>
                  :<div className="rounded-md border bg-background px-3 py-2 text-xs">المتاح {line.available} · المتوسط {fmtSAR(line.unitCost)}</div>}
                <Button type="button" size="icon" variant="ghost" disabled={lines.length===1} onClick={()=>setLines((rows)=>rows.filter((row)=>row.key!==line.key))}><Trash2 className="h-4 w-4 text-destructive" /></Button>
              </div>)}
            </div>
            <div className="grid gap-4 md:grid-cols-[1fr_280px]"><div className="space-y-2"><Label htmlFor={`${kind}-memo`}>ملاحظات</Label><Textarea id={`${kind}-memo`} value={memo} onChange={(e)=>setMemo(e.target.value)} /></div>
              <div className="rounded-xl border bg-muted/30 p-4"><div className="flex justify-between"><span>{receipt?"القيمة":"القيمة التقديرية"}</span><strong>{fmtSAR(total)}</strong></div>{!receipt&&<p className="mt-2 text-[11px] text-muted-foreground">تُثبت القيمة الفعلية عند الترحيل من الرصيد المقفل.</p>}</div></div>
            <div className="flex justify-end gap-2"><Button type="button" variant="outline" onClick={()=>setOpen(false)}>إلغاء</Button><Button type="submit" disabled={create.isPending||setup.isLoading}><Send className="h-4 w-4" />{create.isPending?"جارٍ الإنشاء...":"حفظ وإرسال للاعتماد"}</Button></div>
          </form>}
        </DialogContent>
      </Dialog>
    </div>
    <div className="p-5"><div className="mb-3 text-sm font-semibold">آخر سندات ONEXA</div>
      {documents.isLoading?<p className="text-sm text-muted-foreground">جارٍ التحميل...</p>:documents.isError?<p className="text-sm text-destructive">تعذر تحميل السندات.</p>:documents.data?.length?
        <div className="grid gap-2 md:grid-cols-2">{documents.data.map((document)=><div key={document.id} className="flex items-center justify-between gap-3 rounded-xl border px-4 py-3 text-sm"><div><div className="font-semibold">{document.document_number}</div><div className="mt-1 text-xs text-muted-foreground">{fmtDate(document.document_date)} · {fmtSAR(document.gross_total)}</div></div><Badge variant={document.status==="posted"?"default":"secondary"}>{STATUS_LABELS[document.status]??document.status}</Badge></div>)}</div>
        :<p className="rounded-xl border border-dashed bg-muted/20 px-4 py-8 text-center text-sm text-muted-foreground">لا توجد سندات أصلية بعد.</p>}
    </div>
  </Card>;
}
