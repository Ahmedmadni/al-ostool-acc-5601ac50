import { type ReactNode } from "react";
import { Card } from "@/components/ui/card";

export function PageHeader({ title, description, actions }: { title: string; description?: string; actions?: ReactNode }) {
  return (
    <div className="mb-7 flex flex-wrap items-start justify-between gap-4">
      <div className="min-w-0">
        <h1 className="text-2xl font-bold leading-tight text-foreground md:text-[1.75rem]">{title}</h1>
        {description && <p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">{description}</p>}
      </div>
      {actions && <div className="flex gap-2 flex-wrap">{actions}</div>}
    </div>
  );
}

export function KpiCard({ title, value, icon: Icon, hint, trend, color = "primary" }: {
  title: string; value: string | number; icon?: React.ComponentType<{ className?: string }>;
  hint?: string; trend?: string; color?: "primary" | "success" | "warning" | "destructive" | "info";
}) {
  const colorMap = {
    primary: "bg-primary/10 text-primary",
    success: "bg-success/10 text-success",
    warning: "bg-warning/10 text-warning",
    destructive: "bg-destructive/10 text-destructive",
    info: "bg-info/10 text-info",
  };
  return (
    <Card className="group p-5 transition-[box-shadow,border-color,transform] hover:-translate-y-0.5 hover:border-primary/20 hover:shadow-md">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="mb-2 text-xs font-medium text-muted-foreground">{title}</div>
          <div className="truncate text-2xl font-bold leading-none text-foreground tabular-nums">{value}</div>
          {hint && <div className="text-xs text-muted-foreground mt-1">{hint}</div>}
          {trend && <div className="text-xs text-success mt-1">{trend}</div>}
        </div>
        {Icon && (
          <div className={`shrink-0 rounded-xl p-2.5 transition-transform group-hover:scale-105 ${colorMap[color]}`}>
            <Icon className="w-5 h-5" />
          </div>
        )}
      </div>
    </Card>
  );
}
