"use client";

/**
 * Dilix — صفحه ورود/ثبت‌نام
 * روش: ایمیل + گذرواژه (ورود و ثبت‌نام). ورودِ آسان، امنیتِ کامل.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import toast from "react-hot-toast";
import { Globe2, Mail, Eye, EyeOff } from "lucide-react";
import { authApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import { useTranslation } from "@/store/i18n";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils";

type EmailMode = "login" | "register";

// ─── Page ─────────────────────────────────────────────────────
export default function LoginPage() {
  const { t } = useTranslation();
  const router = useRouter();
  const { setUser, setTokens } = useAuthStore();

  const [emailMode, setEmailMode] = useState<EmailMode>("login");
  const [fullName, setFullName] = useState("");
  const [identifier, setIdentifier] = useState("");
  const [emailPassword, setEmailPassword] = useState("");
  const [showPwd, setShowPwd] = useState(false);
  const [emailBusy, setEmailBusy] = useState(false);

  // ─── پایانِ موفقِ احراز ───────────────────────────────────────
  const finishAuth = async (data: any) => {
    const { access_token, refresh_token, earth_id, is_new_user } = data;
    setTokens(access_token, refresh_token);
    const meRes = await authApi.getMe();
    setUser(meRes.data);
    toast.success(
      is_new_user ? `${t("login.welcomeNewPre")}${earth_id}` : t("login.loginOk")
    );
    router.replace(is_new_user ? "/onboarding" : "/dashboard");
  };

  const errMessage = (err: any, fallback: string) => {
    const d = err?.response?.data?.detail;
    if (typeof d === "string") return d;
    if (d?.message) return d.message;
    return fallback;
  };

  // ─── ایمیل/گذرواژه ───────────────────────────────────────────
  const onEmailSubmit = async () => {
    if (emailMode === "register" && emailPassword.length < 8) {
      toast.error(t("login.err.pwdMin"));
      return;
    }
    setEmailBusy(true);
    try {
      const res =
        emailMode === "login"
          ? await authApi.loginPassword(identifier.trim(), emailPassword)
          : await authApi.register(
              identifier.trim(),
              emailPassword,
              fullName.trim()
            );
      await finishAuth(res.data);
    } catch (err: any) {
      toast.error(
        errMessage(
          err,
          emailMode === "login" ? t("login.err.loginFail") : t("login.err.registerFail")
        )
      );
    } finally {
      setEmailBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-surface-900 flex flex-col items-center justify-center px-4 py-8 overflow-y-auto">
      {/* Background Glow */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-primary/10 rounded-full blur-3xl" />
        <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-secondary/10 rounded-full blur-3xl" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-ai/5 rounded-full blur-3xl" />
      </div>

      <div className="relative w-full max-w-sm">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-gradient-to-br from-primary to-ai mb-4 shadow-lg shadow-primary/30">
            <Globe2 className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-3xl font-black text-gradient-primary mb-1">Dilix</h1>
          <p className="text-surface-500 text-sm">{t("login.tagline")}</p>
        </div>

        {/* Card */}
        <div className="card shadow-card-dark">
          {/* ── سربرگِ روشِ ایمیل ── */}
          <div className="flex items-center justify-center gap-2 mb-5 text-surface-300">
            <Mail className="w-4 h-4" />
            <span className="text-sm font-medium">{t("login.email")}</span>
          </div>

          {/* ── ورود / ثبت‌نام ── */}
          <div className="flex gap-1 p-1 bg-surface-800 rounded-xl mb-4">
            <button
              type="button"
              onClick={() => setEmailMode("login")}
              className={cn(
                "flex-1 py-1.5 rounded-lg text-sm font-medium transition-colors",
                emailMode === "login"
                  ? "bg-surface-700 text-white"
                  : "text-surface-400 hover:text-surface-200"
              )}
            >
              {t("login.signIn")}
            </button>
            <button
              type="button"
              onClick={() => setEmailMode("register")}
              className={cn(
                "flex-1 py-1.5 rounded-lg text-sm font-medium transition-colors",
                emailMode === "register"
                  ? "bg-surface-700 text-white"
                  : "text-surface-400 hover:text-surface-200"
              )}
            >
              {t("login.tabRegister")}
            </button>
          </div>

          <div className="space-y-3">
            {emailMode === "register" && (
              <input
                className="input"
                placeholder={t("login.displayNamePh")}
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
              />
            )}

            <input
              className="input text-left ltr placeholder:text-right"
              placeholder={t("login.identifierPh")}
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              dir="ltr"
              autoComplete="username"
            />

            <div className="relative">
              <input
                className="input text-left ltr placeholder:text-right pl-10"
                type={showPwd ? "text" : "password"}
                placeholder={
                  emailMode === "register"
                    ? t("login.pwdPhRegister")
                    : t("login.pwdPh")
                }
                value={emailPassword}
                onChange={(e) => setEmailPassword(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && onEmailSubmit()}
                dir="ltr"
                autoComplete={
                  emailMode === "register" ? "new-password" : "current-password"
                }
              />
              <button
                type="button"
                onClick={() => setShowPwd((v) => !v)}
                className="absolute left-2 top-1/2 -translate-y-1/2 text-surface-500 hover:text-surface-300"
                aria-label={showPwd ? t("login.hidePwd") : t("login.showPwd")}
              >
                {showPwd ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
              </button>
            </div>

            <Button
              type="button"
              fullWidth
              size="lg"
              loading={emailBusy}
              onClick={onEmailSubmit}
              disabled={
                identifier.trim().length < 3 ||
                emailPassword.length < 1 ||
                (emailMode === "register" && fullName.trim().length < 2)
              }
            >
              {emailMode === "login" ? t("login.signIn") : t("login.submitRegister")}
            </Button>
          </div>

          <p className="text-center text-surface-600 text-xs mt-5">
            {t("login.terms.pre")}
            <a href="/terms" className="text-primary hover:underline">
              {t("login.terms.rules")}
            </a>
            {t("login.terms.mid")}
            <a href="/privacy" className="text-primary hover:underline">
              {t("login.terms.privacy")}
            </a>
            {t("login.terms.post")}
          </p>
        </div>

        {/* Earth ID info */}
        <div className="mt-4 flex items-center gap-2 justify-center text-surface-600 text-xs">
          <Globe2 className="w-3.5 h-3.5" />
          <span>{t("login.earthIdNote")}</span>
        </div>
      </div>
    </div>
  );
}
