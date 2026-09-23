import { createFileRoute, Link } from "@tanstack/react-router";
import {
  ArrowLeft,
  Gauge,
  Globe2,
  ShieldCheck,
  SlidersHorizontal,
  UserCheck,
  Users,
} from "lucide-react";
import { PageHeader } from "@/components/layout/page-header";
import { Card } from "@/components/ui/card";

export const Route = createFileRoute("/_authenticated/settings/")({
  component: SettingsOverview,
});

const SECTIONS = [
  {
    to: "/settings/regional",
    title: "الإعدادات الإقليمية",
    description: "اللغة الافتراضية والعملة والمنطقة الزمنية وتنسيقات الأرقام والتواريخ.",
    icon: Globe2,
  },
  {
    to: "/settings/users",
    title: "إدارة المستخدمين",
    description: "إنشاء الحسابات وتحديث بيانات المستخدمين وربطهم بالإدارات والوظائف.",
    icon: Users,
  },
  {
    to: "/settings/approvals",
    title: "اعتماد المستخدمين",
    description: "مراجعة طلبات التسجيل وقبول المستخدمين أو رفضهم قبل منح الوصول.",
    icon: UserCheck,
  },
  {
    to: "/settings/permissions",
    title: "الصلاحيات",
    description: "إدارة الأدوار ومنح أو حجب الإجراءات الحساسة على مستوى الموديولات.",
    icon: ShieldCheck,
  },
  {
    to: "/settings/permissions-dashboard",
    title: "جاهزية الصلاحيات",
    description: "متابعة تغطية الأدوار والتعارضات والاستثناءات قبل تشغيل العمليات.",
    icon: SlidersHorizontal,
  },
] as const;

function SettingsOverview() {
  return (
    <div>
      <PageHeader
        title="مركز إعدادات ONEXA"
        description="إدارة اللغة والمستخدمين والصلاحيات والاعتمادات من مساحة موحدة"
      />

      <Card className="mb-5 overflow-hidden border-primary/15">
        <div className="flex flex-col gap-4 p-5 md:flex-row md:items-center md:justify-between md:p-6">
          <div className="flex items-start gap-3">
            <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-accent text-primary">
              <Gauge className="h-5 w-5" strokeWidth={1.8} />
            </span>
            <div>
              <div className="font-bold">إعدادات واضحة وآمنة</div>
              <p className="mt-1 max-w-2xl text-xs leading-6 text-muted-foreground">
                التغييرات الإقليمية تطبق على العرض، بينما صلاحيات المستخدمين واعتماداتهم تخضع لضوابط النظام وسجل التدقيق.
              </p>
            </div>
          </div>
          <span className="w-fit rounded-lg border border-border bg-muted/40 px-3 py-2 text-xs font-semibold text-muted-foreground">
            {SECTIONS.length} أقسام إدارية
          </span>
        </div>
      </Card>

      <div className="grid gap-4 md:grid-cols-2">
        {SECTIONS.map((section) => {
          const Icon = section.icon;
          return (
            <Link key={section.to} to={section.to} className="group">
              <Card className="h-full p-5 transition-[transform,border-color,box-shadow] group-hover:-translate-y-0.5 group-hover:border-primary/20 group-hover:shadow-md">
                <div className="flex items-start gap-4">
                  <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-muted text-muted-foreground transition-colors group-hover:bg-accent group-hover:text-primary">
                    <Icon className="h-5 w-5" strokeWidth={1.8} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="font-bold">{section.title}</div>
                    <p className="mt-2 text-xs leading-6 text-muted-foreground">{section.description}</p>
                  </div>
                  <ArrowLeft className="mt-1 h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:-translate-x-1 group-hover:text-primary" />
                </div>
              </Card>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
