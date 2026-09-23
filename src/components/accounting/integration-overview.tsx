import { ArrowLeft, BadgeCheck, BookOpenCheck, FileCheck2, LineChart } from "lucide-react";
import { POSTING_CONTRACTS } from "@/lib/accounting/posting-contracts";
import { ONEXA_REPORTS } from "@/lib/reporting/report-catalog";

const steps = [
  { label: "مستند تشغيلي", caption: "بيع، شراء، مخزون، مشروع أو رواتب", icon: FileCheck2 },
  { label: "اعتماد وضوابط", caption: "صلاحيات، فترة مالية وأبعاد إلزامية", icon: BadgeCheck },
  { label: "قيد متوازن", caption: "مرجع مصدر ثابت ومنع الترحيل المكرر", icon: BookOpenCheck },
  { label: "تقارير مترابطة", caption: "مالية وتشغيلية حسب الشركة والفرع", icon: LineChart },
];

export function AccountingIntegrationOverview() {
  return (
    <section className="overflow-hidden rounded-2xl border border-border bg-card p-5 app-surface md:p-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p className="text-[11px] font-bold tracking-[0.14em] text-primary">ONEXA CONNECTED LEDGER</p>
          <h2 className="mt-2 text-lg font-bold md:text-xl">كل عملية تنتهي في الحسابات والتقارير</h2>
          <p className="mt-2 max-w-3xl text-sm leading-7 text-muted-foreground">
            دورة موحدة تربط المستندات التشغيلية بالحسابات العامة مع تتبع المصدر ومنع الترحيل المكرر والتصحيح بالعكس المحاسبي.
          </p>
        </div>
        <div className="flex shrink-0 gap-2 text-xs font-semibold">
          <span className="rounded-lg border border-border bg-muted/35 px-3 py-2">{POSTING_CONTRACTS.length} نوع مستند</span>
          <span className="rounded-lg border border-border bg-muted/35 px-3 py-2">{ONEXA_REPORTS.length} تقرير مترابط</span>
        </div>
      </div>

      <div className="mt-6 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {steps.map((step, index) => {
          const Icon = step.icon;
          return (
            <div key={step.label} className="relative rounded-xl border border-border bg-muted/25 p-4">
              <div className="flex items-start gap-3">
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-accent text-primary">
                  <Icon className="h-5 w-5" strokeWidth={1.8} />
                </span>
                <div>
                  <div className="font-bold">{step.label}</div>
                  <div className="mt-1 text-xs leading-5 text-muted-foreground">{step.caption}</div>
                </div>
              </div>
              {index < steps.length - 1 && <ArrowLeft className="absolute -left-5 top-1/2 z-10 hidden h-4 w-4 -translate-y-1/2 text-primary xl:block" />}
            </div>
          );
        })}
      </div>
    </section>
  );
}
