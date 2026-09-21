import { BarChart3, Database, FileSpreadsheet } from "lucide-react";
import type { OnexaModuleKey } from "@/lib/onexa-product";
import { reportsForModule } from "@/lib/reporting/report-catalog";
import { getModuleBlueprint } from "@/lib/erp-module-model";
import { useI18n } from "@/lib/i18n";

export function ModuleReportWorkspace({ module }: { module: OnexaModuleKey }) {
  const { lang, dir } = useI18n();
  const english = lang === "en";
  const blueprint = getModuleBlueprint(module);
  const reports = reportsForModule(module);

  return (
    <main className="mx-auto w-full max-w-[1400px] space-y-6 p-4 md:p-6 lg:p-8" dir={dir}>
      <section className="overflow-hidden rounded-3xl border border-border bg-card shadow-sm">
        <div className="h-1.5 bg-[linear-gradient(90deg,var(--brand-blue)_0_68%,var(--brand-cyan)_68%)]" />
        <div className="p-6 md:p-8">
          <div className="flex flex-col justify-between gap-5 md:flex-row md:items-end">
            <div>
              <div className="inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1.5 text-xs font-bold text-primary">
                <BarChart3 className="h-3.5 w-3.5" /> {english ? "Module reports" : "تقارير الموديول"}
              </div>
              <h1 className="mt-4 text-3xl font-black">
                {english ? `${blueprint?.labelEn ?? module} reports` : `تقارير ${blueprint?.labelAr ?? module}`}
              </h1>
              <p className="mt-3 max-w-3xl text-sm leading-7 text-muted-foreground">
                {english
                  ? "Reports remain inside their owning module and use approved operational documents and posted journal entries as their governed source."
                  : "تبقى التقارير داخل الموديول المالك لها، وتقرأ من المستندات التشغيلية المعتمدة والقيود المرحلة كمصدر محكوم واحد."}
              </p>
            </div>
            <div className="rounded-2xl border border-border bg-background px-4 py-3 text-sm">
              <span className="font-black text-primary">{reports.length}</span>
              <span className="ms-2 text-muted-foreground">{english ? "governed reports" : "تقارير محكومة"}</span>
            </div>
          </div>
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {reports.map((report) => (
          <article key={report.key} className="rounded-2xl border border-border bg-card p-5 shadow-sm">
            <div className="flex items-start justify-between gap-3">
              <div className="grid h-11 w-11 place-items-center rounded-xl bg-primary/10 text-primary"><FileSpreadsheet className="h-5 w-5" /></div>
              <span className="rounded-full border border-border bg-background px-2.5 py-1 text-[10px] font-bold text-muted-foreground">{report.key}</span>
            </div>
            <h2 className="mt-4 font-black">{english ? report.labelEn : report.labelAr}</h2>
            <div className="mt-4 flex items-start gap-2 text-xs leading-5 text-muted-foreground">
              <Database className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              <span>{report.sourceDocuments.join(" • ")}</span>
            </div>
            <div className="mt-3 flex flex-wrap gap-1.5">
              {report.dimensions.map((dimension) => <span key={dimension} className="rounded-md bg-muted px-2 py-1 text-[10px] font-semibold text-muted-foreground">{dimension}</span>)}
            </div>
          </article>
        ))}
      </section>
    </main>
  );
}
