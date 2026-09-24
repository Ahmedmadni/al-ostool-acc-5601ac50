import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BookPlus, Plus, Send, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { ONEXA_MANUAL_JOURNALS_ENABLED } from "@/lib/runtime-flags";
import { createManualJournal, listManualJournals, postManualJournal, transitionManualJournal } from "@/lib/accounting/manual-journal-service";
import { OperationalGateCard } from "@/components/operations/operational-gate-card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type DraftLine = {
  key: number;
  accountCode: string;
  debit: string;
  credit: string;
  description: string;
};

const today = () => new Date().toISOString().slice(0, 10);
const newLine = (key: number): DraftLine => ({ key, accountCode: "", debit: "", credit: "", description: "" });
const STATUS_LABELS: Record<string, string> = {
  draft: "مسودة",
  submitted: "بانتظار الاعتماد",
  approved: "معتمد",
  posted: "مرحّل",
  rejected: "مرفوض",
  cancelled: "ملغى",
  reversed: "معكوس",
};

export function ManualJournalPanel() {
  const cache = useQueryClient();
  const [open, setOpen] = useState(false);
  const [legalEntityId, setLegalEntityId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [accountingDate, setAccountingDate] = useState(today);
  const [currency, setCurrency] = useState("SAR");
  const [memo, setMemo] = useState("");
  const [reference, setReference] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([newLine(1), newLine(2)]);

  const setup = useQuery({
    queryKey: ["onexa-manual-journal-setup"],
    enabled: ONEXA_MANUAL_JOURNALS_ENABLED,
    queryFn: async () => {
      const [entities, branches, accounts, user] = await Promise.all([
        supabase.from("onexa_legal_entities").select("id,name_ar,base_currency,is_default").eq("is_active", true).order("is_default", { ascending: false }),
        supabase.from("onexa_branches").select("id,name_ar,legal_entity_id,is_default").eq("is_active", true).order("is_default", { ascending: false }),
        supabase.from("chart_of_accounts").select("code,name_ar").eq("is_active", true).eq("account_type", "detail").order("code"),
        supabase.auth.getUser(),
      ]);
      const error = entities.error ?? branches.error ?? accounts.error;
      if (error) throw error;
      return {
        entities: entities.data ?? [],
        branches: branches.data ?? [],
        accounts: accounts.data ?? [],
        userId: user.data.user?.id ?? null,
      };
    },
  });

  const journals = useQuery({
    queryKey: ["onexa-manual-journals"],
    queryFn: () => listManualJournals(50),
    enabled: ONEXA_MANUAL_JOURNALS_ENABLED,
  });

  const totals = useMemo(() => ({
    debit: lines.reduce((sum, line) => sum + (Number(line.debit) || 0), 0),
    credit: lines.reduce((sum, line) => sum + (Number(line.credit) || 0), 0),
  }), [lines]);
  const difference = Math.abs(totals.debit - totals.credit);
  const availableBranches = (setup.data?.branches ?? []).filter((branch) => branch.legal_entity_id === legalEntityId);

  const reset = () => {
    setMemo("");
    setReference("");
    setAccountingDate(today());
    setLines([newLine(Date.now()), newLine(Date.now() + 1)]);
  };

  const create = useMutation({
    mutationFn: async () => {
      if (!legalEntityId || !branchId || !memo.trim()) throw new Error("حدد الكيان والفرع وبيان القيد");
      if (lines.length < 2 || lines.some((line) => {
        const debit = Number(line.debit) || 0;
        const credit = Number(line.credit) || 0;
        return !line.accountCode || debit < 0 || credit < 0 || ((debit > 0) === (credit > 0));
      })) throw new Error("كل سطر يحتاج حسابًا ومبلغًا في جانب واحد فقط");
      if (totals.debit <= 0 || difference > 0.005) throw new Error("القيد غير متوازن");

      const id = await createManualJournal({
        legalEntityId,
        branchId,
        accountingDate,
        periodCode: accountingDate.slice(0, 7),
        currency,
        memo: memo.trim(),
        externalReference: reference,
        lines: lines.map((line) => ({
          accountCode: line.accountCode,
          debit: Number(line.debit) || 0,
          credit: Number(line.credit) || 0,
          description: line.description,
          dimensions: { legalEntity: legalEntityId, branch: branchId },
        })),
      });
      await transitionManualJournal(id, "submitted");
      return id;
    },
    onSuccess: async () => {
      toast.success("تم إنشاء القيد وإرساله للاعتماد");
      setOpen(false);
      reset();
      await cache.invalidateQueries({ queryKey: ["onexa-manual-journals"] });
    },
    onError: (error) => toast.error(error.message),
  });

  const transition = useMutation({
    mutationFn: async ({ id, action }: { id: string; action: "approved" | "posted" }) => {
      if (action === "approved") return transitionManualJournal(id, "approved");
      return postManualJournal(id);
    },
    onSuccess: async (_, variables) => {
      toast.success(variables.action === "approved" ? "تم اعتماد القيد" : "تم ترحيل القيد إلى الأستاذ");
      await cache.invalidateQueries({ queryKey: ["onexa-manual-journals"] });
    },
    onError: (error) => toast.error(error.message),
  });

  if (!ONEXA_MANUAL_JOURNALS_ENABLED) {
    return (
      <OperationalGateCard
        icon={BookPlus}
        title="القيود اليومية اليدوية"
        description="تم تجهيز دورة القيد المحكومة: مسودة، إرسال، اعتماد من مستخدم آخر، ترحيل ذري إلى الأستاذ، ثم عكس عند التصحيح. التشغيل ينتظر تطبيق حزمة قاعدة البيانات وفحوصها."
        gate="Gate 58"
        actionLabel="إضافة قيد يومية"
      />
    );
  }

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
    <Card className="overflow-hidden border-primary/15">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b bg-primary/[0.035] px-5 py-4">
        <div>
          <div className="flex items-center gap-2 font-bold"><BookPlus className="h-5 w-5 text-primary" />القيود اليومية اليدوية</div>
          <p className="mt-1 text-xs text-muted-foreground">قيد متوازن مع فصل المنشئ عن المعتمد والمرحّل.</p>
        </div>
        <Dialog open={open} onOpenChange={openForm}>
          <DialogTrigger asChild><Button><Plus className="h-4 w-4" />إضافة قيد يومية</Button></DialogTrigger>
          <DialogContent className="max-h-[92vh] max-w-5xl overflow-y-auto" dir="rtl">
            <DialogHeader>
              <DialogTitle>قيد يومية جديد</DialogTitle>
              <DialogDescription>أدخل طرفي القيد ثم أرسله لمستخدم آخر للاعتماد.</DialogDescription>
            </DialogHeader>
            <form className="space-y-5" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
              <div className="grid gap-4 md:grid-cols-3">
                <div className="space-y-2">
                  <Label htmlFor="journal-entity">الكيان القانوني</Label>
                  <select id="journal-entity" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={legalEntityId}
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
                  <Label htmlFor="journal-branch">الفرع</Label>
                  <select id="journal-branch" className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={branchId}
                    onChange={(event) => setBranchId(event.target.value)} required>
                    <option value="">اختر الفرع</option>
                    {availableBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name_ar}</option>)}
                  </select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="journal-date">تاريخ القيد</Label>
                  <Input id="journal-date" type="date" value={accountingDate} onChange={(event) => setAccountingDate(event.target.value)} required />
                </div>
                <div className="space-y-2 md:col-span-2">
                  <Label htmlFor="journal-memo">بيان القيد</Label>
                  <Input id="journal-memo" value={memo} onChange={(event) => setMemo(event.target.value)} placeholder="وصف سبب القيد" required />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="journal-reference">المرجع</Label>
                  <Input id="journal-reference" value={reference} onChange={(event) => setReference(event.target.value)} placeholder="رقم المستند" />
                </div>
              </div>

              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <Label>سطور القيد</Label>
                  <Button type="button" size="sm" variant="outline" onClick={() => setLines((current) => [...current, newLine(Date.now())])}>
                    <Plus className="h-4 w-4" />إضافة سطر
                  </Button>
                </div>
                {lines.map((line, index) => (
                  <div key={line.key} className="grid gap-3 rounded-xl border bg-muted/20 p-3 md:grid-cols-[minmax(220px,1fr)_130px_130px_minmax(180px,1fr)_44px]">
                    <select aria-label={`حساب السطر ${index + 1}`} className="h-10 rounded-md border bg-background px-3 text-sm" value={line.accountCode}
                      onChange={(event) => updateLine(line.key, { accountCode: event.target.value })}>
                      <option value="">اختر الحساب</option>
                      {setup.data?.accounts.map((account) => <option key={account.code} value={account.code}>{account.code} — {account.name_ar}</option>)}
                    </select>
                    <Input aria-label={`مدين السطر ${index + 1}`} type="number" min="0" step="0.01" placeholder="مدين" value={line.debit}
                      onChange={(event) => updateLine(line.key, { debit: event.target.value, ...(Number(event.target.value) > 0 ? { credit: "" } : {}) })} />
                    <Input aria-label={`دائن السطر ${index + 1}`} type="number" min="0" step="0.01" placeholder="دائن" value={line.credit}
                      onChange={(event) => updateLine(line.key, { credit: event.target.value, ...(Number(event.target.value) > 0 ? { debit: "" } : {}) })} />
                    <Input aria-label={`وصف السطر ${index + 1}`} placeholder="وصف السطر" value={line.description}
                      onChange={(event) => updateLine(line.key, { description: event.target.value })} />
                    <Button type="button" size="icon" variant="ghost" disabled={lines.length === 2} aria-label={`حذف السطر ${index + 1}`}
                      onClick={() => setLines((current) => current.filter((item) => item.key !== line.key))}>
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                ))}
              </div>

              <div className="grid gap-3 rounded-xl border bg-muted/30 p-4 sm:grid-cols-3">
                <div><span className="text-xs text-muted-foreground">إجمالي المدين</span><div className="mt-1 font-bold">{totals.debit.toFixed(2)}</div></div>
                <div><span className="text-xs text-muted-foreground">إجمالي الدائن</span><div className="mt-1 font-bold">{totals.credit.toFixed(2)}</div></div>
                <div><span className="text-xs text-muted-foreground">الفرق</span><div className={`mt-1 font-bold ${difference <= 0.005 ? "text-success" : "text-destructive"}`}>{difference.toFixed(2)}</div></div>
              </div>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
                <Button type="submit" disabled={create.isPending || difference > 0.005 || totals.debit <= 0}>
                  <Send className="h-4 w-4" />{create.isPending ? "جارٍ الحفظ..." : "حفظ وإرسال للاعتماد"}
                </Button>
              </div>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      <div className="space-y-2 p-5">
        {journals.data?.map((journal) => (
          <div key={journal.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border px-4 py-3 text-sm">
            <div>
              <div className="font-semibold">{journal.journal_number} · {journal.memo}</div>
              <div className="mt-1 text-xs text-muted-foreground">{journal.accounting_date} · {Number(journal.total_debit).toFixed(2)} {journal.currency}</div>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant={journal.status === "posted" ? "default" : "secondary"}>{STATUS_LABELS[journal.status] ?? journal.status}</Badge>
              {journal.status === "submitted" && journal.created_by !== setup.data?.userId && (
                <Button size="sm" variant="outline" disabled={transition.isPending} onClick={() => transition.mutate({ id: journal.id, action: "approved" })}>اعتماد</Button>
              )}
              {journal.status === "approved" && journal.created_by !== setup.data?.userId && (
                <Button size="sm" disabled={transition.isPending} onClick={() => {
                  if (window.confirm(`ترحيل القيد ${journal.journal_number} إلى الأستاذ؟`)) transition.mutate({ id: journal.id, action: "posted" });
                }}>ترحيل</Button>
              )}
            </div>
          </div>
        ))}
        {!journals.isLoading && !journals.data?.length && <p className="rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">لا توجد قيود يومية يدوية.</p>}
      </div>
    </Card>
  );
}
