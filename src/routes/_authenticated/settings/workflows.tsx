import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowDown, ArrowUp, Plus, Save, Trash2, Workflow } from "lucide-react";
import { toast } from "sonner";
import { SettingsWorkspaceShell } from "@/components/settings/settings-workspace";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_authenticated/settings/workflows")({
  component: RoutePage,
});

type Step = {
  id?: string;
  name_ar: string;
  action_key: "prepare" | "review" | "approve" | "post";
  assignee_kind: "user" | "role" | "department" | "manager";
  assignee_user_id: string;
  assignee_role_key: string;
  assignee_department_id: string;
  minimum_approvals: number;
  is_required: boolean;
};
type Draft = {
  id?: string;
  process_key: string;
  name_ar: string;
  description: string;
  manager_user_id: string;
  is_active: boolean;
  allow_creator_approval: boolean;
  allow_same_actor_all_steps: boolean;
  steps: Step[];
};

const processes = [
  ["sales_invoice", "فاتورة مبيعات"],
  ["purchase_invoice", "فاتورة مشتريات"],
  ["manual_journal", "قيد يومية يدوي"],
  ["customer_receipt", "سند قبض"],
  ["supplier_payment", "سند صرف"],
  ["bank_transfer", "تحويل بنكي"],
  ["payroll", "مسير رواتب"],
  ["fixed_asset", "أصل ثابت"],
  ["project_cost", "تكلفة مشروع"],
  ["fleet_trip_cost", "تكلفة رحلة أسطول"],
] as const;
const actionLabels: Record<Step["action_key"], string> = {
  prepare: "إعداد المسودة",
  review: "مراجعة",
  approve: "اعتماد",
  post: "ترحيل",
};
const emptyStep = (): Step => ({
  name_ar: "خطوة اعتماد",
  action_key: "approve",
  assignee_kind: "role",
  assignee_user_id: "",
  assignee_role_key: "accountant",
  assignee_department_id: "",
  minimum_approvals: 1,
  is_required: true,
});
const newDraft = (): Draft => ({
  process_key: "sales_invoice",
  name_ar: "اعتماد فاتورة المبيعات",
  description: "",
  manager_user_id: "",
  is_active: true,
  allow_creator_approval: false,
  allow_same_actor_all_steps: false,
  steps: [
    { ...emptyStep(), name_ar: "إعداد المسودة", action_key: "prepare" },
    {
      ...emptyStep(),
      name_ar: "اعتماد الفاتورة",
      action_key: "approve",
      assignee_role_key: "finance_manager",
    },
    { ...emptyStep(), name_ar: "الترحيل المحاسبي", action_key: "post" },
  ],
});

