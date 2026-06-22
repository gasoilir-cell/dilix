# سند ۶ — طراحی امنیت (Security Design)
**فاز ۶** · Dilix v1.0

---

## ۱. مدل تهدید (خلاصه STRIDE)

| تهدید | سطح حساس | کنترل |
|---|---|---|
| سرقت هویت/حساب | بالا | MFA، device binding، anomaly detection |
| نشت PII (نقشه افراد) | بالا | opt-in، geo fuzzing، minimization |
| تقلب مالی | بالا | idempotency، escrow بانکی، fraud engine |
| سوءاستفاده Adapter | متوسط | mTLS، scope، rate-limit، KYB |
| طرح هرمی (drift به Ponzi) | حقوقی | gating پاداش به reward_event، سقف، عمق ۳ |
| شنود پیام | بالا | E2EE، forward secrecy |
| دسترسی افقی (IDOR) | بالا | ABAC، ownership check |

---

## ۲. Zero Trust

- هیچ اعتماد ضمنی به شبکه؛ هر فراخوانی احراز و مجوزسنجی می‌شود.
- **mTLS** بین تمام سرویس‌ها (Service Mesh).
- **Workload Identity** (SPIFFE/SVID) برای سرویس‌ها.
- **Least Privilege** برای همه‌ی credentialها؛ secrets در Vault.

---

## ۳. هویت و دسترسی

- **AuthN:** OIDC، JWT کوتاه‌عمر (≤15m) + refresh چرخشی، device key.
- **MFA:** TOTP/SMS/Push؛ اجباری برای نقش‌های مالی/ادمین/ارائه‌دهنده.
- **AuthZ دو لایه:**
  - **RBAC:** نقش‌ها (۱۷ نوع کاربر سند اصلی) → permissionها.
  - **ABAC:** سیاست‌های زمینه‌ای (region، kyc_level، ownership، relationship). PDP مرکزی (OPA/Cedar).

```rego
# نمونه سیاست ABAC (شبه‌کد OPA)
allow {
  input.action == "freight.release_escrow"
  input.resource.owner_id == input.subject.earth_id
  input.resource.status == "delivered"
  input.subject.kyc_level >= 2
}
```

---

## ۴. رمزنگاری End-to-End و مرز با AI (ADR-05)

```mermaid
graph LR
    A[کاربر A] -- ciphertext --> S[(سرور: فقط ذخیره‌ی رمز)]
    S -- ciphertext --> B[کاربر B]
    A -.کلید فقط روی دستگاه.- A
    B -.کلید فقط روی دستگاه.- B
    subgraph AI Chat (جدا - غیر E2EE)
      A2[کاربر] --> AIGW[AI Gateway: متن قابل‌پردازش]
    end
```

- پیام‌های کاربر-به-کاربر: **E2EE** (پروتکل نوع Signal/MLS، X3DH + Double Ratchet، forward secrecy). سرور هرگز plaintext ندارد.
- چت با **AI** در conversationِ جداگانه و **آگاهانه غیر-E2EE** است (چون AI باید بخواند). در UI به‌وضوح متمایز و با رضایت کاربر.
- جستجوی پیام E2EE فقط سمت کلاینت (client-side index).

---

## ۵. امنیت داده

- **At rest:** رمزنگاری دیسک + رمزنگاری ستونی برای PII/KYC/اسناد (envelope encryption، KMS).
- **In transit:** TLS 1.3 همه‌جا + mTLS داخلی.
- **Data minimization:** نقشه فقط فیلدهای opt-in و در سطح geo_precision.
- **Tokenization** برای داده‌ی پرداخت؛ هیچ PAN/کارت در Dilix ذخیره نمی‌شود (PCI scope حداقلی، نزد PSP).
- **Key management:** HSM/KMS؛ چرخش کلید؛ جداسازی کلید per-region.

---

## ۶. امنیت Adapterها و ارائه‌دهندگان

- **KYB اجباری** قبل از production: بررسی مجوز (بیمه مرکزی/راهداری/بانک مرکزی).
- **Sandbox isolation:** کلید sandbox هرگز به داده‌ی production دسترسی ندارد.
- **Scoped credentials + rate-limit + IP allowlist** برای هر provider.
- **Signed webhooks** (HMAC) + replay protection.
- **mTLS** برای اتصال‌های حساس (سامان/البرز).

---

## ۷. تشخیص تقلب و تهدید (AI-assisted)

- **Fraud Engine:** قواعد + مدل ML برای الگوهای مشکوک (پرداخت، رفرال، multi-account).
- **Anti-Pyramid Guard:** پایش گراف رفرال برای شناسایی الگوی هرمی؛ مسدودسازی پاداشِ بدون reward_event.
- **AI Threat Detection:** ناهنجاری در login، API abuse، bot detection.
- **Rate limiting / WAF / Bot management** در لبه.

---

## ۸. Audit & Compliance

- **Audit log** append-only (hash-chained) برای عملیات حساس؛ غیرقابل‌تغییر.
- **Compliance by design:**
  - **GDPR:** consent، right-to-access/erasure، DPIA برای نقشه افراد.
  - **داده‌ی ایران/روسیه/عمان/ترکیه:** data residency per-region.
  - **مالی:** AML/KYC، گزارش‌دهی به بانک شریک.
  - **بیمه:** ضوابط بیمه مرکزی از طریق کارگزاری.
- **Lawful access:** هر دسترسی قانونی فقط روی metadata؛ E2EE حفظ می‌شود.

---

## ۹. SDLC امن

- SAST/DAST، dependency scanning، secret scanning در CI.
- Threat modeling برای هر feature حساس.
- Pen-test پیش از launch هر vertical.
- Least-privilege CI/CD؛ امضای image؛ SBOM.
