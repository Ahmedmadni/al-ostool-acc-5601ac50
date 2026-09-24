import { useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, WifiOff } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useI18n } from "@/lib/i18n";

type ConnectivityState = "online" | "offline" | "restored";

export function ConnectivityBanner() {
  const { lang } = useI18n();
  const queryClient = useQueryClient();
  const [state, setState] = useState<ConnectivityState>(() => {
    if (typeof navigator === "undefined") return "online";
    return navigator.onLine ? "online" : "offline";
  });
  const wasOffline = useRef(typeof navigator !== "undefined" && !navigator.onLine);
  const restoreTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const clearRestoreTimer = () => {
      if (restoreTimer.current) clearTimeout(restoreTimer.current);
      restoreTimer.current = null;
    };

    const handleOffline = () => {
      clearRestoreTimer();
      wasOffline.current = true;
      setState("offline");
    };

    const handleOnline = () => {
      if (!wasOffline.current) {
        setState("online");
        return;
      }

      wasOffline.current = false;
      setState("restored");
      void queryClient.refetchQueries({ type: "active" });
      clearRestoreTimer();
      restoreTimer.current = setTimeout(() => setState("online"), 4500);
    };

    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);
    return () => {
      clearRestoreTimer();
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("online", handleOnline);
    };
  }, [queryClient]);

  if (state === "online") return null;

  const restored = state === "restored";
  const title = lang === "en"
    ? restored ? "Connection restored" : "You are offline"
    : restored ? "تمت استعادة الاتصال" : "أنت غير متصل بالإنترنت";
  const detail = lang === "en"
    ? restored ? "Active data is being refreshed." : "Displayed data may be outdated. Avoid posting or approving transactions until connectivity returns."
    : restored ? "جارٍ تحديث البيانات النشطة." : "قد تكون البيانات المعروضة غير محدثة. تجنب ترحيل أو اعتماد العمليات حتى عودة الاتصال.";

  return (
    <div
      role="status"
      aria-live={restored ? "polite" : "assertive"}
      data-connectivity={state}
      className={`no-print sticky top-[4.5rem] z-20 flex items-start justify-center gap-3 border-b px-4 py-2.5 text-sm shadow-sm ${restored ? "border-success/20 bg-success/10 text-success" : "border-warning/30 bg-warning/10 text-foreground"}`}
    >
      {restored ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" /> : <WifiOff className="mt-0.5 h-4 w-4 shrink-0 text-warning" />}
      <span>
        <strong>{title}</strong>
        <span className="ms-2 text-xs opacity-80">{detail}</span>
      </span>
    </div>
  );
}
