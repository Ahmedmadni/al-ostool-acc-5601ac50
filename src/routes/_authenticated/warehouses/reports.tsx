import { createFileRoute } from "@tanstack/react-router";
import { ModuleReportWorkspace } from "@/components/reporting/module-report-workspace";

export const Route = createFileRoute("/_authenticated/warehouses/reports")({
  component: () => <ModuleReportWorkspace module="inventory" />,
});
