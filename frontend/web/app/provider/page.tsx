"use client";

import { useState } from "react";

import {
  ApiError,
  api,
  isAuthenticated,
  type CredentialOut,
  type ProviderApiOut,
  type ProviderOut,
  type SandboxTestResult,
  type WebhookOut,
} from "@/lib/api";

// پورتالِ ارائه‌دهنده (سند ۷ §۴): ثبت‌نام KYB، ثبتِ API، sandbox، webhook، کلیدها.
export default function ProviderPortal() {
  const [provider, setProvider] = useState<ProviderOut | null>(null);
  const [apis, setApis] = useState<ProviderApiOut[]>([]);
  const [sandbox, setSandbox] = useState<Record<string, SandboxTestResult>>({});
  const [webhook, setWebhook] = useState<WebhookOut | null>(null);
  const [credential, setCredential] = useState<CredentialOut | null>(null);
  const [error, setError] = useState<string | null>(null);

  // فرم‌ها
  const [legalName, setLegalName] = useState("");
  const [providerType, setProviderType] = useState<ProviderOut["provider_type"]>("psp");
  const [apiName, setApiName] = useState("");
  const [specUrl, setSpecUrl] = useState("");
  const [webhookUrl, setWebhookUrl] = useState("");

  function fail(e: unknown, fallback: string) {
    setError(e instanceof ApiError ? e.problem.detail : fallback);
  }

  async function register() {
    setError(null);
    try {
      setProvider(
        await api.provider.register({
          legal_name: legalName,
          provider_type: providerType as
            | "insurer"
            | "carrier"
            | "psp"
            | "telecom"
            | "third_party",
        }),
      );
    } catch (e) {
      fail(e, "ثبت‌نامِ ارائه‌دهنده ناموفق بود. ابتدا وارد شوید.");
    }
  }

  async function addApi() {
    if (!provider) return;
    setError(null);
    try {
      const created = await api.provider.registerApi(provider.id, {
        name: apiName,
        spec_url: specUrl || undefined,
      });
      setApis((a) => [...a, created]);
      setApiName("");
      setSpecUrl("");
    } catch (e) {
      fail(e, "ثبتِ API ناموفق بود.");
    }
  }

  async function runSandbox(apiId: string) {
    if (!provider) return;
    try {
      const res = await api.provider.sandboxTest(provider.id, apiId);
      setSandbox((s) => ({ ...s, [apiId]: res }));
    } catch (e) {
      fail(e, "تستِ sandbox ناموفق بود.");
    }
  }

  async function addWebhook() {
    if (!provider) return;
    try {
      setWebhook(
        await api.provider.registerWebhook(provider.id, {
          url: webhookUrl,
          event_types: ["*"],
        }),
      );
      setWebhookUrl("");
    } catch (e) {
      fail(e, "ثبتِ webhook ناموفق بود.");
    }
  }

  async function issueKey(env: "sandbox" | "production") {
    if (!provider) return;
    try {
      setCredential(await api.provider.issueCredential(provider.id, env));
    } catch (e) {
      fail(e, "صدورِ کلید ناموفق بود (production نیازمندِ KYB تأییدشده است).");
    }
  }

  if (!isAuthenticated()) {
    return (
      <main className="page">
        <h1>پورتالِ ارائه‌دهنده</h1>
        <div className="card">
          <p className="muted">برای دسترسی به پورتال، ابتدا از صفحه‌ی «من» وارد شوید.</p>
        </div>
      </main>
    );
  }

  return (
    <main className="page">
      <h1>پورتالِ ارائه‌دهنده</h1>
      <p className="muted">ثبتِ سرویس، تستِ sandbox، webhook و کلیدها — خودسرویس (Provider Adapter Framework).</p>
      {error && <div className="card danger">{error}</div>}

      {!provider ? (
        <div className="card">
          <strong>ثبت‌نامِ ارائه‌دهنده (KYB)</strong>
          <input
            className="input"
            placeholder="نامِ حقوقی"
            value={legalName}
            onChange={(e) => setLegalName(e.target.value)}
          />
          <select
            className="input"
            value={providerType}
            onChange={(e) => setProviderType(e.target.value as ProviderOut["provider_type"])}
          >
            <option value="psp">PSP (پرداخت)</option>
            <option value="insurer">بیمه‌گر</option>
            <option value="carrier">حمل‌کننده / راهداری</option>
            <option value="telecom">اپراتورِ ارتباطات</option>
            <option value="third_party">شخصِ ثالث</option>
          </select>
          <button className="btn" style={{ marginTop: 8 }} onClick={register}>
            ثبت‌نام
          </button>
        </div>
      ) : (
        <>
          <div className="card row-between">
            <div>
              <strong>{provider.legal_name}</strong>
              <div className="muted">{provider.provider_type} · {provider.country}</div>
            </div>
            <span className="badge">KYB: {provider.kyb_status}</span>
          </div>

          <div className="card">
            <strong>ثبتِ API</strong>
            <input
              className="input"
              placeholder="نامِ سرویس/API"
              value={apiName}
              onChange={(e) => setApiName(e.target.value)}
            />
            <input
              className="input"
              placeholder="آدرسِ OpenAPI spec (اختیاری)"
              value={specUrl}
              onChange={(e) => setSpecUrl(e.target.value)}
            />
            <button className="btn" style={{ marginTop: 8 }} onClick={addApi}>
              افزودنِ API
            </button>
          </div>

          {apis.map((a) => (
            <div key={a.id} className="card">
              <div className="row-between">
                <div>
                  <strong>{a.name}</strong>
                  <div className="muted">{a.env} · {a.status}</div>
                </div>
                <button className="btn secondary" onClick={() => runSandbox(a.id)}>
                  تستِ sandbox
                </button>
              </div>
              {sandbox[a.id] && (
                <p className={sandbox[a.id].reachable ? "muted" : "danger"} style={{ marginTop: 8 }}>
                  {sandbox[a.id].reachable ? "✓ در دسترس" : "✕ ناموفق"} — {sandbox[a.id].detail}
                  {sandbox[a.id].latency_ms != null && ` (${sandbox[a.id].latency_ms}ms)`}
                </p>
              )}
            </div>
          ))}

          <div className="card">
            <strong>Webhook</strong>
            <input
              className="input"
              placeholder="https://example.com/webhooks/dilix"
              value={webhookUrl}
              onChange={(e) => setWebhookUrl(e.target.value)}
            />
            <button className="btn" style={{ marginTop: 8 }} onClick={addWebhook}>
              ثبتِ webhook
            </button>
            {webhook?.secret && (
              <div className="card" style={{ marginTop: 8 }}>
                <p className="muted">secretِ امضای HMAC (فقط همین یک‌بار نمایش داده می‌شود):</p>
                <code style={{ wordBreak: "break-all" }}>{webhook.secret}</code>
              </div>
            )}
          </div>

          <div className="card">
            <strong>کلیدهای API</strong>
            <div className="row" style={{ gap: 8, marginTop: 8 }}>
              <button className="btn secondary" onClick={() => issueKey("sandbox")}>
                کلیدِ sandbox
              </button>
              <button className="btn" onClick={() => issueKey("production")}>
                کلیدِ production
              </button>
            </div>
            {credential?.api_key && (
              <div className="card" style={{ marginTop: 8 }}>
                <p className="muted">کلیدِ خام ({credential.env}) — فقط همین یک‌بار:</p>
                <code style={{ wordBreak: "break-all" }}>{credential.api_key}</code>
              </div>
            )}
          </div>
        </>
      )}
    </main>
  );
}
