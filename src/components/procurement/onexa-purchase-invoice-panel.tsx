import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { PackagePlus, Plus, Send, Trash2 } from "lucide-react";
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

type PurchaseRole = "purchase_expense" | "inventory" | "fixed_asset_cost";
type DraftLine = {
  key: number;
  description: string;
  quantity: string;
  unitPrice: string;
  taxRate: string;
  accountRole: PurchaseRole;
  itemId: string;
  warehouseId: string;
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

const CLASSIFICATION_LABELS: Record<PurchaseRole, string> = {
  purchase_expense: "مصروف تشغيلي",
  inventory: "مخزون",
  fixed_asset_cost: "أصل ثابت",
};

const roundMoney = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;
const today = () => new Date().toISOString().slice(0, 10);
const newLine = (key: number): DraftLine => ({
  key,
  description: "",
  quantity: "1",
  unitPrice: "",
  taxRate: "15",
  accountRole: "purchase_expense",
  itemId: "",
  warehouseId: "",
});

export function OnexaPurchaseInvoicePanel() {
  const cache = useQueryClient();
  const [open, setOpen] = useState(false);
  const [legalEntityId, setLegalEntityId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [vendorId, setVendorId] = useState("");
  const [documentDate, setDocumentDate] = useState(today);
  const [dueDate, setDueDate] = useState(today);
  const [currency, setCurrency] = useState("SAR");
  const [externalReference, setExternalReference] = useState("");
  const [memo, setMemo] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([newLine(1)]);

  const setup = useQuery({
    queryKey: ["onexa-native-purchase-setup"],
    queryFn: async () => {
      const [entities, branches, vendors, items, warehouses] = await Promise.all([
        supabase.from("onexa_legal_entities").select("id,name_ar,base_currency,is_default").eq("is_active", true).order("is_default", { ascending: false }),
        supabase.from("onexa_branches").select("id,name_ar,legal_entity_id,is_default").eq("is_active", true).order("is_default", { ascending: false }),
        supabase.from("vendors").select("id,name,code").eq("is_active", true).order("name"),
        supabase.from("inventory_items").select("id,name_ar,sku,unit").eq("is_active", true).order("name_ar"),
        supabase.from("inventory_warehouses").select("id,name_ar,code").eq("is_active", true).order("name_ar"),
      ]);
      const error = entities.error ?? branches.error ?? vendors.error ?? items.error ?? warehouses.error;
      if (error) throw error;
      return {
        entities: entities.data ?? [],
        branches: branches.data ?? [],
        vendors: vendors.data ?? [],
        items: items.data ?? [],
        warehouses: warehouses.data ?? [],
      };
    },
  });

  const documents = useQuery({
    queryKey: ["onexa-purchase-business-documents"],
    queryFn: async () => (await listBusinessDocuments("procurement", 30))
      .filter((document) => document.document_type === "purchase_invoice")
      .slice(0, 12),
  });

  const availableBranches = (setup.data?.branches ?? []).filter((branch) => branch.legal_entity_id === legalEntityId);
  const vendor = setup.data?.vendors.find((row) => row.id === vendorId);
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
    setVendorId("");
    setExternalReference("");
    setMemo("");
    setDocumentDate(today());
    setDueDate(today());
    setLines([newLine(Date.now())]);
  };

  const create = useMutation({
    mutationFn: async () => {
      if (!legalEntityId || !branchId || !vendor) throw new Error("حدد الكيان والفرع والمورد");
      if (!totals.normalized.length || totals.normalized.some((line) =>
        !line.description.trim() || !Number.isFinite(line.quantity) || line.quantity <= 0 ||
        !Number.isFinite(line.unitPrice) || line.unitPrice < 0 ||
        !Number.isFinite(line.taxRate) || line.taxRate < 0 || line.taxRate > 1 ||
        (line.accountRole === "inventory" && (!line.itemId || !line.warehouseId))
      )) throw new Error("راجع البنود والتصنيف؛ بند المخزون يتطلب صنفًا ومستودعًا");
      if (totals.gross <= 0) throw new Error("يجب أن يكون إجمالي الفاتورة أكبر من صفر");

      const id = await createBusinessDocument({
        legalEntityId,
        branchId,
        module: "procurement",
        documentType: "purchase_invoice",
        documentDate,
        accountingDate: documentDate,
        dueDate,
        currency,
        party: { type: "vendor", id: vendor.id, nameSnapshot: vendor.name },
        externalReference,
        origin: "native",
        subtotal: totals.subtotal,
        taxTotal: totals.tax,
        grossTotal: totals.gross,
        memo,
        dimensions: { legalEntity: legalEntityId, branch: branchId, vendor: vendor.id },
        sourceSnapshot: { entered_from: "native_purchase_ui", posting_contract_version: "procurement-v1" },
        lines: totals.normalized.map((line, index) => ({
          lineNumber: index + 1,
          description: line.description.trim(),
          quantity: line.quantity,
          unitOfMeasure: line.accountRole === "inventory"
            ? setup.data?.items.find((item) => item.id === line.itemId)?.unit
            : undefined,
          unitPrice: line.unitPrice,
          netAmount: line.net,
          taxCode: line.taxRate > 0 ? "VAT_STANDARD" : "VAT_ZERO",
          taxRate: line.taxRate,
          taxAmount: line.tax,
          grossAmount: line.gross,
          itemId: line.accountRole === "inventory" ? line.itemId : undefined,
          warehouseId: line.accountRole === "inventory" ? line.warehouseId : undefined,
          accountRole: line.accountRole,
          dimensions: {
            legalEntity: legalEntityId,
            branch: branchId,
            vendor: vendor.id,
            ...(line.accountRole === "inventory" ? { warehouse: line.warehouseId } : {}),
          },
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
      if (result.status === "submitted") toast.success("تم إنشاء فاتورة الشراء وإرسالها للاعتماد");
      else toast.warning("تم حفظ فاتورة الشراء كمسودة، وتعذر إرسالها للاعتماد");
      setOpen(false);
      reset();
      await cache.invalidateQueries({ queryKey: ["onexa-purchase-business-documents"] });
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

  const updateLine = (key: number, patch: Partial<DraftLine>) =>
    setLines((current) => current.map((line) => line.key === key ? { ...line, ...patch } : line));

  return (
    <Card className="mb-5 overflow-hidden border-primary/15">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b bg-primary/[0.035] px-5 py-4">
        <div>
          <div className="flex items-center gap-2 font-bold"><PackagePlus className="h-5 w-5 text-primary" />المشتريات التشغيلية الأصلية</div>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">فاتورة مورد محكومة مع تصنيف كل بند إلى مصروف أو مخزون أو أصل ثابت.</p>
        </div>
        <Dialog open={open} onOpenChange={openForm}>
          <DialogTrigger asChild>
            <Button className="gap-2"><Plus className="h-4 w-4" />فاتورة مشتريات جديدة</Button>
          </DialogTrigger>
          <DialogContent className="max-h-[92vh] max-w-5xl overflow-y-auto" dir="rtl">
            <DialogHeader>
              <DialogTitle>إنشاء فاتورة مشتريات</DialogTitle>
              <DialogDescription>يحدد تصنيف كل بند حسابه المحاسبي وأثره التشغيلي عند الترحيل.</DialogDescription>
            </DialogHeader>

            {setup.isError ? (
              <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">تعذر تحميل بيانات الكيانات أو الموردين أو المخزون.</p>
            ) : (
              <form className="space-y-5" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
                <div className="grid gap-4 md:grid-cols-3">
                  <div className="space-y-2">
                    <Label htmlFor="purchase-entity">الكيان القانوني</Label>
                    <select id="purchase-entity" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={legalEntityId}
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
                    <Label htmlFor="purchase-branch">الفرع</Label>
                    <select id="purchase-branch" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={branchId}
                      onChange={(event) => setBranchId(event.target.value)} required>
                      <option value="">اختر الفرع</option>
                      {availableBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name_ar}</option>)}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="purchase-vendor">المورد</Label>
                    <select id="purchase-vendor" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={vendorId}
                      onChange={(event) => setVendorId(event.target.value)} required>
                      <option value="">اختر المورد</option>
                      {setup.data?.vendors.map((row) => <option key={row.id} value={row.id}>{row.name} ({row.code})</option>)}
                    </select>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="purchase-date">تاريخ الفاتورة</Label>
                    <Input id="purchase-date" type="date" value={documentDate} onChange={(event) => setDocumentDate(event.target.value)} required />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="purchase-due">تاريخ الاستحقاق</Label>
                    <Input id="purchase-due" type="date" min={documentDate} value={dueDate} onChange={(event) => setDueDate(event.target.value)} required />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="purchase-reference">مرجع فاتورة المورد</Label>
                    <Input id="purchase-reference" value={externalReference} onChange={(event) => setExternalReference(event.target.value)} placeholder="رقم فاتورة المورد" />
                  </div>
                </div>

                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <Label>بنود الفاتورة</Label>
                    <Button type="button" size="sm" variant="outline" onClick={() => setLines((current) => [...current, newLine(Date.now())])}>
                      <Plus className="h-4 w-4" />إضافة بند
                    </Button>
                  </div>
                  {lines.map((line, index) => (
                    <div key={line.key} className="space-y-3 rounded-xl border bg-muted/20 p-3">
                      <div className="grid gap-3 md:grid-cols-[minmax(240px,1fr)_190px_44px]">
                        <Input aria-label={`وصف بند المشتريات ${index + 1}`} placeholder="وصف الصنف أو الخدمة" value={line.description}
                          onChange={(event) => updateLine(line.key, { description: event.target.value })} />
                        <select aria-label={`تصنيف بند المشتريات ${index + 1}`} className="h-10 rounded-md border bg-background px-3 text-sm" value={line.accountRole}
                          onChange={(event) => updateLine(line.key, { accountRole: event.target.value as PurchaseRole, itemId: "", warehouseId: "" })}>
                          {(Object.keys(CLASSIFICATION_LABELS) as PurchaseRole[]).map((role) => <option key={role} value={role}>{CLASSIFICATION_LABELS[role]}</option>)}
                        </select>
                        <Button type="button" size="icon" variant="ghost" aria-label={`حذف بند المشتريات ${index + 1}`} disabled={lines.length === 1}
                          onClick={() => setLines((current) => current.filter((item) => item.key !== line.key))}>
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                      <div className="grid gap-3 md:grid-cols-3 xl:grid-cols-5">
                        <Input aria-label={`كمية بند المشتريات ${index + 1}`} type="number" min="0.000001" step="any" placeholder="الكمية" value={line.quantity}
                          onChange={(event) => updateLine(line.key, { quantity: event.target.value })} />
                        <Input aria-label={`سعر بند المشتريات ${index + 1}`} type="number" min="0" step="0.01" placeholder="سعر الوحدة" value={line.unitPrice}
                          onChange={(event) => updateLine(line.key, { unitPrice: event.target.value })} />
                        <Input aria-label={`ضريبة بند المشتريات ${index + 1}`} type="number" min="0" max="100" step="0.01" placeholder="الضريبة %" value={line.taxRate}
                          onChange={(event) => updateLine(line.key, { taxRate: event.target.value })} />
                        {line.accountRole === "inventory" && (
                          <>
                            <select aria-label={`صنف المخزون ${index + 1}`} className="h-10 rounded-md border bg-background px-3 text-sm" value={line.itemId}
                              onChange={(event) => updateLine(line.key, { itemId: event.target.value })}>
                              <option value="">اختر الصنف</option>
                              {setup.data?.items.map((item) => <option key={item.id} value={item.id}>{item.name_ar} ({item.sku})</option>)}
                            </select>
                            <select aria-label={`مستودع بند المشتريات ${index + 1}`} className="h-10 rounded-md border bg-background px-3 text-sm" value={line.warehouseId}
                              onChange={(event) => updateLine(line.key, { warehouseId: event.target.value })}>
                              <option value="">اختر المستودع</option>
                              {setup.data?.warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>{warehouse.name_ar} ({warehouse.code})</option>)}
                            </select>
                          </>
                        )}
                      </div>
                    </div>
                  ))}
                </div>

                <div className="grid gap-4 md:grid-cols-[1fr_320px]">
                  <div className="space-y-2">
                    <Label htmlFor="purchase-memo">ملاحظات</Label>
                    <Textarea id="purchase-memo" value={memo} onChange={(event) => setMemo(event.target.value)} placeholder="رقم أمر الشراء أو المشروع أو وصف إضافي..." />
                  </div>
                  <div className="rounded-xl border bg-muted/30 p-4 text-sm">
                    <div className="flex justify-between py-1"><span className="text-muted-foreground">قبل الضريبة</span><strong>{fmtSAR(totals.subtotal)}</strong></div>
                    <div className="flex justify-between py-1"><span className="text-muted-foreground">ضريبة المدخلات</span><strong>{fmtSAR(totals.tax)}</strong></div>
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
        <div className="mb-3 text-sm font-semibold">آخر فواتير المشتريات الأصلية</div>
        {documents.isLoading ? (
          <p className="text-sm text-muted-foreground">جارٍ تحميل المستندات...</p>
        ) : documents.isError ? (
          <p className="text-sm text-destructive">تعذر تحميل مستندات المشتريات الأصلية.</p>
        ) : documents.data?.length ? (
          <div className="grid gap-2 md:grid-cols-2">
            {documents.data.map((document) => (
              <div key={document.id} className="flex items-center justify-between gap-3 rounded-xl border px-4 py-3 text-sm">
                <div className="min-w-0">
                  <div className="truncate font-semibold">{document.document_number} · {document.party_name_snapshot || "بدون مورد"}</div>
                  <div className="mt-1 text-xs text-muted-foreground">{fmtDate(document.document_date)} · {fmtSAR(document.gross_total)}</div>
                </div>
                <Badge variant={document.status === "posted" ? "default" : "secondary"}>{STATUS_LABELS[document.status] ?? document.status}</Badge>
              </div>
            ))}
          </div>
        ) : (
          <p className="rounded-xl border border-dashed bg-muted/20 px-4 py-8 text-center text-sm text-muted-foreground">لا توجد فواتير مشتريات أصلية بعد.</p>
        )}
      </div>
    </Card>
  );
}
