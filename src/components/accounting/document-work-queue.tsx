import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CheckCircle2,
  CircleDollarSign,
  Clock3,
  Inbox,
  Loader2,
  LockKeyhole,
  RefreshCw,
  Send,
  XCircle,
} from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import {
  listAccountingInbox,
  listApprovalInbox,
  transitionBusinessDocument,
  type AccountingInboxItem,
  type ApprovalInboxItem,
} from "@/lib/documents/business-document-service";
import { postSalesInvoice } from "@/lib/sales/sales-posting-service";
import { postPurchaseInvoice } from "@/lib/procurement/purchase-posting-service";
import { postOnexaReceipt } from "@/lib/sales/customer-receipt-service";
import { postOnexaPayment } from "@/lib/procurement/supplier-payment-service";
import { postOnexaBankTransfer } from "@/lib/finance/bank-transfer-service";
import {
  ONEXA_BANK_TRANSFER_POSTING_ENABLED,
  ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED,
  ONEXA_PROCUREMENT_POSTING_ENABLED,
  ONEXA_SALES_POSTING_ENABLED,
  ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED,
} from "@/lib/runtime-flags";
import { fmtDate, fmtSAR } from "@/lib/format";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const TYPE_LABELS: Record<string, string> = {
  sales_invoice: "فاتورة مبيعات",
  purchase_invoice: "فاتورة مشتريات",
  customer_receipt: "تحصيل عميل",
  supplier_payment: "دفعة مورد",
  bank_transfer: "تحويل بنكي",
};

const currentPeriod = () => new Date().toISOString().slice(0, 7);

function describePostingAvailability(item: AccountingInboxItem) {
  if (item.document_type === "sales_invoice") {
    return ONEXA_SALES_POSTING_ENABLED
      ? { enabled: true, label: "جاهز للترحيل" }
      : { enabled: false, label: "يتطلب تفعيل Gate 35" };
  }
  if (item.document_type === "purchase_invoice") {
    return ONEXA_PROCUREMENT_POSTING_ENABLED
      ? { enabled: true, label: "جاهز للترحيل" }
      : { enabled: false, label: "يتطلب تنفيذ وتفعيل Gate 36" };
  }
  if (item.document_type === "customer_receipt") {
    return ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED
      ? { enabled: true, label: "جاهز لترحيل التحصيل" }
      : { enabled: false, label: "يتطلب تنفيذ وتفعيل Gate 39" };
  }
  if (item.document_type === "supplier_payment") {
    return ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED
      ? { enabled: true, label: "جاهز لترحيل الدفعة" }
      : { enabled: false, label: "يتطلب تنفيذ وتفعيل Gate 40" };
  }
  if (item.document_type === "bank_transfer") {
    return ONEXA_BANK_TRANSFER_POSTING_ENABLED
      ? { enabled: true, label: "جاهز لترحيل التحويل" }
      : { enabled: false, label: "يتطلب تنفيذ وتفعيل Gate 41" };
  }
  return { enabled: false, label: "نوع المستند غير مدعوم في صندوق الترحيل" };
}

function DocumentSummary({ item }: { item: ApprovalInboxItem | AccountingInboxItem }) {
  return (
    <div className="min-w-0">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-bold">{item.document_number}</span>
        <Badge variant="outline">{TYPE_LABELS[item.document_type] ?? item.document_type}</Badge>
      </div>
      <div className="mt-1 truncate text-xs text-muted-foreground">
        {item.party_name_snapshot || "بدون طرف"} · {fmtDate(item.document_date)}
      </div>
      <div className="mt-2 text-sm font-bold tabular-nums">{fmtSAR(item.gross_total)}</div>
    </div>
  );
}

