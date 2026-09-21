import { createFileRoute } from "@tanstack/react-router";
import { ModuleReportWorkspace } from "@/components/reporting/module-report-workspace";

export const Route = createFileRoute("/_authenticated/fleet/reports")({
  component: () => <ModuleReportWorkspace module="logistics" />,
});
