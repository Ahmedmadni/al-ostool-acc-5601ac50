import { createFileRoute } from "@tanstack/react-router";
import { ModuleReportWorkspace } from "@/components/reporting/module-report-workspace";

export const Route = createFileRoute("/_authenticated/projects/reports")({
  component: () => <ModuleReportWorkspace module="projects" />,
});
