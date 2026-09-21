import { createFileRoute } from "@tanstack/react-router";
import { ModuleAccessGuard } from "@/components/group/module-access-guard";
import { ModuleReportWorkspace } from "@/components/reporting/module-report-workspace";

export const Route = createFileRoute("/_authenticated/real-estate/reports")({
  component: RealEstateReports,
});

function RealEstateReports() {
  return (
    <ModuleAccessGuard companyCode="RE" moduleKey="real_estate">
      <ModuleReportWorkspace module="facilities" />
    </ModuleAccessGuard>
  );
}
