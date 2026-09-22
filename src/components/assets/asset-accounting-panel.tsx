import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  Landmark,
  PlayCircle,
  TrendingDown,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { ONEXA_ASSET_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  fetchAssetAccountingReconciliation,
  fetchAssetPostingConfigurationGaps,
  postAssetDepreciation,
} from "@/lib/assets/asset-posting-service";

const amount = (value: number) =>
  new Intl.NumberFormat("ar-SA", {
    style: "currency",
    currency: "SAR",
    maximumFractionDigits: 2,
  }).format(value);

const statusLabels: Record<string, string> = {
  ready: "جاهز للترحيل",
  fully_depreciated: "مُهلك بالكامل",
  legal_entity_required: "يلزم تحديد الكيان",
  branch_required: "يلزم تحديد الفرع",
  invalid_legal_entity: "كيان غير صالح",
  invalid_branch: "فرع غير صالح",
  cost_required: "التكلفة مطلوبة",
  invalid_salvage_value: "قيمة تخريد غير صالحة",
  useful_life_required: "العمر الإنتاجي مطلوب",
  depreciation_start_required: "تاريخ بدء الإهلاك مطلوب",
  unsupported_method: "طريقة إهلاك غير مدعومة",
  register_mismatch: "عدم تطابق سجل الأصل",
};

function currentPeriod() {
  const now = new Date();
  const year = now.getUTCFullYear();
  const monthIndex = now.getUTCMonth();
  const month = String(monthIndex + 1).padStart(2, "0");
  const day = String(new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate()).padStart(2, "0");
  return {
    periodCode: `${year}-${month}`,
    accountingDate: `${year}-${month}-${day}`,
  };
}

