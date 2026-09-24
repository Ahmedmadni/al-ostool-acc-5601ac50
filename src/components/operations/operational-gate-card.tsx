import type { LucideIcon } from "lucide-react";
import { DatabaseZap, LockKeyhole } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export function OperationalGateCard({
  icon: Icon,
  title,
  description,
  gate,
  actionLabel,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
  gate: string;
  actionLabel: string;
}) {
  return (
    <Card className="mb-5 overflow-hidden border-warning/25">
      <div className="flex flex-wrap items-start justify-between gap-4 border-b bg-warning/[0.045] px-5 py-4">
        <div className="flex items-start gap-3">
          <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-warning/10 text-warning">
            <Icon className="h-5 w-5" strokeWidth={1.8} />
          </span>
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="font-bold">{title}</h2>
              <Badge variant="outline" className="border-warning/30 bg-warning/10 text-warning">بانتظار {gate}</Badge>
            </div>
            <p className="mt-1 max-w-2xl text-xs leading-5 text-muted-foreground">{description}</p>
          </div>
        </div>
        <Button disabled className="gap-2" aria-describedby={`${gate}-readiness`}>
          <LockKeyhole className="h-4 w-4" />{actionLabel}
        </Button>
      </div>
      <div id={`${gate}-readiness`} className="grid gap-3 px-5 py-4 text-xs sm:grid-cols-3">
        <div className="flex items-center gap-2 rounded-lg border bg-card p-3">
          <DatabaseZap className="h-4 w-4 text-primary" />
          <span><strong>1.</strong> تطبيق حزمة {gate}</span>
        </div>
        <div className="flex items-center gap-2 rounded-lg border bg-card p-3">
          <DatabaseZap className="h-4 w-4 text-primary" />
          <span><strong>2.</strong> نجاح Postcheck وSmoke test</span>
        </div>
        <div className="flex items-center gap-2 rounded-lg border bg-card p-3">
          <DatabaseZap className="h-4 w-4 text-primary" />
          <span><strong>3.</strong> تفعيل مفتاح التشغيل الآمن</span>
        </div>
      </div>
    </Card>
  );
}
