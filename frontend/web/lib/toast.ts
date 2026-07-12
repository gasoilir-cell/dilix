// شیمِ توست — جایگزینِ `react-hot-toast` بدونِ وابستگیِ خارجی.
// یک نوتیفیکیشنِ سبکِ مبتنی بر DOM که پایینِ صفحه ظاهر و پس از مدتی محو می‌شود.
// امضای اصلی سازگار است: toast(msg), toast.success/error/loading, toast.dismiss(id).

type ToastKind = "default" | "success" | "error" | "loading";

let seq = 0;
const BG: Record<ToastKind, string> = {
  default: "#1C1C1E",
  success: "#0f5132",
  error: "#842029",
  loading: "#1C1C1E",
};
const ICON: Record<ToastKind, string> = {
  default: "",
  success: "✓ ",
  error: "✕ ",
  loading: "⏳ ",
};

function show(message: string, kind: ToastKind, autoDismissMs: number | null): string {
  const id = `toast-${++seq}`;
  if (typeof document === "undefined") return id;

  const el = document.createElement("div");
  el.id = id;
  el.textContent = `${ICON[kind]}${message}`;
  el.setAttribute("role", "status");
  Object.assign(el.style, {
    position: "fixed",
    left: "50%",
    bottom: "88px",
    transform: "translateX(-50%)",
    zIndex: "9999",
    maxWidth: "88vw",
    padding: "10px 16px",
    borderRadius: "12px",
    background: BG[kind],
    color: "#fff",
    fontSize: "14px",
    fontFamily: "Vazirmatn, Tahoma, sans-serif",
    boxShadow: "0 6px 24px rgba(0,0,0,0.35)",
    direction: "rtl",
    pointerEvents: "none",
  } as CSSStyleDeclaration);
  document.body.appendChild(el);

  if (autoDismissMs != null) {
    window.setTimeout(() => dismiss(id), autoDismissMs);
  }
  return id;
}

export function dismiss(id?: string): void {
  if (typeof document === "undefined") return;
  if (id) {
    document.getElementById(id)?.remove();
  } else {
    document.querySelectorAll('[id^="toast-"]').forEach((n) => n.remove());
  }
}

function toast(message: string): string {
  return show(message, "default", 2500);
}
toast.success = (message: string): string => show(message, "success", 2500);
toast.error = (message: string): string => show(message, "error", 3000);
toast.loading = (message: string): string => show(message, "loading", null);
toast.dismiss = dismiss;

export default toast;