export function AssetAccountingPanel() {
  const queryClient = useQueryClient();
  const period = currentPeriod();
  const reconciliation = useQuery({
    queryKey: ["asset-accounting-reconciliation"],
    queryFn: () => fetchAssetAccountingReconciliation(),
    enabled: ONEXA_ASSET_POSTING_ENABLED,
  });
  const configuration = useQuery({
    queryKey: ["asset-posting-configuration-gaps"],
    queryFn: fetchAssetPostingConfigurationGaps,
    enabled: ONEXA_ASSET_POSTING_ENABLED,
  });
  const posting = useMutation({
    mutationFn: (assetId: string) =>
      postAssetDepreciation(assetId, period.periodCode, period.accountingDate),
    onSuccess: async (result) => {
      if (result.status === "posted") {
        toast.success("تم ترحيل إهلاك الأصل بنجاح");
      }
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["asset-accounting-reconciliation"] }),
        queryClient.invalidateQueries({ queryKey: ["fixed_assets"] }),
      ]);
    },
    onError: (error) => {
      toast.error(error instanceof Error ? error.message : "تعذر ترحيل الإهلاك");
    },
  });

  if (!ONEXA_ASSET_POSTING_ENABLED) {
    return (
      <Card className="mb-5 border-amber-500/25 bg-amber-500/[0.06] p-6">
        <AlertTriangle className="h-6 w-6 text-amber-600" />
        <h2 className="mt-3 text-lg font-black">الربط المحاسبي للأصول جاهز مرحليًا</h2>
        <p className="mt-2 text-sm leading-7 text-muted-foreground">
          طبّق Gate 38، اربط حسابي مصروف الإهلاك ومجمع الإهلاك، وأكمل بيانات
          الكيان والفرع والعمر الإنتاجي وتاريخ بدء الإهلاك قبل تفعيل الترحيل.
        </p>
      </Card>
    );
  }

  const rows = reconciliation.data ?? [];
  const ready = rows.filter((row) => row.reconciliation_status === "ready");
  const reconciled = rows.filter(
    (row) =>
      row.reconciliation_status === "ready" ||
      row.reconciliation_status === "fully_depreciated",
  );
  const postedPeriods = rows.reduce((sum, row) => sum + Number(row.posted_periods), 0);
  const gate38Depreciation = rows.reduce(
    (sum, row) => sum + Number(row.gate38_depreciation),
    0,
  );
  const configurationReady = (configuration.data?.length ?? 0) === 0;

  return (
    <div className="mb-5 space-y-5">
      {!configurationReady && (
        <Card className="border-destructive/25 bg-destructive/[0.04] p-5">
          <div className="flex items-center gap-2 font-black text-destructive">
            <AlertTriangle className="h-5 w-5" />
            إعدادات حسابات الإهلاك غير مكتملة
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            {configuration.data?.map((gap) => (
              <Badge
                key={`${gap.legal_entity_id}:${gap.account_role}`}
                variant="outline"
              >
                {gap.legal_entity_code} • {gap.account_role}
              </Badge>
            ))}
          </div>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[
          { label: "أصول مطابقة", value: reconciled.length, icon: CheckCircle2 },
          { label: "جاهز للشهر الحالي", value: ready.length, icon: Building2 },
          { label: "فترات مرحلة", value: postedPeriods, icon: Landmark },
          {
            label: "إهلاك Gate 38",
            value: amount(gate38Depreciation),
            icon: TrendingDown,
          },
        ].map((item) => {
          const Icon = item.icon;
          return (
            <Card key={item.label} className="p-4">
              <Icon className="h-5 w-5 text-primary" />
              <div className="mt-3 text-xl font-black">{item.value}</div>
              <div className="mt-1 text-xs text-muted-foreground">{item.label}</div>
            </Card>
          );
        })}
      </div>

      <Card className="overflow-hidden p-0">
        <div className="border-b px-5 py-4">
          <h3 className="font-black">مطابقة سجل الأصول والإهلاك</h3>
          <p className="mt-1 text-xs text-muted-foreground">
            فترة الترحيل الحالية: {period.periodCode}
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1100px] text-sm">
            <thead className="bg-muted/60 text-xs text-muted-foreground">
              <tr>
                {[
                  "الأصل",
                  "التكلفة",
                  "مجمع الإهلاك",
                  "صافي القيمة",
                  "آخر فترة",
                  "الحالة",
                  "الإجراء",
                ].map((heading) => (
                  <th key={heading} className="px-4 py-3 text-start font-black">
                    {heading}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {rows.map((row) => {
                const canPost =
                  configurationReady && row.reconciliation_status === "ready";
                return (
                  <tr key={row.asset_id} className="hover:bg-muted/25">
                    <td className="px-4 py-3">
                      <div className="font-bold">{row.asset_name}</div>
                      <div className="text-xs text-muted-foreground">
                        {row.asset_code ?? row.asset_id.slice(0, 8)}
                      </div>
                    </td>
                    <td className="px-4 py-3">{amount(Number(row.cost))}</td>
                    <td className="px-4 py-3">
                      {amount(Number(row.accumulated_depreciation))}
                    </td>
                    <td className="px-4 py-3 font-bold">
                      {amount(Number(row.net_book_value))}
                    </td>
                    <td className="px-4 py-3">
                      {row.latest_posted_period ?? "—"}
                    </td>
                    <td className="px-4 py-3">
                      <Badge
                        variant={
                          row.reconciliation_status === "ready" ||
                          row.reconciliation_status === "fully_depreciated"
                            ? "secondary"
                            : "destructive"
                        }
                      >
                        {statusLabels[row.reconciliation_status] ??
                          row.reconciliation_status}
                      </Badge>
                    </td>
                    <td className="px-4 py-3">
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={!canPost || posting.isPending}
                        onClick={() => {
                          if (
                            window.confirm(
                              `ترحيل إهلاك ${row.asset_name} عن ${period.periodCode}؟`,
                            )
                          ) {
                            posting.mutate(row.asset_id);
                          }
                        }}
                      >
                        <PlayCircle className="me-2 h-4 w-4" />
                        ترحيل الشهر
                      </Button>
                    </td>
                  </tr>
                );
              })}
              {!rows.length && !reconciliation.isLoading && (
                <tr>
                  <td colSpan={7} className="px-4 py-10 text-center text-muted-foreground">
                    لا توجد أصول مهيأة للمطابقة.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
