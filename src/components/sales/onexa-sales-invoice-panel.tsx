import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { FilePlus2, Plus, Send, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { createBusinessDocument, listBusinessDocuments, transitionBusinessDocument } from "@/lib/documents/business-document-service";
import { fmtSAR, fmtDate } from "@/lib/format";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

type DraftLine = {
  key: number;
  description: string;
  quantity: string;
  unitPrice: string;
  taxRate: string;
};

const STATUS_LABELS: Record<string, string> = {
  draft: "مسودة",
  submitted: "بانتظار الاعتماد",
  approved: "معتمدة",
  posted: "مرحّلة",
  rejected: "مرفوضة",
  cancelled: "ملغاة",
  reversed: "معكوسة",
};

const roundMoney = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;
const today = () => new Date().toISOString().slice(0, 10);
const newLine = (key: number): DraftLine => ({ key, description: "", quantity: "1", unitPrice: "", taxRate: "15" });

export function OnexaSalesInvoicePanel() {
  const cache = useQueryClient();
  const [open, setOpen] = useState(false);
  const [legalEntityId, setLegalEntityId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [customerId, setCustomerId] = useState("");
  const [documentDate, setDocumentDate] = useState(today);
  const [dueDate, setDueDate] = useState(today);
  const [currency, setCurrency] = useState("SAR");
  const [memo, setMemo] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([newLine(1)]);

  const setup = useQuery({
    queryKey: ["onexa-native-sales-setup"],
    queryFn: async () => {
      const [entities, branches, customers] = await Promise.all([
        supabase.from("onexa_legal_entities").select("id,name_ar,base_currency,is_default").eq("is_active", true).order("is_default", { ascending: false }),
        supabase.from("onexa_branches").select("id,name_ar,legal_entity_id,is_default").eq("is_active", true).order("is_default", { ascending: false }),
        supabase.from("customers").select("id,name,code").eq("is_active", true).order("name"),
      ]);
      const error = entities.error ?? branches.error ?? customers.error;
      if (error) throw error;
      return {
        entities: entities.data ?? [],
        branches: branches.data ?? [],
        customers: customers.data ?? [],
      };
    },
  });

  const documents = useQuery({
    queryKey: ["onexa-sales-business-documents"],
    queryFn: () => listBusinessDocuments("sales", 12),
  });

  const availableBranches = (setup.data?.branches ?? []).filter((branch) => branch.legal_entity_id === legalEntityId);
  const customer = setup.data?.customers.find((row) => row.id === customerId);
  const totals = useMemo(() => {
    const normalized = lines.map((line) => {
      const quantity = Number(line.quantity);
      const unitPrice = Number(line.unitPrice);
      const taxRate = Number(line.taxRate) / 100;
      const net = roundMoney(quantity * unitPrice);
      const tax = roundMoney(net * taxRate);
      return { ...line, quantity, unitPrice, taxRate, net, tax, gross: roundMoney(net + tax) };
    });
    return {
      normalized,
      subtotal: roundMoney(normalized.reduce((sum, line) => sum + (Number.isFinite(line.net) ? line.net : 0), 0)),
      tax: roundMoney(normalized.reduce((sum, line) => sum + (Number.isFinite(line.tax) ? line.tax : 0), 0)),
      gross: roundMoney(normalized.reduce((sum, line) => sum + (Number.isFinite(line.gross) ? line.gross : 0), 0)),
    };
  }, [lines]);

  const reset = () => {
    setCustomerId("");
    setMemo("");
    setDocumentDate(today());
    setDueDate(today());
    setLines([newLine(Date.now())]);
  };

  const create = useMutation({
    mutationFn: async () => {
      if (!legalEntityId || !branchId || !customer) throw new Error("حدد الكيان والفرع والعميل");
      if (!totals.normalized.length || totals.normalized.some((line) =>
        !line.description.trim() || !Number.isFinite(line.quantity) || line.quantity <= 0 ||
        !Number.isFinite(line.unitPrice) || line.unitPrice < 0 ||
        !Number.isFinite(line.taxRate) || line.taxRate < 0 || line.taxRate > 1
      )) throw new Error("راجع وصف البنود والكميات والأسعار والضريبة");
      if (totals.gross <= 0) throw new Error("يجب أن يكون إجمالي الفاتورة أكبر من صفر");

      const id = await createBusinessDocument({
        legalEntityId,
        branchId,
        module: "sales",
        documentType: "sales_invoice",
        documentDate,
        accountingDate: documentDate,
        dueDate,
        currency,
        party: { type: "customer", id: customer.id, nameSnapshot: customer.name },
        origin: "native",
        subtotal: totals.subtotal,
        taxTotal: totals.tax,
        grossTotal: totals.gross,
        memo,
        dimensions: { legalEntity: legalEntityId, branch: branchId, customer: customer.id },
        sourceSnapshot: { entered_from: "native_sales_ui", posting_contract_version: "sales-v1" },
        lines: totals.normalized.map((line, index) => ({
          lineNumber: index + 1,
          description: line.description.trim(),
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          netAmount: line.net,
          taxCode: line.taxRate > 0 ? "VAT_STANDARD" : "VAT_ZERO",
          taxRate: line.taxRate,
          taxAmount: line.tax,
          grossAmount: line.gross,
          accountRole: "sales_revenue",
          dimensions: { legalEntity: legalEntityId, branch: branchId, customer: customer.id },
        })),
      });

      try {
        await transitionBusinessDocument(id, "submitted");
        return { id, status: "submitted" as const };
      } catch {
        return { id, status: "draft" as const };
      }
    },
    onSuccess: async (result) => {
      if (result.status === "submitted") toast.success("تم إنشاء الفاتورة وإرسالها للاعتماد");
      else toast.warning("تم حفظ الفاتورة كمسودة، وتعذر إرسالها للاعتماد");
      setOpen(false);
      reset();
      await cache.invalidateQueries({ queryKey: ["onexa-sales-business-documents"] });
    },
    onError: (error) => toast.error(error.message),
  });

  const openForm = (next: boolean) => {
    setOpen(next);
    if (!next || !setup.data) return;
    const entity = setup.data.entities.find((row) => row.is_default) ?? setup.data.entities[0];
    if (entity && !legalEntityId) {
      setLegalEntityId(entity.id);
      setCurrency(entity.base_currency || "SAR");
      const branch = setup.data.branches.find((row) => row.legal_entity_id === entity.id && row.is_default)
        ?? setup.data.branches.find((row) => row.legal_entity_id === entity.id);
      setBranchId(branch?.id ?? "");
    }
  };

  return (
    <Card className="mb-5 overflow-hidden border-primary/15">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b bg-primary/[0.035] px-5 py-4">
        <div>
          <div className="flex items-center gap-2 font-bold"><FilePlus2 className="h-5 w-5 text-primary" />الفوترة التشغيلية الأصلية</div>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">إنشاء فاتورة داخل ONEXA ثم تمريرها للاعتماد والترحيل، دون الاعتماد على ملف خارجي.</p>
        </div>
        <Dialog open={open} onOpenChange={openForm}>
          <DialogTrigger asChild>
            <Button className="gap-2"><Plus className="h-4 w-4" />فاتورة مبيعات جديدة</Button>
          </DialogTrigger>
          <DialogContent className="max-h-[90vh] max-w-5xl overflow-y-auto" dir="rtl">
            <DialogHeader>
              <DialogTitle>إنشاء فاتورة مبيعات</DialogTitle>
              <DialogDescription>ستُحفظ الفاتورة كمستند أصلي وتُرسل إلى مستخدم آخر للاعتماد.</DialogDescription>
            </DialogHeader>

            {setup.isError ? (
              <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">تعذر تحميل الكيانات أو الفروع أو العملاء.</p>
            ) : (
              <form className="space-y-5" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
                <div className="grid gap-4 md:grid-cols-3">
                  <div className="space-y-2">
                    <Label htmlFor="sales-entity">الكيان القانوني</Label>
                    <select id="sales-entity" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={legalEntityId}
                      onChange={(event) => {
                        const id = event.target.value;
                        setLegalEntityId(id);
                        const entity = setup.data?.entities.find((row) => row.id === id);
                        setCurrency(entity?.base_currency || "SAR");
                        const branch = setup.data?.branches.find((row) => row.legal_entity_id === id && row.is_default)
                          ?? setup.data?.branches.find((row) => row.legal_entity_id === id);
                        setBranchId(branch?.id ?? "");
                      }} required>
                      <option value="">اختر الكيان</option>
                      {setup.data?.entities.map((entity) => <option key={entity.id} value={entity.id}>{entity.name_ar}</option>)}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="sales-branch">الفرع</Label>
                    <select id="sales-branch" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={branchId}
                      onChange={(event) => setBranchId(event.target.value)} required>
                      <option value="">اختر الفرع</option>
                      {availableBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name_ar}</option>)}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="sales-customer">العميل</Label>
                    <select id="sales-customer" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={customerId}
                      onChange={(event) => setCustomerId(event.target.value)} required>
                      <option value="">اختر العميل</option>
                      {setup.data?.customers.map((row) => <option key={row.id} value={row.id}>{row.name} ({row.code})</option>)}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="sales-date">تاريخ الفاتورة</Label>
                    <Input id="sales-date" type="date" value={documentDate} onChange={(event) => setDocumentDate(event.target.value)} required />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="sales-due">تاريخ الاستحقاق</Label>
                    <Input id="sales-due" type="date" min={documentDate} value={dueDate} onChange={(event) => setDueDate(event.target.value)} required />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="sales-currency">العملة</Label>
                    <Input id="sales-currency" value={currency} maxLength={3} onChange={(event) => setCurrency(event.target.value.toUpperCase())} required />
                  </div>
                </div>

                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <Label>بنود الفاتورة</Label>
                    <Button type="button" size="sm" variant="outline" onClick={() => setLines((current) => [...current, newLine(Date.now())])}>
                      <Plus className="h-4 w-4" />إضافة بند
                    </Button>
                  </div>
                  <div className="space-y-3">
                    {lines.map((line, index) => (
                      <div key={line.key} className="grid gap-3 rounded-xl border bg-muted/20 p-3 md:grid-cols-[minmax(220px,1fr)_110px_140px_110px_44px]">
                        <Input aria-label={`وصف البند ${index + 1}`} placeholder="وصف الصنف أو الخدمة" value={line.description}
                          onChange={(event) => setLines((current) => current.map((item) => item.key === line.key ? { ...item, description: event.target.value } : item))} />
                        <Input aria-label={`كمية البند ${index + 1}`} type="number" min="0.000001" step="any" placeholder="الكمية" value={line.quantity}
                          onChange={(event) => setLines((current) => current.map((item) => item.key === line.key ? { ...item, quantity: event.target.value } : item))} />
                        <Input aria-label={`سعر البند ${index + 1}`} type="number" min="0" step="0.01" placeholder="سعر الوحدة" value={line.unitPrice}
                          onChange={(event) => setLines((current) => current.map((item) => item.key === line.key ? { ...item, unitPrice: event.target.value } : item))} />
                        <Input aria-label={`ضريبة البند ${index + 1}`} type="number" min="0" max="100" step="0.01" placeholder="الضريبة %" value={line.taxRate}
                          onChange={(event) => setLines((current) => current.map((item) => item.key === line.key ? { ...item, taxRate: event.target.value } : item))} />
                        <Button type="button" size="icon" variant="ghost" aria-label={`حذف البند ${index + 1}`} disabled={lines.length === 1}
                          onClick={() => setLines((current) => current.filter((item) => item.key !== line.key)}>
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                    ))}
                  </div>
                </div>

                <div className="grid gap-4 md:grid-cols-[1fr_320px]">
                  <div className="space-y-2">
                    <Label htmlFor="sales-memo">ملاحظات</Label>
                    <Textarea id="sales-memo" value={memo} onChange={(event) => setMemo(event.target.value)} placeholder="مرجع العقد أو وصف إضافي..." />
                  </div>
                  <div className="rounded-xl border bg-muted/30 p-4 text-sm">
                    <div className="flex justify-between py-1"><span className="text-muted-foreground">قبل الضريبة</span><strong>{fmtSAR(totals.subtotal)}</strong></div>
                    <div className="flex justify-between py-1"><span className="text-muted-foreground">الضريبة</span><strong>{fmtSAR(totals.tax)}</strong></div>
                    <div className="mt-2 flex justify-between border-t pt-3 text-base"><span>الإجمالي</span><strong>{fmtSAR(totals.gross)}</strong></div>
                  </div>
                </div>

                <div className="flex justify-end gap-2">
                  <Button type="button" variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
                  <Button type="submit" disabled={create.isPending || setup.isLoading}>
                    <Send className="h-4 w-4" />{create.isPending ? "جارٍ الإنشاء..." : "حفظ وإرسال للاعتماد"}
                  </Button>
                </div>
              </form>
            )}
          </DialogContent>
        </Dialog>
      </div>

      <div className="p-5">
        <div className="mb-3 text-sm font-semibold">آخر الفواتير الأصلية</div>
        {documents.isLoading ? (
          <p className="text-sm text-muted-foreground">جارٍ تحميل المستندات...</p>
        ) : documents.isError ? (
          <p className="text-sm text-destructive">تعذر تحميل مستندات ONEXA الأصلية.</p>
        ) : documents.data?.length ? (
          <div className="grid gap-2 md:grid-cols-2">
            {documents.data.map((document) => (
              <div key={document.id} className="flex items-center justify-between gap-3 rounded-xl border px-4 py-3 text-sm">
                <div className="min-w-0">
                  <div className="truncate font-semibold">{document.document_number} · {document.party_name_snapshot || "بدون عميل"}</div>
                  <div className="mt-1 text-xs text-muted-foreground">{fmtDate(document.document_date)} · {fmtSAR(document.gross_total)}</div>
                </div>
                <Badge variant={document.status === "posted" ? "default" : "secondary"}>{STATUS_LABELS[document.status] ?? document.status}</Badge>
              </div>
            ))}
          </div>
        ) : (
          <p className="rounded-xl border border-dashed bg-muted/20 px-4 py-8 text-center text-sm text-muted-foreground">لا توجد فواتير أصلية بعد. أنشئ أول فاتورة من الزر أعلاه.</p>
        )}
      </div>
    </Card>
  );
}