function Page() {
  const qc = useQueryClient();
  const [draft, setDraft] = useState<Draft>(newDraft);
  const [saving, setSaving] = useState(false);
  const { data: workflows = [] } = useQuery({
    queryKey: ["approval-workflows"],
    queryFn: async () => {
      const { data, error } = await (supabase as any)
        .from("onexa_approval_workflows")
        .select("*, onexa_approval_workflow_steps(*)")
        .order("name_ar");
      if (error) throw error;
      return data ?? [];
    },
  });
  const { data: profiles = [] } = useQuery({
    queryKey: ["approval-workflow-profiles"],
    queryFn: async () =>
      (
        await (supabase as any)
          .from("profiles")
          .select("id,full_name,email")
          .eq("status", "active")
          .order("full_name")
      ).data ?? [],
  });
  const { data: departments = [] } = useQuery({
    queryKey: ["approval-workflow-departments"],
    queryFn: async () =>
      (
        await (supabase as any)
          .from("departments")
          .select("id,name_ar")
          .order("name_ar")
      ).data ?? [],
  });
  const ordered = useMemo(() => [...draft.steps], [draft.steps]);
  const selectWorkflow = (row: any) =>
    setDraft({
      id: row.id,
      process_key: row.process_key,
      name_ar: row.name_ar,
      description: row.description ?? "",
      manager_user_id: row.manager_user_id ?? "",
      is_active: row.is_active,
      allow_creator_approval: row.allow_creator_approval,
      allow_same_actor_all_steps: row.allow_same_actor_all_steps,
      steps: [...(row.onexa_approval_workflow_steps ?? [])]
        .sort((a: any, b: any) => a.step_order - b.step_order)
        .map((s: any) => ({
          ...s,
          assignee_user_id: s.assignee_user_id ?? "",
          assignee_role_key: s.assignee_role_key ?? "",
          assignee_department_id: s.assignee_department_id ?? "",
        })),
    });
  const patchStep = (index: number, patch: Partial<Step>) =>
    setDraft((d) => ({
      ...d,
      steps: d.steps.map((s, i) => (i === index ? { ...s, ...patch } : s)),
    }));
  const move = (index: number, delta: number) =>
    setDraft((d) => {
      const next = [...d.steps];
      const target = index + delta;
      if (target < 0 || target >= next.length) return d;
      [next[index], next[target]] = [next[target], next[index]];
      return { ...d, steps: next };
    });
  const save = async () => {
    if (!draft.name_ar.trim() || !draft.steps.length)
      return toast.error("أدخل اسم الخريطة وخطوة واحدة على الأقل");
    setSaving(true);
    const payload = {
      ...draft,
      manager_user_id: draft.manager_user_id || null,
      steps: draft.steps.map((s) => ({
        ...s,
        assignee_user_id:
          s.assignee_kind === "user" ? s.assignee_user_id : null,
        assignee_role_key:
          s.assignee_kind === "role" ? s.assignee_role_key : null,
        assignee_department_id:
          s.assignee_kind === "department" ? s.assignee_department_id : null,
      })),
    };
    const { data, error } = await (supabase as any).rpc(
      "onexa_save_approval_workflow",
      { _workflow: payload },
    );
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success("تم حفظ خريطة الاعتماد");
    setDraft((d) => ({ ...d, id: data }));
    qc.invalidateQueries({ queryKey: ["approval-workflows"] });
  };
  return (
    <div>
      <PageHeader
        title="خرائط سير الاعتماد"
        description="تخصيص من ينشئ ويراجع ويعتمد ويرحّل كل عملية لكل شركة"
        actions={
          <Button onClick={save} disabled={saving} className="gap-2">
            <Save className="h-4 w-4" />
            {saving ? "جارٍ الحفظ" : "حفظ الخريطة"}
          </Button>
        }
      />
      <div className="grid gap-4 lg:grid-cols-[260px_minmax(0,1fr)]">
        <Card className="p-3">
          <Button
            variant="outline"
            className="mb-3 w-full gap-2"
            onClick={() => setDraft(newDraft())}
          >
            <Plus className="h-4 w-4" />
            خريطة جديدة
          </Button>
          <div className="space-y-1">
            {workflows.map((w: any) => (
              <button
                key={w.id}
                onClick={() => selectWorkflow(w)}
                className={`w-full rounded-lg p-3 text-right text-sm ${draft.id === w.id ? "bg-primary/10 text-primary" : "hover:bg-muted"}`}
              >
                <span className="block font-semibold">{w.name_ar}</span>
                <span className="mt-1 block text-xs text-muted-foreground">
                  {processes.find(([k]) => k === w.process_key)?.[1] ??
                    w.process_key}
                </span>
              </button>
            ))}
          </div>
        </Card>
        <div className="space-y-4">
          <Card className="grid gap-4 p-5 md:grid-cols-2">
            <div className="space-y-1.5">
              <Label>نوع العملية</Label>
              <Select
                value={draft.process_key}
                disabled={Boolean(draft.id)}
                onValueChange={(v) => setDraft({ ...draft, process_key: v })}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {processes.map(([k, l]) => (
                    <SelectItem key={k} value={k}>
                      {l}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>اسم الخريطة</Label>
              <Input
                value={draft.name_ar}
                onChange={(e) =>
                  setDraft({ ...draft, name_ar: e.target.value })
                }
              />
            </div>
            <div className="space-y-1.5 md:col-span-2">
              <Label>مدير الخريطة</Label>
              <Select
                value={draft.manager_user_id || "none"}
                onValueChange={(v) =>
                  setDraft({ ...draft, manager_user_id: v === "none" ? "" : v })
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">مالك الشركة فقط</SelectItem>
                  {profiles.map((p: any) => (
                    <SelectItem key={p.id} value={p.id}>
                      {p.full_name ?? p.email}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                مدير الخريطة يستطيع تعديل الخطوات وترتيبها؛ إنشاء الخريطة لمالك
                الشركة.
              </p>
            </div>
            <Toggle
              label="الخريطة مفعلة"
              checked={draft.is_active}
              onChange={(v) => setDraft({ ...draft, is_active: v })}
            />
            <Toggle
              label="السماح للمنشئ بالاعتماد"
              checked={draft.allow_creator_approval}
              onChange={(v) =>
                setDraft({ ...draft, allow_creator_approval: v })
              }
            />
            <div className="md:col-span-2">
              <Toggle
                label="السماح لشخص واحد بتنفيذ جميع المراحل"
                checked={draft.allow_same_actor_all_steps}
                onChange={(v) =>
                  setDraft({ ...draft, allow_same_actor_all_steps: v })
                }
              />
              <p className="mt-1 text-xs text-amber-700">
                فعّل هذا فقط للشركات الصغيرة التي تعتمد رسميًا عدم فصل المهام.
              </p>
            </div>
          </Card>
          <div className="space-y-3">
            {ordered.map((step, index) => (
              <Card key={step.id ?? index} className="p-4">
                <div className="mb-4 flex items-center gap-2">
                  <Badge variant="secondary">{index + 1}</Badge>
                  <Workflow className="h-4 w-4 text-primary" />
                  <strong className="flex-1 text-sm">
                    {step.name_ar || "خطوة جديدة"}
                  </strong>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => move(index, -1)}
                    disabled={index === 0}
                  >
                    <ArrowUp className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => move(index, 1)}
                    disabled={index === ordered.length - 1}
                  >
                    <ArrowDown className="h-4 w-4" />
                  </Button>
                  <Button
                    size="icon"
                    variant="ghost"
                    className="text-destructive"
                    onClick={() =>
                      setDraft((d) => ({
                        ...d,
                        steps: d.steps.filter((_, i) => i !== index),
                      }))
                    }
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
                <div className="grid gap-3 md:grid-cols-4">
                  <div className="space-y-1">
                    <Label>اسم الخطوة</Label>
                    <Input
                      value={step.name_ar}
                      onChange={(e) =>
                        patchStep(index, { name_ar: e.target.value })
                      }
                    />
                  </div>
                  <div className="space-y-1">
                    <Label>الإجراء</Label>
                    <Select
                      value={step.action_key}
                      onValueChange={(v: Step["action_key"]) =>
                        patchStep(index, { action_key: v })
                      }
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {Object.entries(actionLabels).map(([k, v]) => (
                          <SelectItem key={k} value={k}>
                            {v}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1">
                    <Label>التعيين حسب</Label>
                    <Select
                      value={step.assignee_kind}
                      onValueChange={(v: Step["assignee_kind"]) =>
                        patchStep(index, { assignee_kind: v })
                      }
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="role">الدور</SelectItem>
                        <SelectItem value="user">شخص محدد</SelectItem>
                        <SelectItem value="department">الإدارة</SelectItem>
                        <SelectItem value="manager">المدير المباشر</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <Assignee
                    step={step}
                    profiles={profiles}
                    departments={departments}
                    onChange={(p) => patchStep(index, p)}
                  />
                </div>
              </Card>
            ))}
            <Button
              variant="outline"
              className="w-full gap-2"
              onClick={() =>
                setDraft((d) => ({ ...d, steps: [...d.steps, emptyStep()] }))
              }
            >
              <Plus className="h-4 w-4" />
              إضافة خطوة
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-lg border p-3">
      <Label>{label}</Label>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}
function Assignee({
  step,
  profiles,
  departments,
  onChange,
}: {
  step: Step;
  profiles: any[];
  departments: any[];
  onChange: (p: Partial<Step>) => void;
}) {
  if (step.assignee_kind === "manager")
    return (
      <div className="space-y-1">
        <Label>المسؤول</Label>
        <Input disabled value="المدير المباشر لصاحب الطلب" />
      </div>
    );
  if (step.assignee_kind === "user")
    return (
      <div className="space-y-1">
        <Label>المستخدم</Label>
        <Select
          value={step.assignee_user_id}
          onValueChange={(v) => onChange({ assignee_user_id: v })}
        >
          <SelectTrigger>
            <SelectValue placeholder="اختر مستخدمًا" />
          </SelectTrigger>
          <SelectContent>
            {profiles.map((p) => (
              <SelectItem key={p.id} value={p.id}>
                {p.full_name ?? p.email}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
    );
  if (step.assignee_kind === "department")
    return (
      <div className="space-y-1">
        <Label>الإدارة</Label>
        <Select
          value={step.assignee_department_id}
          onValueChange={(v) => onChange({ assignee_department_id: v })}
        >
          <SelectTrigger>
            <SelectValue placeholder="اختر إدارة" />
          </SelectTrigger>
          <SelectContent>
            {departments.map((d) => (
              <SelectItem key={d.id} value={d.id}>
                {d.name_ar}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
    );
  return (
    <div className="space-y-1">
      <Label>الدور</Label>
      <Select
        value={step.assignee_role_key}
        onValueChange={(v) => onChange({ assignee_role_key: v })}
      >
        <SelectTrigger>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="accountant">محاسب</SelectItem>
          <SelectItem value="finance_manager">
            رئيس الحسابات / المدير المالي
          </SelectItem>
          <SelectItem value="workspace_owner">مالك الشركة</SelectItem>
          <SelectItem value="hr_manager">مدير الموارد البشرية</SelectItem>
          <SelectItem value="project_manager">مدير المشروع</SelectItem>
          <SelectItem value="sales_manager">مدير المبيعات</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}
function RoutePage() {
  return (
    <SettingsWorkspaceShell>
      <Page />
    </SettingsWorkspaceShell>
  );
}
