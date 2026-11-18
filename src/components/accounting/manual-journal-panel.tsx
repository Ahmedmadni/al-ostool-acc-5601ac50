import { useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BookPlus, Plus, Send, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { ONEXA_MANUAL_JOURNALS_ENABLED } from "@/lib/runtime-flags";
import { amendManualJournal, createManualJournal, listManualJournals, loadEditableManualJournal, postManualJournal, transitionManualJournal } from "@/lib/accounting/manual-journal-service";
import { evaluateManualJournalDraft } from "@/lib/accounting/manual-journal-validation";
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
  dimensions: Record<string, string>;
};

const today = () => {
  const date = new Date();
  return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, "0"), String(date.getDate()).padStart(2, "0")].join("-");
};
const newLine = (key: number): DraftLine => ({ key, accountCode: "", debit: "", credit: "", description: "", dimensions: {} });
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
  const [editTarget, setEditTarget] = useState<{ id: string; revision: number; status: "draft" | "rejected" } | null>(null);
  const [loadingEditId, setLoadingEditId] = useState<string | null>(null);
  const [rejectionReason, setRejectionReason] = useState<string | null>(null);
  const [legalEntityId, setLegalEntityId] = useState("");
  const [branchId, setBranchId] = useState("");
  const [accountingDate, setAccountingDate] = useState(today);
  const [currency, setCurrency] = useState("SAR");
  const [memo, setMemo] = useState("");
  const [reference, setReference] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([newLine(1), newLine(2)]);
  const nextLineKey = useRef(3);

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
      const error = entities.error ?? branches.error ?? accounts.error ?? user.error;
      if (error) throw error;
      if (!user.data.user?.id) throw new Error("يجب تسجيل الدخول قبل إدخال القيود");
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

  const availableBranches = (setup.data?.branches ?? []).filter((branch) => branch.legal_entity_id === legalEntityId);
  const validation = useMemo(() => evaluateManualJournalDraft({
    legalEntityId,
    branchId,
    entityIds: (setup.data?.entities ?? []).map((entity) => entity.id),
    branchIdsForEntity: availableBranches.map((branch) => branch.id),
    accountCodes: (setup.data?.accounts ?? []).map((account) => account.code),
    accountingDate,
    currency,
    memo,
    lines,
  }), [legalEntityId, branchId, setup.data, accountingDate, currency, memo, lines]);

  const reset = () => {
    setEditTarget(null);
    setRejectionReason(null);
    setMemo("");
    setReference("");
    setAccountingDate(today());
    setLines([newLine(nextLineKey.current++), newLine(nextLineKey.current++)]);
  };

  const create = useMutation({
    mutationFn: async () => {
      if (!setup.data?.userId) throw new Error("لم يتم التحقق من هوية المستخدم");
      if (!validation.valid) throw new Error(validation.errors[0] ?? "بيانات القيد غير مكتملة");

      // Preserve cost-centre/project dimensions across amendments; an edit must
      // not silently discard data not exposed as controls in this small panel.
      const inputLines = validation.normalizedLines.map((line, index) => ({
        ...line,
        dimensions: {
          ...lines[index].dimensions,
          legalEntity: legalEntityId,
          branch: branchId,
        },
      }));
      let id: string;
      if (editTarget) {
        // An RPC-amended draft is committed before the separate submit RPC.
        // Failure to submit leaves a retryable draft, not an ambiguous save.
        await amendManualJournal({
          journalId: editTarget.id,
          expectedRevision: editTarget.revision,
          memo: memo.trim(),
          externalReference: reference.trim(),
          lines: inputLines,
        });
        id = editTarget.id;
      } else {
        id = await createManualJournal({
          legalEntityId,
          branchId,
          accountingDate,
          periodCode: accountingDate.slice(0, 7),
          currency,
          memo: memo.trim(),
          externalReference: reference.trim(),
          lines: inputLines,
        });
      }
      // These are two separate RPCs. A failed submission does NOT undo the
      // successfully created draft; expose it for an explicit retry in the list.
      try {
        await transitionManualJournal(id, "submitted");
        return { id, submitted: true, amended: Boolean(editTarget) };
      } catch {
        return { id, submitted: false, amended: Boolean(editTarget) };
      }
    },
    onSuccess: async ({ submitted, amended }) => {
      if (submitted) toast.success(amended ? "تم حفظ التصحيح وإعادة إرسال القيد للاعتماد" : "تم إنشاء القيد وإرساله للاعتماد");
      else toast.warning(amended
        ? "تم حفظ التعديل كمراجعة جديدة، ولم يتأكد الإرسال. أعد الإرسال من القائمة."
        : "تم حفظ القيد كمسودة، لكن لم يتأكد إرساله للاعتماد. أعد الإرسال من القائمة.");
      setOpen(false);
      reset();
      await cache.invalidateQueries({ queryKey: ["onexa-manual-journals"] });
    },
    onError: (error) => toast.error(error.message),
  });

  const transition = useMutation({
    mutationFn: async ({ id, action }: { id: string; action: "submitted" | "approved" | "posted" }) => {
      if (action === "posted") return postManualJournal(id);
      return transitionManualJournal(id, action);
    },
    onSuccess: async (_, variables) => {
      const message = variables.action === "submitted" ? "تم إرسال المسودة للاعتماد"
        : variables.action === "approved" ? "تم اعتماد القيد"
        : "تم ترحيل القيد إلى الأستاذ";
      toast.success(message);
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
    if (!next) {
      reset();
      return;
    }
    if (!setup.data) return;
    const entity = setup.data.entities.find((row) => row.is_default) ?? setup.data.entities[0];
    if (entity && !legalEntityId) {
      setLegalEntityId(entity.id);
      setCurrency(entity.base_currency || "SAR");
      const branch = setup.data.branches.find((row) => row.legal_entity_id === entity.id && row.is_default)
        ?? setup.data.branches.find((row) => row.legal_entity_id === entity.id);
      setBranchId(branch?.id ?? "");
    }
  };

  const startEditing = async (journalId: string) => {
    if (loadingEditId) return;
    setLoadingEditId(journalId);
    try {
      const entry = await loadEditableManualJournal(journalId);
      const creator = setup.data?.userId;
      if (!creator || entry.journal.created_by !== creator) {
        throw new Error("لا يمكن تصحيح قيد أنشأه مستخدم آخر");
      }
      if (entry.journal.status !== "draft" && entry.journal.status !== "rejected") {
        throw new Error("لا يمكن تعديل قيد بعد تقديمه للاعتماد");
      }
      setEditTarget({
        id: entry.journal.id,
        revision: entry.journal.revision,
        status: entry.journal.status,
      });
      setRejectionReason(entry.latestRejectionReason);
      setLegalEntityId(entry.journal.legal_entity_id);
      setBranchId(entry.journal.branch_id);
      setAccountingDate(entry.journal.accounting_date);
      setCurrency(entry.journal.currency);
      setMemo(entry.journal.memo);
      setReference(entry.journal.external_reference ?? "");
      setLines(entry.lines.map((line) => ({
        key: nextLineKey.current++,
        accountCode: line.account_code,
        debit: line.debit ? String(line.debit) : "",
        credit: line.credit ? String(line.credit) : "",
        description: line.description ?? "",
        dimensions: line.dimensions ?? {},
      })));
      setOpen(true);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "تعذر فتح القيد للتصحيح");
    } finally {
      setLoadingEditId(null);
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
              <DialogTitle>{editTarget ? `تصحيح القيد — المراجعة ${editTarget.revision}` : "قيد يومية جديد"}</DialogTitle>
              <DialogDescription>{editTarget
                ? "يمكن تعديل البيان والمرجع والسطور فقط. يحتفظ القيد بنفس هويته، ويسجل النظام نسخة سابقة لكل تصحيح."
                : "أدخل طرفي القيد ثم أرسله لمستخدم آخر للاعتماد."}</DialogDescription>
            </DialogHeader>
            <form className="space-y-5" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
              {editTarget && rejectionReason && (
                <p role="note" className="rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-sm">
                  سبب الرفض السابق: {rejectionReason}
                </p>
              )}
              <div className="grid gap-4 md:grid-cols-3">
                <div className="space-y-2">
                  <Label htmlFor="journal-entity">الكيان القانوني</Label>
                  <select id="journal-entity" disabled={Boolean(editTarget)} className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={legalEntityId}
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
                  <select id="journal-branch" disabled={Boolean(editTarget)} className="h-10 w-full rounded-md border bg-background px-3 text-sm" value={branchId}
                    onChange={(event) => setBranchId(event.target.value)} required>
                    <option value="">اختر الفرع</option>
                    {availableBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name_ar}</option>)}
                  </select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="journal-date">تاريخ القيد</Label>
                  <Input id="journal-date" disabled={Boolean(editTarget)} type="date" value={accountingDate} onChange={(event) => setAccountingDate(event.target.value)} required />
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
                  <Button type="button" size="sm" variant="outline" onClick={() => setLines((current) => [...current, newLine(nextLineKey.current++)])}>
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
                    <Input aria-label={`مدين السطر ${index + 1}`} type="number" min="0" step="any" placeholder="مدين" value={line.debit}
                      onChange={(event) => updateLine(line.key, { debit: event.target.value, ...(Number(event.target.value) > 0 ? { credit: "" } : {}) })} />
                    <Input aria-label={`دائن السطر ${index + 1}`} type="number" min="0" step="any" placeholder="دائن" value={line.credit}
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
                <div><span className="text-xs text-muted-foreground">إجمالي المدين</span><div className="mt-1 font-bold tabular-nums">{validation.totalDebit}</div></div>
                <div><span className="text-xs text-muted-foreground">إجمالي الدائن</span><div className="mt-1 font-bold tabular-nums">{validation.totalCredit}</div></div>
                <div><span className="text-xs text-muted-foreground">الفرق</span><div className={`mt-1 font-bold tabular-nums ${Number(validation.difference) === 0 ? "text-success" : "text-destructive"}`}>{validation.difference}</div></div>
              </div>
              {setup.isError && <p role="alert" className="text-sm text-destructive">تعذر تحميل دليل الحسابات أو صلاحيات المستخدم. لا يمكن إنشاء القيد.</p>}
              {validation.errors.length > 0 && <p role="alert" className="text-sm text-destructive">{validation.errors[0]}</p>}
              <div className="flex justify-end gap-2">
                <Button type="button" variant="outline" onClick={() => setOpen(false)}>إلغاء</Button>
                <Button type="submit" disabled={create.isPending || !setup.data?.userId || !validation.valid}>
                  <Send className="h-4 w-4" />{create.isPending ? "جارٍ الحفظ..." : editTarget ? "حفظ التصحيح وإعادة الإرسال" : "حفظ وإرسال للاعتماد"
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
              <div className="text-xs text-muted-foreground">مراجعة {journal.revision}</div>
              <div className="mt-1 text-xs text-muted-foreground">{journal.accounting_date} · {Number(journal.total_debit).toFixed(2)} {journal.currency}</div>
            </div>
            <div className="flex items-center gap-2">
              <Badge variant={journal.status === "posted" ? "default" : "secondary"}>{STATUS_LABELS[journal.status] ?? journal.status}</Badge>
              {(journal.status === "draft" || journal.status === "rejected") && setup.data?.userId === journal.created_by && (
                <Button size="sm" variant="outline" disabled={create.isPending || Boolean(loadingEditId)}
                  onClick={() => void startEditing(journal.id)}>
                  {loadingEditId === journal.id ? "جارٍ تحميل القيد..." : journal.status === "rejected" ? "تصحيح القيد المرفوض" : "تعديل المسودة"}
                </Button>
              )}
              {journal.status === "draft" && setup.data?.userId === journal.created_by && (
                <Button size="sm" variant="outline" disabled={transition.isPending}
                  onClick={() => transition.mutate({ id: journal.id, action: "submitted" })}>إرسال للاعتماد</Button>
              )}
              {journal.status === "submitted" && Boolean(setup.data?.userId) && journal.created_by !== setup.data?.userId && (
                <Button size="sm" variant="outline" disabled={transition.isPending} onClick={() => transition.mutate({ id: journal.id, action: "approved" })}>اعتماد</Button>
              )}
              {journal.status === "approved" && Boolean(setup.data?.userId) && journal.created_by !== setup.data?.userId && (
                <Button size="sm" disabled={transition.isPending} onClick={() => {
                  if (window.confirm(`ترحيل القيد ${journal.journal_number} إلى الأستاذ؟`)) transition.mutate({ id: journal.id, action: "posted" });
                }}>ترحيل</Button>
              )}
            </div>
          </div>
        ))}
        {journals.isError && <p role="alert" className="rounded-xl border border-destructive/30 p-4 text-sm text-destructive">تعذر تحميل القيود اليومية. تحقق من صلاحيات القراءة أو اتصال قاعدة البيانات.</p>}
        {journals.isLoading && <p className="p-4 text-sm text-muted-foreground">جارٍ تحميل القيود...</p>}
        {!journals.isLoading && !journals.isError && !journals.data?.length && <p className="rounded-xl border border-dashed p-8 text-center text-sm text-muted-foreground">لا توجد قيود يومية يدوية.</p>}
      </div>
    </Card>
  );
}
