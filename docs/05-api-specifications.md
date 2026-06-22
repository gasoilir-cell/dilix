# سند ۵ — مشخصات API (API Specifications)
**فاز ۵** · Dilix v1.0

---

## ۱. اصول API

- **Contract-First:** OpenAPI 3.1 برای REST، AsyncAPI 2.x برای رویدادها، Protobuf برای gRPC داخلی.
- **Versioning:** مسیر نسخه‌دار `/v1/...`؛ رویدادها با `schemaVersion`.
- **Auth:** OAuth2 / OIDC + JWT کوتاه‌عمر + refresh؛ کلید API برای ارائه‌دهندگان.
- **Conventions:** snake_case در JSON، صفحه‌بندی cursor-based، `Idempotency-Key` برای POST حساس، RFC7807 برای خطاها.
- **Multi-region:** هدر `X-Region` و routing بر اساس `home_region`.

---

## ۲. الگوی خطا (RFC 7807)

```json
{
  "type": "https://dilix.app/errors/insufficient_kyc",
  "title": "KYC level too low",
  "status": 403,
  "detail": "این عملیات نیازمند سطح KYC 2 است.",
  "instance": "/v1/freight/shipments",
  "trace_id": "..."
}
```

---

## ۳. Identity & Auth API (نمونه OpenAPI)

```yaml
paths:
  /v1/auth/register:
    post:
      summary: ثبت‌نام و ایجاد Earth ID
      requestBody: { $ref: '#/components/schemas/RegisterRequest' }
      responses: { '201': { description: earth_id ایجاد شد } }
  /v1/auth/mfa/verify:
    post: { summary: تأیید کد MFA }
  /v1/identity/me:
    get: { summary: پروفایل من }
    patch: { summary: ویرایش پروفایل }
  /v1/identity/me/visibility:
    put:
      summary: تنظیم دیده‌شدن روی نقشه (opt-in)
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                discoverable: { type: boolean }
                audience: { enum: [public, verified, connections] }
                geo_precision: { enum: [exact, city, region] }
                visible_fields:
                  type: array
                  items: { enum: [gender, age_range, marital_status, profession, interests] }
```

---

## ۴. Discovery (3D Earth) API

```yaml
  /v1/discovery/nearby:
    get:
      summary: کشف افراد/کسب‌وکار در یک منطقه (فقط discoverable)
      parameters:
        - { name: region, in: query }            # یا bbox نقشه
        - { name: bbox, in: query }              # min/max lat,lng
        - { name: entity_type, in: query }
        - { name: gender, in: query }            # فقط روی opt-in اعمال
        - { name: age_range, in: query }
        - { name: profession, in: query }
        - { name: language, in: query }
        - { name: marital_status, in: query }
        - { name: business_category, in: query }
      responses:
        '200':
          description: نتایج در سطح geo_precision کاربرانِ هدف (مختصات دقیق برنمی‌گردد)
  /v1/discovery/{earth_id}/contact-request:
    post: { summary: درخواست شروع گفتگو با فرد کشف‌شده }
```

---

## ۵. Messaging API + Realtime

REST برای تاریخچه و آپلود؛ WebSocket برای زنده.

```yaml
  /v1/conversations: { get: {}, post: {} }
  /v1/conversations/{id}/messages:
    get: { summary: تاریخچه (ciphertext) }
    post:
      summary: ارسال پیام (E2EE - سرور فقط ciphertext)
      requestBody:
        content: { application/json: { schema: { properties: {
          content_type: {}, ciphertext: {}, media_key: {} } } } }
  /v1/devices/keys:
    post: { summary: ثبت کلید عمومی دستگاه (E2EE) }
```

**WebSocket events (realtime-gateway):**
```
client→server: typing, read_receipt, presence_ping
server→client: message.new, message.read, presence.update, call.signal
WebRTC: call.offer / call.answer / ice.candidate  (signaling) + SFU media
```

---

## ۶. Freight API

```yaml
  /v1/freight/shipments:
    post: { summary: ثبت بار → trigger تحلیل AI و انتشار به رانندگان }
    get:  { summary: فهرست/جستجوی بار (بر اساس منطقه راننده) }
  /v1/freight/shipments/{id}/bids:
    post: { summary: راننده بار را می‌پذیرد/پیشنهاد می‌دهد }
  /v1/freight/shipments/{id}/assign:
    post: { summary: صاحب بار راننده را تأیید می‌کند }
  /v1/freight/shipments/{id}/waybill:
    post: { summary: درخواست صدور بارنامه از Carrier Adapter (راهداری) }
  /v1/freight/shipments/{id}/confirmations:
    post: { summary: تأیید بارگیری/تحویل (دوطرفه) }
  /v1/freight/shipments/{id}/track:
    get: { summary: آخرین موقعیت GPS (همچنین stream از WS) }
```

---

## ۷. Insurance & Payment API

```yaml
  /v1/insurance/quotes:
    post: { summary: استعلام/مقایسه از بیمه‌گران (Adapter) }
  /v1/insurance/policies:
    post: { summary: صدور بیمه‌نامه از طریق بیمه‌گر مجاز }
  /v1/insurance/policies/{id}/claims:
    post: { summary: ثبت خسارت }

  /v1/payments/orders:
    post:
      summary: ایجاد سفارش پرداخت (Idempotency-Key الزامی)
      description: وجه نزد بانک (Escrow) نگه داشته می‌شود؛ Dilix فقط orchestrate
  /v1/payments/orders/{id}/escrow/release:
    post: { summary: آزادسازی Escrow پس از تحویل تأییدشده }
```

---

## ۸. Growth API (قانونی)

```yaml
  /v1/growth/referrals/link: { get: { summary: لینک دعوت من } }
  /v1/growth/rewards:        { get: { summary: کیف پاداش (gated به reward_event) } }
  /v1/growth/membership:     { post: { summary: ارتقای عضویت (Walmart+ style) } }
  /v1/growth/revenue-share:  { get: { summary: سهم از پول کارمزد (Vanguard style) } }
```
> هیچ endpointی برای «پاداشِ صرفِ عضوگیری» وجود ندارد؛ پاداش همیشه از `reward_event` واقعی مشتق می‌شود (ADR-08).

---

## ۹. Provider / Open API Marketplace

```yaml
  /v1/providers/register:        { post: { summary: ثبت‌نام ارائه‌دهنده (KYB) } }
  /v1/providers/me/apis:         { post: { summary: ثبت API توسط خود ارائه‌دهنده } }
  /v1/providers/me/apis/{id}/sandbox-test: { post: {} }
  /v1/providers/me/webhooks:     { post: { summary: ثبت webhook } }
  /v1/providers/me/credentials:  { post: { summary: کلید sandbox/production } }
```

**Provider Adapter Port (نمونه contract که ارائه‌دهنده پیاده می‌کند):**
```yaml
# Insurance Provider Port
POST /quote        -> { premium, coverage, policy_terms }
POST /issue        -> { policy_no, document_url }
POST /claim        -> { claim_no, status }
# Payment Provider Port
POST /hold         -> { hold_ref }
POST /release      -> { settlement_ref }
POST /refund       -> { refund_ref }
# Carrier Port
POST /waybill      -> { waybill_no, document_url }
GET  /track/{id}   -> { lat, lng, ts }
```

---

## ۱۰. AsyncAPI (نمونه رویداد)

```yaml
channels:
  freight.delivered:
    subscribe:
      message:
        payload:
          type: object
          properties:
            shipment_id: { type: string }
            delivered_at: { type: string, format: date-time }
            economic_value: { type: number }   # مصرف توسط growth/reputation
        x-schemaVersion: 1
```
