import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Building2, Link2, ReceiptText, Send, WalletCards } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { fmtDate, fmtSAR } from "@/lib/format";
import { ONEXA_LEASE_ACCOUNTING_ENABLED } from "@/lib/runtime-flags";
import { OnexaLeasePropertyReport } from "@/components/real-estate/onexa-lease-property-report";
import {
  createOnexaLeaseInvoice,
  createOnexaLeaseReceipt,
  listActiveTenantLeases,
  listLeaseAccountingScopes,
  listLeaseBillingCandidates,
  listLeaseReceivables,
  listOnexaBranches,
  listOnexaLeaseDocuments,
  saveLeaseAccountingScope,
} from "@/lib/real-estate/lease-accounting-service";

const today = () => new Date().toISOString().slice(0, 10);
const STATUS: Record<string, string> = {
  draft: "مسودة", submitted: "بانتظار الاعتماد", approved: "معتمدة",
  posted: "مرحّلة", rejected: "مرفوضة", cancelled: "ملغاة", reversed: "معكوسة",
};

export function OnexaLeaseAccountingPanel() {
  const cache = useQueryClient();
  const [leaseId, setLeaseId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [candidateId, setCandidateId] = useState("");
  const [invoiceDate, setInvoiceDate] = useState(today);
  const [taxRate, setTaxRate] = useState<0 | 0.15 | null>(null);
  const [invoiceReference, setInvoiceReference] = useState("");
  const [receivableId, setReceivableId] = useState("");
  const [receiptAmount, setReceiptAmount] = useState("");
  const [receiptDate, setReceiptDate] = useState(today);
  const [receiptReference, setReceiptReference] = useState("");

  const leases = useQuery({ queryKey: ["onexa-active-tenant-leases"], queryFn: listActiveTenantLeases, enabled: ONEXA_LEASE_ACCOUNTING_ENABLED });
  const branches = useQuery({ queryKey: ["onexa-lease-branches"], queryFn: listOnexaBranches, enabled: ONEXA_LEASE_ACCOUNTING_ENABLED });
  const scopes = useQuery({ queryKey: ["onexa-lease-scopes"], queryFn: listLeaseAccountingScopes, enabled: ONEXA_LEASE_ACCOUNTING_ENABLED });
  const candidates = useQuery({ queryKey: ["onexa-lease-billing-candidates"], queryFn: listLeaseBillingCandidates, enabled: ONEXA_LEASE_ACCOUNTING_ENABLED });
  const receivables = useQuery({ queryKey: ["onexa-lease-receivables"], queryFn: listLeaseReceivables, enabled: ONEXA_LEASE_ACCOUNTING_ENABLED });
  const documents = useQuery({ queryKey: ["onexa-lease-documents"], queryFn: listOnexaLeaseDocuments, enabled: ONEXA_LEASE_ACCOUNTING_ENABLED });

  const refresh = async () => Promise.all([
    cache.invalidateQueries({ queryKey: ["onexa-lease-scopes"] }),
    cache.invalidateQueries({ queryKey: ["onexa-lease-billing-candidates"] }),
    cache.invalidateQueries({ queryKey: ["onexa-lease-receivables"] }),
    cache.invalidateQueries({ queryKey: ["onexa-lease-documents"] }),
    cache.invalidateQueries({ queryKey: ["onexa-document-approval-inbox"] }),
    cache.invalidateQueries({ queryKey: ["onexa-accounting-posting-inbox"] }),
    cache.invalidateQueries({ queryKey: ["real-estate-facilities-dashboard"] }),
    cache.invalidateQueries({ queryKey: ["onexa-lease-property-report"] }),
  ]);

  const saveScope = useMutation({
    mutationFn: () => saveLeaseAccountingScope(leaseId, branchId),
    onSuccess: async () => { toast.success("تم ربط عقد المستأجر بالكيان والفرع المحاسبي"); await refresh(); },
    onError: (error) => toast.error(error.message),
  });
  const createInvoice = useMutation({
    mutationFn: async () => {
      const candidate = candidates.data?.find((item) => item.schedule_id === candidateId);
      if (!candidate) throw new Error("حدد استحقاق الإيجار");
      if (taxRate === null) throw new Error("حدد المعالجة الضريبية بعد مراجعة نوع الإيجار");
      return createOnexaLeaseInvoice({ candidate, documentDate: invoiceDate, taxRate, externalReference: invoiceReference });
    },
    onSuccess: async (result) => {
      result.status === "submitted" ? toast.success("تم إنشاء فاتورة الإيجار وإرسالها للاعتماد") : toast.warning("حُفظت فاتورة الإيجار كمسودة حتى تكتمل خريطة الاعتماد");
      setCandidateId(""); setInvoiceReference(""); await refresh();
    },
    onError: (error) => toast.error(error.message),
  });
  const createReceipt = useMutation({
    mutationFn: async () => {
      const receivable = receivables.data?.find((item) => item.invoice_id === receivableId);
      if (!receivable) throw new Error("حدد فاتورة إيجار مرحلة");
      return createOnexaLeaseReceipt({ receivable, amount: Number(receiptAmount), date: receiptDate, externalReference: receiptReference });
    },
    onSuccess: async (result) => {
      result.status === "submitted" ? toast.success("تم إنشاء تحصيل الإيجار وإرساله للاعتماد") : toast.warning("حُفظ التحصيل كمسودة حتى تكتمل خريطة الاعتماد");
      setReceivableId(""); setReceiptAmount(""); setReceiptReference(""); await refresh();
    },
    onError: (error) => toast.error(error.message),
  });

  if (!ONEXA_LEASE_ACCOUNTING_ENABLED) return null;
  const hasError = [leases, branches, scopes, candidates, receivables, documents].some((query) => query.isError);

  return (
    <Card className="overflow-hidden rounded-3xl border-primary/20">
      <CardHeader className="border-b bg-primary/[0.035]">
        <CardTitle className="flex items-center gap-2 text-lg"><Building2 className="h-5 w-5 text-primary" />محاسبة عقود الإيجار والتحصيل</CardTitle>
        <p className="text-xs leading-6 text-muted-foreground">يرتبط كل عقد مستأجر بكيان وفرع ONEXA، ثم تمر الفاتورة والتحصيل بخريطة اعتماد الشركة قبل الترحيل إلى الأستاذ.</p>
      </CardHeader>
      <CardContent className="space-y-6 p-5">
        {hasError && <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">تعذر تحميل طبقة محاسبة الإيجارات. تحقق من Gate 15 وGate 67 والصلاحيات.</p>}

        <section className="space-y-3 rounded-2xl border p-4">
          <div className="flex items-center gap-2 font-semibold"><Link2 className="h-4 w-4 text-primary" />ربط العقد بالنطاق المحاسبي</div>
          <div className="grid gap-3 lg:grid-cols-[1fr_1fr_auto]">
            <select aria-label="عقد المستأجر" className="h-10 rounded-md border bg-background px-3 text-sm" value={leaseId} onChange={(event) => setLeaseId(event.target.value)}>
              <option value="">اختر عقد المستأجر</option>
              {leases.data?.map((lease) => <option key={lease.id} value={lease.id}>{lease.lease_no} · {lease.property_name} · {lease.unit_code}</option>)}
            </select>
            <select aria-label="الفرع المحاسبي" className="h-10 rounded-md border bg-background px-3 text-sm" value={branchId} onChange={(event) => setBranchId(event.target.value)}>
              <option value="">اختر فرع ONEXA</option>
              {branches.data?.map((branch) => <option key={branch.id} value={branch.id}>{branch.code}</option>)}
            </select>
            <Button type="button" variant="outline" disabled={!leaseId || !branchId || saveScope.isPending} onClick={() => saveScope.mutate()}><Link2 className="h-4 w-4" />حفظ الربط</Button>
          </div>
          <p className="text-xs text-muted-foreground">الروابط النشطة: {scopes.data?.length ?? 0}</p>
        </section>

        <div className="grid gap-5 xl:grid-cols-2">
          <section className="space-y-4 rounded-2xl border p-4">
            <div className="flex items-center gap-2 font-semibold"><ReceiptText className="h-4 w-4 text-primary" />إنشاء فاتورة إيجار</div>
            <div className="space-y-3">
              <div className="space-y-1.5"><Label htmlFor="lease-schedule">الاستحقاق</Label><select id="lease-schedule" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={candidateId} onChange={(event) => setCandidateId(event.target.value)}><option value="">اختر الاستحقاق غير المفوتر</option>{candidates.data?.map((item) => <option key={item.schedule_id} value={item.schedule_id}>{item.lease_no} · {item.property_code}/{item.unit_code} · {fmtDate(item.due_date)} · {fmtSAR(item.net_amount)}</option>)}</select></div>
              <div className="grid gap-3 sm:grid-cols-2"><div className="space-y-1.5"><Label htmlFor="lease-invoice-date">تاريخ الفاتورة</Label><Input id="lease-invoice-date" type="date" value={invoiceDate} onChange={(event) => setInvoiceDate(event.target.value)} /></div><div className="space-y-1.5"><Label htmlFor="lease-tax-rate">معالجة الضريبة</Label><select id="lease-tax-rate" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={taxRate ?? ""} onChange={(event) => setTaxRate(event.target.value === "" ? null : Number(event.target.value) as 0 | 0.15)}><option value="">حدد بعد المراجعة</option><option value={0.15}>خاضع 15%</option><option value={0}>معفى / لا تحتسب ضريبة</option></select></div></div>
              <div className="space-y-1.5"><Label htmlFor="lease-invoice-reference">مرجع فريد</Label><Input id="lease-invoice-reference" value={invoiceReference} onChange={(event) => setInvoiceReference(event.target.value)} placeholder="LEASE-INV-..." /></div>
              <Button className="w-full" disabled={!candidateId || taxRate === null || !invoiceReference.trim() || createInvoice.isPending} onClick={() => createInvoice.mutate()}><Send className="h-4 w-4" />إنشاء وإرسال للاعتماد</Button>
            </div>
          </section>

          <section className="space-y-4 rounded-2xl border p-4">
            <div className="flex items-center gap-2 font-semibold"><WalletCards className="h-4 w-4 text-primary" />إنشاء تحصيل إيجار</div>
            <div className="space-y-3">
              <div className="space-y-1.5"><Label htmlFor="lease-receivable">الفاتورة المرحلة</Label><select id="lease-receivable" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={receivableId} onChange={(event) => { const id = event.target.value; setReceivableId(id); const item = receivables.data?.find((row) => row.invoice_id === id); if (item) setReceiptAmount(String(item.outstanding_amount)); }}><option value="">اختر فاتورة إيجار مفتوحة</option>{receivables.data?.map((item) => <option key={item.invoice_id} value={item.invoice_id}>{item.document_number} · {item.property_code} · متبقٍ {fmtSAR(item.outstanding_amount)}</option>)}</select></div>
              <div className="grid gap-3 sm:grid-cols-2"><div className="space-y-1.5"><Label htmlFor="lease-receipt-amount">المبلغ</Label><Input id="lease-receipt-amount" type="number" min="0.01" step="0.01" value={receiptAmount} onChange={(event) => setReceiptAmount(event.target.value)} /></div><div className="space-y-1.5"><Label htmlFor="lease-receipt-date">تاريخ التحصيل</Label><Input id="lease-receipt-date" type="date" value={receiptDate} onChange={(event) => setReceiptDate(event.target.value)} /></div></div>
              <div className="space-y-1.5"><Label htmlFor="lease-receipt-reference">مرجع البنك/السداد</Label><Input id="lease-receipt-reference" value={receiptReference} onChange={(event) => setReceiptReference(event.target.value)} placeholder="LEASE-RCPT-..." /></div>
              <Button className="w-full" disabled={!receivableId || Number(receiptAmount) <= 0 || !receiptReference.trim() || createReceipt.isPending} onClick={() => createReceipt.mutate()}><Send className="h-4 w-4" />إنشاء وإرسال للاعتماد</Button>
            </div>
          </section>
        </div>

        <OnexaLeasePropertyReport scopes={scopes.data ?? []} />

        <section className="space-y-2"><div className="font-semibold">آخر مستندات الإيجارات</div>{documents.data?.length ? <div className="grid gap-2 md:grid-cols-2">{documents.data.map((document) => <div key={document.id} className="flex items-center justify-between gap-3 rounded-xl border p-3 text-sm"><div><div className="font-semibold">{document.document_number}</div><div className="mt-1 text-xs text-muted-foreground">{document.document_type === "lease_invoice" ? "فاتورة إيجار" : "تحصيل إيجار"} · {fmtDate(document.document_date)} · {fmtSAR(document.gross_total)}</div></div><Badge variant={document.status === "posted" ? "default" : "secondary"}>{STATUS[document.status] ?? document.status}</Badge></div>)}</div> : <p className="rounded-xl border border-dashed py-6 text-center text-sm text-muted-foreground">لا توجد مستندات إيجار محاسبية بعد.</p>}</section>
      </CardContent>
    </Card>
  );
}
