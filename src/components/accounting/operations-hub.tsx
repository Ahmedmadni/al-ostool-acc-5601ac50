import { Link } from "@tanstack/react-router";
import { ArrowLeftRight, BadgeDollarSign, BookPlus, FilePlus2, HandCoins, ReceiptText } from "lucide-react";
import { Card } from "@/components/ui/card";

const OPERATIONS = [
  {
    title: "فاتورة مبيعات",
    description: "إنشاء فاتورة أصلية وإرسالها للاعتماد",
    to: "/customers/invoices",
    icon: FilePlus2,
    state: "متاح الآن",
    active: true,
  },
  {
    title: "فاتورة مشتريات",
    description: "تسجيل فاتورة مورد وتصنيف بنودها",
    to: "/vendors/invoices",
    icon: ReceiptText,
    state: "متاح الآن",
    active: true,
  },
  {
    title: "تحصيل عميل",
    description: "تسجيل المقبوض وتخصيصه على الفواتير",
    to: "/customers/collections",
    icon: HandCoins,
    state: "جاهز بعد Gate 39",
    active: true,
  },
  {
    title: "دفعة مورد",
    description: "إنشاء دفعة وتخصيصها على المستحقات",
    to: "/vendors/payments",
    icon: BadgeDollarSign,
    state: "جاهز بعد Gate 40",
    active: true,
  },
  {
    title: "حركة بنكية",
    description: "تحويل محكوم بين حسابات الخزينة",
    to: "/banks",
    icon: ArrowLeftRight,
    state: "جاهز بعد Gate 41",
    active: true,
  },
] as const;

export function AccountingOperationsHub() {
  return (
    <Card className="overflow-hidden border-primary/15">
      <div className="border-b bg-primary/[0.035] px-5 py-4">
        <h2 className="font-bold">العمليات المحاسبية</h2>
        <p className="mt-1 text-xs leading-5 text-muted-foreground">
          الإدخال الأصلي داخل النظام هو المسار الأساسي؛ الاستيراد أصبح قناة مساندة للبيانات القديمة فقط.
        </p>
      </div>
      <div className="grid gap-px bg-border sm:grid-cols-2 xl:grid-cols-3">
        {OPERATIONS.map((operation) => {
          const Icon = operation.icon;
          return (
            <Link key={operation.title} to={operation.to} className="group bg-card p-5 transition-colors hover:bg-accent/40">
              <div className="flex items-start justify-between gap-3">
                <span className="grid h-10 w-10 place-items-center rounded-xl bg-primary/8 text-primary">
                  <Icon className="h-5 w-5" strokeWidth={1.8} />
                </span>
                <span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold ${operation.state === "متاح الآن" ? "bg-success/10 text-success" : "bg-muted text-muted-foreground"}`}>
                  {operation.state}
                </span>
              </div>
              <div className="mt-4 font-bold">{operation.title}</div>
              <p className="mt-1 text-xs leading-5 text-muted-foreground">{operation.description}</p>
            </Link>
          );
        })}
        <div className="bg-card p-5 opacity-75" title="يتطلب توسيع عقد قاعدة البيانات بمسار اعتماد مستقل">
          <div className="flex items-start justify-between gap-3">
            <span className="grid h-10 w-10 place-items-center rounded-xl bg-muted text-muted-foreground">
              <BookPlus className="h-5 w-5" strokeWidth={1.8} />
            </span>
            <span className="rounded-full bg-warning/10 px-2.5 py-1 text-[10px] font-semibold text-warning">يتطلب Migration</span>
          </div>
          <div className="mt-4 font-bold">قيد يومية يدوي</div>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">لن يُفعّل قبل إضافة مسودة واعتماد وفصل المنشئ عن المرحّل في قاعدة البيانات.</p>
        </div>
      </div>
    </Card>
  );
}
