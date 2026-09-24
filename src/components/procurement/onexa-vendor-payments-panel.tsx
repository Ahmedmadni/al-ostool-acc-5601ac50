import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { BadgeDollarSign } from "lucide-react";
import { OperationalGateCard } from "@/components/operations/operational-gate-card";
import { ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  approveOnexaPayment, createOnexaPayment, listOnexaPayables,
  listOnexaPayments, postOnexaPayment,
} from "@/lib/procurement/supplier-payment-service";

export function OnexaPaymentsPanel() {
  const cache = useQueryClient();
  const [invoiceId, setInvoiceId] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const payables = useQuery({ queryKey: ["onexa-payables"], queryFn: listOnexaPayables,
    enabled: ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED });
  const payments = useQuery({ queryKey: ["onexa-payments"], queryFn: listOnexaPayments,
    enabled: ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED });
  const user = useQuery({ queryKey: ["onexa-payment-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    enabled: ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED });
  const refresh = async () => {
    await Promise.all([
      cache.invalidateQueries({ queryKey: ["onexa-payables"] }),
      cache.invalidateQueries({ queryKey: ["onexa-payments"] }),
    ]);
  };
  const create = useMutation({
    mutationFn: async () => {
      const invoice = payables.data?.find((row) => row.invoice_id === invoiceId);
      if (!invoice) throw new Error("اختر فاتورة ONEXA مرحلة");
      await createOnexaPayment(invoice, Number(amount), date);
    },
    onSuccess: async () => { toast.success("أُنشئ سند الدفع وأُرسل للاعتماد"); setAmount(""); await refresh(); },
    onError: (error) => toast.error(error.message),
  });
  const transition = useMutation({
    mutationFn: async ({ id, action, accountingDate }: { id: string; action: "approve" | "post"; accountingDate: string }) => {
      if (action === "approve") await approveOnexaPayment(id);
      else await postOnexaPayment(id, accountingDate);
    },
    onSuccess: async () => { toast.success("تم تحديث سند الدفع"); await refresh(); },
    onError: (error) => toast.error(error.message),
  });

  if (!ONEXA_SUPPLIER_PAYMENT_POSTING_ENABLED) return (
    <OperationalGateCard
      icon={BadgeDollarSign}
      title="سندات دفع الموردين"
      description="العملية جاهزة في الواجهة وستنشئ سندًا أصليًا مرتبطًا بفاتورة مشتريات مرحلة، مع تخصيص المبلغ واعتماده وترحيله دون كتابة مباشرة في جداول الاستيراد."
      gate="Gate 40"
      actionLabel="إنشاء سند دفع"
    />
  );

  const invoice = payables.data?.find((row) => row.invoice_id === invoiceId);
  return <Card className="mb-5 space-y-4 p-5">
    <div>
      <h2 className="font-bold">مدفوعات ONEXA وربط الذمم</h2>
      <p className="text-sm text-muted-foreground">
        سند مستقل عن المدفوعات القديمة؛ يرتبط بفواتير ONEXA المرحلة فقط، ويحتاج إلى مُعتمد ومُرحّل مختلفين عن المنشئ.
      </p>
    </div>
    {payables.isError || payments.isError ? <p className="text-destructive text-sm">تعذر تحميل مستندات ONEXA.</p> : null}
    <div className="grid gap-3 md:grid-cols-4">
      <select className="rounded-md border bg-background px-3 py-2 text-sm" aria-label="فاتورة ONEXA"
        value={invoiceId} onChange={(event) => { setInvoiceId(event.target.value); setAmount(""); }}>
        <option value="">اختر فاتورة مرحلة</option>
        {payables.data?.map((row) => <option key={row.invoice_id} value={row.invoice_id}>
          {row.document_number} · {Number(row.outstanding_amount).toFixed(2)} {row.currency}
        </option>)}
      </select>
      <Input aria-label="مبلغ الدفع" type="number" min="0.01" step="0.01"
        max={invoice?.outstanding_amount} placeholder="المبلغ" value={amount}
        onChange={(event) => setAmount(event.target.value)} />
      <Input aria-label="تاريخ الدفع" type="date" value={date}
        onChange={(event) => setDate(event.target.value)} />
      <Button disabled={!invoice || create.isPending || !amount ||
        Number(amount) <= 0 || Number(amount) > Number(invoice?.outstanding_amount)}
        onClick={() => create.mutate()}>إنشاء وإرسال للاعتماد</Button>
    </div>
    <div className="space-y-2">
      {payments.data?.map((payment) => <div key={payment.id}
        className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
        <div><strong>{payment.document_number}</strong> · {payment.gross_total} {payment.currency}
          <span className="ms-2 text-muted-foreground">{payment.status}</span></div>
        {payment.status === "submitted" && payment.created_by !== user.data &&
          <Button size="sm" variant="outline" disabled={transition.isPending}
            onClick={() => transition.mutate({ id: payment.id, action: "approve", accountingDate: payment.accounting_date })}>
            اعتماد
          </Button>}
        {payment.status === "approved" && payment.created_by !== user.data &&
          <Button size="sm" disabled={transition.isPending}
            onClick={() => {
              if (window.confirm(`ترحيل الدفع ${payment.document_number}؟`))
                transition.mutate({ id: payment.id, action: "post", accountingDate: payment.accounting_date });
            }}>ترحيل إلى الأستاذ</Button>}
      </div>)}
    </div>
  </Card>;
}
