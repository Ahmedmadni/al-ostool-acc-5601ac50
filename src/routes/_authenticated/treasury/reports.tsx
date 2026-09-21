import { createFileRoute } from "@tanstack/react-router";
import { ModuleReportWorkspace } from "@/components/reporting/module-report-workspace";

export const Route = createFileRoute("/_authenticated/treasury/reports")({
  component: () => <ModuleReportWorkspace module="finance" />,
});