export function AccountingDocumentWorkQueue() {
  const cache = useQueryClient();
  const [periodCode, setPeriodCode] = useState(currentPeriod);

  const currentUser = useQuery({
    queryKey: ["onexa-current-user-id"],
    queryFn: async () => {
      const { data, error } = await supabase.auth.getUser();
      if (error) throw error;
      return data.user?.id ?? null;
    },
    staleTime: 5 * 60 * 1000,
  });

  const approvals = useQuery({
    queryKey: ["onexa-document-approval-inbox"],
    queryFn: () => listApprovalInbox(100),
  });

  const postings = useQuery({
    queryKey: ["onexa-accounting-posting-inbox"],
    queryFn: () => listAccountingInbox(100),
  });

  const refreshQueues = async () => {
    await Promise.all([
      cache.invalidateQueries({ queryKey: ["onexa-document-approval-inbox"] }),
      cache.invalidateQueries({ queryKey: ["onexa-accounting-posting-inbox"] }),
      cache.invalidateQueries({ queryKey: ["onexa-sales-business-documents"] }),
      cache.invalidateQueries({ queryKey: ["onexa-purchase-business-documents"] }),
      cache.invalidateQueries({ queryKey: ["onexa-receivables"] }),
      cache.invalidateQueries({ queryKey: ["onexa-receipts"] }),
      cache.invalidateQueries({ queryKey: ["onexa-payables"] }),
      cache.invalidateQueries({ queryKey: ["onexa-payments"] }),
      cache.invalidateQueries({ queryKey: ["onexa-bank-transfers"] }),
    ]);
  };

  const transition = useMutation({
    mutationFn: async (input: { item: ApprovalInboxItem; action: "approved" | "rejected"; reason?: string }) =>
      transitionBusinessDocument(input.item.id, input.action, input.reason),
    onSuccess: async (_status, input) => {
      toast.success(input.action === "approved" ? "تم اعتماد المستند" : "تم رفض المستند وإعادته للمعالجة");
      await refreshQueues();
    },
    onError: (error) => toast.error(error.message),
  });

  const post = useMutation({
    mutationFn: async (item: AccountingInboxItem) => {
      if (!periodCode.trim()) throw new Error("أدخل رمز الفترة المالية أولاً");
      if (item.document_type === "sales_invoice") {
        const result = await postSalesInvoice(item.id, periodCode);
        if (result.status === "disabled") throw new Error("ترحيل المبيعات غير مفعّل في إعدادات التشغيل");
        return result.journalId;
      }
      if (item.document_type === "purchase_invoice") {
        const result = await postPurchaseInvoice(item.id, periodCode);
        if (result.status === "disabled") throw new Error("ترحيل المشتريات غير مفعّل في إعدادات التشغيل");
        return result.journalId;
      }
      if (item.document_type === "customer_receipt") {
        return postOnexaReceipt(item.id, periodCode);
      }
      if (item.document_type === "supplier_payment") {
        return postOnexaPayment(item.id, periodCode);
      }
      if (item.document_type === "bank_transfer") {
        return postOnexaBankTransfer(item.id, periodCode);
      }
      throw new Error("نوع المستند غير مدعوم في صندوق الترحيل");
    },
    onSuccess: async (journalId) => {
      toast.success(`تم الترحيل إلى القيد ${journalId}`);
      await refreshQueues();
    },
    onError: (error) => toast.error(error.message),
  });

  const reject = (item: ApprovalInboxItem) => {
    const reason = window.prompt("اكتب سبب الرفض؛ سيُحفظ في سجل تدقيق المستند:");
    if (!reason?.trim()) return;
    transition.mutate({ item, action: "rejected", reason: reason.trim() });
  };

  const busy = approvals.isFetching || postings.isFetching;
  const hasError = approvals.isError || postings.isError || currentUser.isError;

  return (
    <Card className="overflow-hidden border-primary/15">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b bg-primary/[0.035] px-5 py-4">
        <div>
          <div className="flex items-center gap-2 font-bold">
            <Inbox className="h-5 w-5 text-primary" />
            صندوق الاعتماد والترحيل
          </div>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">
            دورة موحّدة للفواتير وسندات القبض ومدفوعات الموردين والتحويلات البنكية: اعتماد مستقل ثم ترحيل محاسبي محكوم.
          </p>
        </div>
        <Button type="button" size="sm" variant="outline" disabled={busy} onClick={refreshQueues}>
          <RefreshCw className={`h-4 w-4 ${busy ? "animate-spin" : ""}`} />
          تحديث
        </Button>
      </div>

      {hasError && (
        <div className="border-b border-destructive/20 bg-destructive/5 px-5 py-3 text-xs text-destructive">
          تعذر تحميل أحد صناديق العمل. تأكد من تطبيق حزمة الأساس وصلاحيات المستخدم ثم أعد المحاولة.
        </div>
      )}

      <div className="grid divide-y lg:grid-cols-2 lg:divide-x lg:divide-y-0 lg:divide-x-reverse">
        <section className="p-5">
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-2 text-sm font-bold">
                <Clock3 className="h-4 w-4 text-warning" />
                بانتظار الاعتماد
              </div>
              <p className="mt-1 text-[11px] text-muted-foreground">لا يستطيع منشئ المستند اعتماد مستنده بنفسه.</p>
            </div>
            <Badge variant="secondary">{approvals.data?.length ?? 0}</Badge>
          </div>

          {approvals.isLoading ? (
            <div className="flex items-center justify-center py-10 text-sm text-muted-foreground">
              <Loader2 className="me-2 h-4 w-4 animate-spin" />جارٍ التحميل...
            </div>
          ) : approvals.data?.length ? (
            <div className="space-y-3">
              {approvals.data.map((item) => {
                const isCreator = Boolean(currentUser.data && currentUser.data === item.created_by);
                const isPending = transition.isPending && transition.variables?.item.id === item.id;
                return (
                  <div key={item.id} className="rounded-xl border bg-card p-4">
                    <DocumentSummary item={item} />
                    <div className="mt-4 flex flex-wrap items-center gap-2 border-t pt-3">
                      <Button
                        size="sm"
                        disabled={isCreator || isPending || currentUser.isLoading}
                        onClick={() => transition.mutate({ item, action: "approved" })}
                      >
                        {isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
                        اعتماد
                      </Button>
                      <Button size="sm" variant="outline" disabled={isPending} onClick={() => reject(item)}>
                        <XCircle className="h-4 w-4" />
                        رفض
                      </Button>
                      {isCreator && (
                        <span className="inline-flex items-center gap-1 text-[11px] text-warning">
                          <LockKeyhole className="h-3.5 w-3.5" />يلزم مستخدم مالي آخر
                        </span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="rounded-xl border border-dashed bg-muted/20 px-4 py-10 text-center">
              <CheckCircle2 className="mx-auto h-7 w-7 text-success" />
              <p className="mt-2 text-sm font-semibold">لا توجد مستندات بانتظار الاعتماد</p>
            </div>
          )}
        </section>

        <section className="p-5">
          <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
            <div>
              <div className="flex items-center gap-2 text-sm font-bold">
                <CircleDollarSign className="h-4 w-4 text-primary" />
                جاهز للترحيل
              </div>
              <p className="mt-1 text-[11px] text-muted-foreground">المستندات المعتمدة التي لم تُنشئ قيدًا بعد.</p>
            </div>
            <div className="w-32 space-y-1">
              <Label htmlFor="posting-period" className="text-[11px]">رمز الفترة</Label>
              <Input
                id="posting-period"
                value={periodCode}
                onChange={(event) => setPeriodCode(event.target.value)}
                placeholder="2026-09"
                className="h-8 text-xs"
              />
            </div>
          </div>

          {postings.isLoading ? (
            <div className="flex items-center justify-center py-10 text-sm text-muted-foreground">
              <Loader2 className="me-2 h-4 w-4 animate-spin" />جارٍ التحميل...
            </div>
          ) : postings.data?.length ? (
            <div className="space-y-3">
              {postings.data.map((item) => {
                const availability = describePostingAvailability(item);
                const isPending = post.isPending && post.variables?.id === item.id;
                return (
                  <div key={item.id} className="rounded-xl border bg-card p-4">
                    <DocumentSummary item={item} />
                    <div className="mt-4 flex flex-wrap items-center gap-2 border-t pt-3">
                      <Button
                        size="sm"
                        disabled={!availability.enabled || isPending || !periodCode.trim()}
                        onClick={() => post.mutate(item)}
                      >
                        {isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                        ترحيل
                      </Button>
                      <span className={`text-[11px] ${availability.enabled ? "text-success" : "text-muted-foreground"}`}>
                        {availability.label}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="rounded-xl border border-dashed bg-muted/20 px-4 py-10 text-center">
              <CheckCircle2 className="mx-auto h-7 w-7 text-success" />
              <p className="mt-2 text-sm font-semibold">لا توجد مستندات معتمدة بانتظار الترحيل</p>
            </div>
          )}
        </section>
      </div>
    </Card>
  );
}
