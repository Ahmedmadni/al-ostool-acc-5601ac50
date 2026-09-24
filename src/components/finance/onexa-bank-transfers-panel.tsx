import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";\nimport { ArrowLeftRight } from "lucide-react";
import { OperationalGateCard } from "@/components/operations/operational-gate-card";
import { ONEXA_BANK_TRANSFER_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  approveOnexaBankTransfer, createOnexaBankTransfer,
  listOnexaBankTransfers, listTreasuryAccounts, postOnexaBankTransfer,
} from "@/lib/finance/bank-transfer-service";

export function OnexaBankTransfersPanel() {
  const cache = useQueryClient();
  const [sourceId, setSourceId] = useState("");
  const [destinationId, setDestinationId] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const accounts = useQuery({ queryKey: ["onexa-treasury-accounts"], queryFn: listTreasuryAccounts,
    enabled: ONEXA_BANK_TRANSFER_POSTING_ENABLED });
  const transfers = useQuery({ queryKey: ["onexa-bank-transfers"], queryFn: listOnexaBankTransfers,
    enabled: ONEXA_BANK_TRANSFER_POSTING_ENABLED });
  const user = useQuery({ queryKey: ["onexa-bank-transfer-user"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    enabled: ONEXA_BANK_TRANSFER_POSTING_ENABLED });
  const refresh = async () => cache.invalidateQueries({ queryKey: ["onexa-bank-transfers"] });
  const create = useMutation({
    mutationFn: async () => {
      const source = accounts.data?.find((row) => row.id === sourceId);
      const destination = accounts.data?.find((row) => row.id === destinationId);
      if (!source || !destination) throw new Error("حدد الحساب المصدر والوجهة");
      await createOnexaBankTransfer(source, destination, Number(amount), date);
    },
    onSuccess: async () => { toast.success("أُنشئ التحويل وأُرسل للاعتماد"); setAmount(""); await refresh(); },
    onError: (error) => toast.error(error.message),
  });
  const transition = useMutation({
    mutationFn: async ({ id, action, accountingDate }: { id: string; action: "approve" | "post"; accountingDate: string }) => {
      if (action === "approve") await approveOnexaBankTransfer(id);
      else await postOnexaBankTransfer(id, accountingDate);
    },
    onSuccess: async () => { toast.success("تم تحديث التحويل البنكي"); await refresh(); },
    onError: (error) => toast.error(error.message),
  });

  if (!ONEXA_BANK_TRANSFER_POSTING_ENABLED) return (
    <OperationalGateCard
      icon={ArrowLeftRight}
      title="التحويلات البنكية"
      description="نموذج التحويل بين حسابات الخزينة موجود، لكن تشغيله متوقف حتى تجهيز الحسابات البنكية واجتياز فحوص المطابقة والترحيل."
      gate="Gate 41"
      actionLabel="إنشاء تحويل بنكي"
    />
  );
  const source = accounts.data?.find((row) => row.id === sourceId);
  return <Card className="mb-5 space-y-4 p-5">
    <div>
      <h2 className="font-bold">تحويلات ONEXA البنكية</h2>
      <p className="text-sm text-muted-foreground">مستندات مالية معتمدة بين حسابين مؤكدين في نفس الكيان والفرع. كشوف البنك المستوردة مستقلة وتحتاج إلى مطابقة لاحقة.</p>
    </div>
    {(accounts.isError || transfers.isError) && <p className="text-sm text-destructive">تعذر تحميل حسابات ONEXA أو تحويلاتها.</p>}
    <div className="grid gap-3 md:grid-cols-4">
      <select aria-label="حساب المصدر" className="rounded-md border bg-background px-3 py-2 text-sm"
        value={sourceId} onChange={(event) => { setSourceId(event.target.value); setDestinationId(""); }}>
        <option value="">حساب المصدر</option>
        {accounts.data?.map((account) => <option key={account.id} value={account.id}>
          {account.display_name} ({account.account_code})
        </option>)}
      </select>
      <select aria-label="حساب الوجهة" className="rounded-md border bg-background px-3 py-2 text-sm"
        value={destinationId} onChange={(event) => setDestinationId(event.target.value)}>
        <option value="">حساب الوجهة</option>
        {accounts.data?.filter((account) => source && account.id !== source.id
          && account.legal_entity_id === source.legal_entity_id
          && account.branch_id === source.branch_id).map((account) =>
          <option key={account.id} value={account.id}>{account.display_name} ({account.account_code})</option>)}
      </select>
      <Input aria-label="المبلغ" type="number" min="0.01" step="0.01" placeholder="المبلغ بالريال"
        value={amount} onChange={(event) => setAmount(event.target.value)} />
      <Input aria-label="تاريخ التحويل" type="date" value={date}
        onChange={(event) => setDate(event.target.value)} />
    </div>
    <Button disabled={!sourceId || !destinationId || !amount || Number(amount) <= 0 || create.isPending}
      onClick={() => create.mutate()}>إنشاء وإرسال للاعتماد</Button>
    <div className="space-y-2">
      {transfers.data?.map((transfer) => <div key={transfer.id}
        className="flex flex-wrap items-center justify-between gap-3 rounded-md border p-3 text-sm">
        <div><strong>{transfer.document_number}</strong> · {transfer.gross_total} ر.س
          <span className="ms-2 text-muted-foreground">{transfer.status}</span></div>
        {transfer.status === "submitted" && transfer.created_by !== user.data &&
          <Button size="sm" variant="outline" disabled={transition.isPending}
            onClick={() => transition.mutate({ id: transfer.id, action: "approve", accountingDate: transfer.accounting_date })}>
            اعتماد
          </Button>}
        {transfer.status === "approved" && transfer.created_by !== user.data &&
          <Button size="sm" disabled={transition.isPending}
            onClick={() => {
              if (window.confirm(`ترحيل التحويل ${transfer.document_number}؟`))
                transition.mutate({ id: transfer.id, action: "post", accountingDate: transfer.accounting_date });
            }}>ترحيل إلى الأستاذ</Button>}
      </div>)}
    </div>
  </Card>;
}
