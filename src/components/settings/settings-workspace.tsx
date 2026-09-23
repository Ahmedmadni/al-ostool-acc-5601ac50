import { Link, useRouterState } from "@tanstack/react-router";
import { type ReactNode } from "react";
import {
  ChevronLeft,
  Globe2,
  ShieldCheck,
  SlidersHorizontal,
  UserCheck,
  Users,
} from "lucide-react";
import { Card } from "@/components/ui/card";

const SETTINGS_LINKS = [
  { to: "/settings/regional", label: "الإعدادات الإقليمية", caption: "اللغة والعملات والتواريخ", icon: Globe2 },
  { to: "/settings/users", label: "إدارة المستخدمين", caption: "الحسابات والبيانات الوظيفية", icon: Users },
  { to: "/settings/approvals", label: "اعتماد المستخدمين", caption: "مراجعة طلبات الوصول", icon: UserCheck },
  { to: "/settings/permissions", label: "الصلاحيات", caption: "الأدوار ونطاقات الوصول", icon: ShieldCheck },
  { to: "/settings/permissions-dashboard", label: "جاهزية الصلاحيات", caption: "التغطية والاستثناءات", icon: SlidersHorizontal },
] as const;

export function SettingsWorkspaceShell({ children }: { children: ReactNode }) {
  const path = useRouterState({ select: (state) => state.location.pathname });

  return (
    <div className="grid items-start gap-5 xl:grid-cols-[280px_minmax(0,1fr)]" dir="rtl">
      <aside className="xl:sticky xl:top-24">
        <Card className="overflow-hidden">
          <div className="border-b border-border px-5 py-4">
            <div className="text-base font-bold">الإعدادات</div>
            <div className="mt-1 text-xs text-muted-foreground">إدارة بيئة ONEXA والصلاحيات</div>
          </div>
          <nav className="grid gap-1 p-3 sm:grid-cols-2 xl:grid-cols-1">
            {SETTINGS_LINKS.map((item) => {
              const Icon = item.icon;
              const active = path === item.to;
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  className={`group flex items-center gap-3 rounded-xl px-3 py-3 transition-colors ${active ? "bg-accent text-accent-foreground" : "text-muted-foreground hover:bg-muted hover:text-foreground"}`}
                >
                  <span className={`grid h-9 w-9 shrink-0 place-items-center rounded-xl ${active ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground group-hover:text-foreground"}`}>
                    <Icon className="h-[18px] w-[18px]" strokeWidth={1.8} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className={`block truncate text-sm ${active ? "font-bold" : "font-medium"}`}>{item.label}</span>
                    <span className="mt-0.5 block truncate text-[10px] opacity-70">{item.caption}</span>
                  </span>
                  {active && <ChevronLeft className="h-3.5 w-3.5 text-primary" />}
                </Link>
              );
            })}
          </nav>
        </Card>
      </aside>
      <section className="min-w-0">{children}</section>
    </div>
  );
}
