import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Banknote, CheckCircle2, Landmark, Users } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { ONEXA_PAYROLL_POSTING_ENABLED } from "@/lib/runtime-flags";
import {
  fetchPayrollAccountingReconciliation,
  fetchPayrollPostingConfigurationGaps,
} from "@/lib/payroll/payroll-posting-service";

const amount = (value: number) => new Intl.NumberFormat("ar-SA", {
  style: "currency",
  currency: "SAR",
  maximumFractionDigits: 2,
}).format(value);

export function PayrollAccountingPanel() {
  const reconciliation = useQuery({
    queryKey: ["payroll-accounting-reconciliation"],
    queryFn: () => fetchPayrollAccountingReconciliation(),
    enabled: ONEXA_PAYROLL_POSTING_ENABLED,
  });
  const configuration = useQuery({
    queryKey: ["payroll-posting-configuration-gaps"],
    queryFn: fetchPayrollPostingConfigurationGaps,
    enabled: ONEXA_PAYROLL_POSTING_ENABLED,
  });

  if (!ONEXA_PAYROLL_POSTING_ENABLED) {
    return (
      <Card className="border-amber-500/25 bg-amber-500/[0.06] p-6">
        <AlertTriangle className="h-6 w-6 text-amber-600" />
        <h2 className="mt-3 text-lg font-black">الربط المحاسبي للرواتب جاهز مرحليًا</h2>
        <p className="mt-2 text-sm leading-7 text-muted-foreground">
          طبّق Gate 37 واربط حسابات الرواتب، ثم نفّذ اختبار المطابقة قبل تفعيل مفتاح الترحيل.
        </p>
      </Card>
    );
  }

  const rows = reconciliation.data ?? [];
  const posted = rows.filter((row) => row.posted_journal_id);
  const reconciled = rows.filter((row) => row.reconciliation_status === "reconciled");
  const employerCost = rows.reduce((sum, row) => sum + Number(row.employer_cost), 0);
  const netPay = rows.reduce((sum, row) => sum + Number(row.net_pay), 0);

  return (
    <div className="space-y-5">
      {(configuration.data?.length ?? 0) > 0 && (
        <Card className="border-destructive/25 bg-destructive/[0.04] p-5">
          <div className="flex items-center gap-2 font-black text-destructive"><AlertTriangle className="h-5 w-5" />إعدادات الحسابات غير مكتملة</div>
          <div className="mt-3 flex flex-wrap gap-2">
            {configuration.data?.map((gap) => <Badge key={`${gap.legal_entity_id}:${gap.account_role}`} variant="outline">{gap.legal_entity_code} • {gap.account_role}</Badge>)}
          </div>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[
          { label: "المسيرات المرحلة", value: posted.length, icon: Landmark },
          { label: "المطابق بالكامل", value: reconciled.length, icon: CheckCircle2 },
          { label: "تكلفة صاحب العمل", value: amount(employerCost), icon: Banknote },
          { label: "صافي مستحقات الموظفين", value: amount(netPay), icon: Users },
        ].map((item) => {
          const Icon = item.icon;
          return <Card key={item.label} className="p-4"><Icon className="h-5 w-5 text-primary" /><div className="mt-3 text-xl font-black">{item.value}</div><div className="mt-1 text-xs text-muted-foreground">{item.label}</div></Card>;
        })}
      </div>

      <Card className="overflow-hidden p-0">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1050px] text-sm">
            <thead className="bg-muted/60 text-xs text-muted-foreground"><tr>{[
              "المسير", "الفترة", "الموظفون", "تكلفة صاحب العمل", "صافي الرواتب",
              "التأمينات", "استرداد السلف", "دفتر التكلفة", "الحالة",
            ].map((heading) => <th key={heading} className="px-4 py-3 text-start font-black">{heading}</th>)}</tr></thead>
            <tbody className="divide-y divide-border">
              {rows.map((row) => (
                <tr key={row.payroll_run_id} className="hover:bg-muted/25">
                  <td className="px-4 py-3 font-bold">{row.run_no}</td>
                  <td className="px-4 py-3">{String(row.period_month).padStart(2, "0")}/{row.period_year}</td>
                  <td className="px-4 py-3">{row.employees_count}</td>
                  <td className="px-4 py-3">{amount(Number(row.employer_cost))}</td>
                  <td className="px-4 py-3">{amount(Number(row.net_pay))}</td>
                  <td className="px-4 py-3">{amount(Number(row.gosi_payable))}</td>
                  <td className="px-4 py-3">{amount(Number(row.loan_recovery))}</td>
                  <td className="px-4 py-3">{row.cost_line_count}/{row.expected_cost_line_count} • {amount(Number(row.cost_ledger_amount))}</td>
                  <td className="px-4 py-3"><Badge variant={row.reconciliation_status === "reconciled" ? "secondary" : "destructive"}>{row.reconciliation_status}</Badge></td>
                </tr>
              ))}
              {!rows.length && !reconciliation.isLoading && <tr><td colSpan={9} className="px-4 py-10 text-center text-muted-foreground">لا توجد مسيرات رواتب لعرضها.</td></tr>}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
