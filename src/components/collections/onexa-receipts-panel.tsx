import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";\nimport { HandCoins } from "lucide-react";
import { OperationalGateCard } from "@/components/operations/operational-gate-card";
import { ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  approveOnexaReceipt, createOnexaReceipt, listOnexaReceivables,
  listOnexaReceipts, postOnexaReceipt,
} from "@/lib/sales/customer-receipt-service";

export function OnexaReceiptsPanel() {
  const cache = useQueryClient();
  const [invoiceId, setInvoiceId] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const receivables = useQuery({ queryKey: ["onexa-receivables"], queryFn: listOnexaReceivables,
    enabled: ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED });
  const receipts = useQuery({ queryKey: ["onexa-receipts"], queryFn: listOnexaReceipts,
    enabled: ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED });
  const user = useQuery({ queryKey: ["onexa-receipt-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    enabled: ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED });
  const refresh = async () => {
    await Promise.all([
      cache.invalidateQueries({ queryKey: ["onexa-receivables"] }),
      cache.invalidateQueries({ queryKey: ["onexa-receipts"] }),
    ]);
  };
  const create = useMutation({
    mutationFn: async () => {
      const invoice = receivables.data?.find((row) => row.invoice_id === invoiceId);
      if (!invoice) throw new Error("اختر فاتورة ONEXA مرحلة");
      await createOnexaReceipt(invoice, Number(amount), date);
    },
    onSuccess: async () => { toast.success("أُنشئ سند التحصيل وأُرسل للاعتماد"); setAmount(""); await refresh(); },
    onError: (error) => toast.error(error.message),
  });
  const transition = useMutation({
    mutationFn: async ({ id, action, accountingDate }: { id: string; action: "approve" | "post"; accountingDate: string }) => {
      if (action === "approve") await approveOnexaReceipt(id);
      else await postOnexaReceipt(id, accountingDate);
    },
    onSuccess: async () => { toast.success("تم تحديث سند التحصيل"); await refresh(); },
    onError: (error) => toast.error(error.message),
  });

  if (!ONEXA_CUSTOMER_RECEIPT_POSTING_ENABLED) return (
    <OperationalGateCard
      icon={HandCoins}
      title="سندات تحصيل العملاء"
      description="العملية جاهزة في الواجهة وستنشئ سندًا أصليًا مرتبطًا بفاتورة مرحلة، مع اعتماد وترحيل منفصلين. الإيقاف الحالي يحمي الذمم والأستاذ حتى اكتمال قاعدة البيانات."
      gate="Gate 39"
      actionLabel="إنشاء سند تحصيل"
    />
  );

  const invoice = receivables.data?.find((row) => row.invoice_id === invoiceId);
  return <Card className="mb-5 space-y-4 p-5">
    <div>
      <h2 className="font-bold">تحصيلات ONEXA وربط الذمم</h2>
      <p className="text-sm text-muted-foreground">
        سند مستقل عن التحصيلات القديمة؛ يرتبط بفواتير ONEXA المرحلة فقط، ويحتاج إلى مُعتمد ومُرحّل مختلفين عن المنشئ.
      </p>
    </div>
    {receivables.isError || receipts.isError ? <p className="text-destructive text-sm">تعذر تحميل مستندات ONEXA.</p> : null}
    <div className="grid gap-3 md:grid-cols-4">
      <select className="rounded-md border bg-background px-3 py-2 text-sm" aria-label="فاتورة ONEXA"
        value={invoiceId} onChange={(event) => { setInvoiceId(event.target.value); setAmount(""); }}>
        <option value="">اختر فاتورة مرحلة</option>
        {receivables.data?.map((row) => <option key={row.invoice_id} value={row.invoice_id}>
          {row.document_number} · {Number(row.outstanding_amount).toFixed(2)} {row.currency}
        </option>)}
      </select>
      <Input aria-label="مبلغ التحصيل" type="number" min="0.01" step="0.01"
        max={invoice?.outstanding_amount} placeholder="المبلغ" value={amount}
        onChange={(event) => setAmount(event.target.value)} />
      <Input aria-label="تاريخ التحصيل" type="date" value={date}
        onChange={(event) => setDate(event.target.value)} />
      <Button disabled={!invoice || create.isPending || !amount ||
        Number(amount) <= 0 || Number(amount) > Number(invoice?.outstanding_amount)}
        onClick={() => create.mutate()}>إنشاء وإرسال للاعتماد</Button>
    </div>
    <div className="space-y-2">
      {receipts.data?.map((receipt) => <div key={receipt.id}
        className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
        <div><strong>{receipt.document_number}</strong> · {receipt.gross_total} {receipt.currency}
          <span className="ms-2 text-muted-foreground">{receipt.status}</span></div>
        {receipt.status === "submitted" && receipt.created_by !== user.data &&
          <Button size="sm" variant="outline" disabled={transition.isPending}
            onClick={() => transition.mutate({ id: receipt.id, action: "approve", accountingDate: receipt.accounting_date })}>
            اعتماد
          </Button>}
        {receipt.status === "approved" && receipt.created_by !== user.data &&
          <Button size="sm" disabled={transition.isPending}
            onClick={() => {
              if (window.confirm(`ترحيل التحصيل ${receipt.document_number}؟`))
                transition.mutate({ id: receipt.id, action: "post", accountingDate: receipt.accounting_date });
            }}>ترحيل إلى الأستاذ</Button>}
      </div>)}
    </div>
  </Card>;
}
