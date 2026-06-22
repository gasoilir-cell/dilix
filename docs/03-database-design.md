# سند ۳ — طراحی پایگاه‌داده (Database Design)
**فاز ۳** · Dilix v1.0

---

## ۱. اصول داده

- **Database-per-Context:** هر Bounded Context schema/دیتابیس مجزای خودش (در Modular Monolith با schema جدا در یک Postgres؛ هنگام تفکیک، instance جدا).
- **هیچ JOIN بین‌Contextی** — ارتباط فقط با رویداد یا API.
- **Data Residency:** جدول‌های دارای PII در ریجن کشور؛ Global Identity Plane حداقلی.
- **Polyglot Persistence:** Postgres (تراکنشی)، Redis (cache/presence/session)، Elasticsearch (جستجو/feed/discovery read-model)، MinIO (مدیا)، Vector DB (RAG).

---

## ۲. نگاشت ذخیره‌سازی به ماژول

| ماژول | Postgres | Redis | Elasticsearch | MinIO | Vector |
|---|---|---|---|---|---|
| Identity | ✓ | session | پروفایل (search) | avatar | — |
| Discovery (Earth) | ✓ (geo) | presence (geo) | ✓ کشف | — | — |
| Messaging | ✓ (metadata) | presence/typing | جستجوی پیام (opt) | فایل | — |
| Social | ✓ | counters | feed/search | media | — |
| Freight | ✓ | tracking live | جستجوی بار | اسناد | — |
| Insurance | ✓ | — | — | بیمه‌نامه PDF | — |
| Payment | ✓ (ledger ref) | idempotency | — | رسید | — |
| Reputation | ✓ | cache score | — | — | — |
| Growth | ✓ (ledger) | — | leaderboard | — | — |
| AI | ✓ (sessions) | — | — | — | ✓ knowledge |

---

## ۳. مدل داده‌ی Identity (هسته)

```
earth_identity
  earth_id            UUID PK            -- شناسه جهانی
  entity_type         ENUM(individual,business,driver,cargo_owner,
                            logistics,insurer,insurance_agent,financial,
                            telecom,freelancer,healthcare,education,
                            government,moderator,admin...)
  status              ENUM(active,suspended,deleted)
  kyc_level           SMALLINT           -- 0..3
  home_region         VARCHAR(8)         -- IR, RU, OM, TR ...
  created_at, updated_at TIMESTAMPTZ

profile  (1:1 earth_identity)
  earth_id FK, display_name, gender, birth_date, marital_status,
  languages[], interests[], education, bio, avatar_url

professional_profile (1:1)
  earth_id FK, profession, company, business_category, skills[], links[]

visibility_settings (1:1)             -- ADR-06
  earth_id FK,
  discoverable BOOL DEFAULT false,    -- opt-in
  visible_fields[] ,                  -- چه چیزی دیده شود
  audience ENUM(public,verified,connections),
  geo_precision ENUM(exact,city,region) DEFAULT region  -- fuzzing

kyc_document
  id PK, earth_id FK, doc_type, storage_key(MinIO), verified_by, verified_at
```

---

## ۴. مدل داده‌ی Discovery (نقشه 3D)

```
presence (Redis GEO + Postgres snapshot)
  earth_id, geo_hash, lat_fuzzed, lng_fuzzed, region, last_seen,
  online BOOL
-- Redis: GEOADD presence:<region> lng lat earth_id  (برای کوئری شعاعی سریع)

discovery_index (Elasticsearch)
  earth_id, entity_type, display_name, profession, business_category,
  languages, interests, gender?, age_range?, marital_status?,  -- فقط اگر opt-in
  geo_point(region-level), reputation_score
```
> نمایش روی نقشه فقط برای کاربرانِ `discoverable=true` و در سطح `geo_precision`. مختصات دقیق هرگز به سمت کلاینت دیگر نمی‌رود.

---

## ۵. مدل داده‌ی Messaging

```
conversation        id PK, type(private,group), created_at
participant         conversation_id FK, earth_id, role, joined_at
message             id PK, conversation_id FK, sender_id,
                    content_type, ciphertext BYTEA,   -- E2EE: سرور متن خام ندارد
                    media_key(MinIO opt), created_at, edited_at, deleted_at
message_receipt     message_id FK, earth_id, state(delivered,read), at
device_key          earth_id, device_id, public_key   -- E2EE key registry
```
> سرور فقط ciphertext و metadata را نگه می‌دارد (ADR-05). چت با AI در conversation جداگانه‌ی **غیر-E2EE** است.

---

## ۶. مدل داده‌ی Freight

```
shipment
  id PK, owner_id, origin_geo, dest_geo, cargo_type, weight, volume,
  price_suggested, price_final, status(
    posted,matched,assigned,waybill_issued,picked_up,in_transit,delivered,settled,cancelled),
  created_at
bid               id PK, shipment_id FK, driver_id, amount, status, created_at
assignment        shipment_id FK, driver_id, confirmed_by_owner BOOL,
                  confirmed_by_driver BOOL
waybill_ref       shipment_id FK, carrier_provider_id, external_waybill_no,
                  issued_at, document_key(MinIO)
tracking_point    shipment_id FK, lat, lng, recorded_at   -- time-series (می‌تواند به TSDB برود)
delivery_confirmation shipment_id FK, receiver_signature_key, confirmed_at
```

---

## ۷. مدل داده‌ی Insurance / Payment

```
policy_application
  id PK, applicant_id, insurance_type, target_ref(shipment/vehicle/person),
  quote_amount, provider_id, status(quoted,issued,renewed,claimed),
  policy_document_key(MinIO)
claim   id PK, policy_id FK, description, amount, status, filed_at

payment_order
  id PK, payer_id, payee_id, amount, currency,
  escrow_state(none,held,released,refunded),
  provider_ref,                      -- رفرنس بانک سامان (وجه نزد بانک)
  idempotency_key UNIQUE, created_at
payment_event  id PK, payment_order_id FK, type, provider_payload_ref, at
```
> **مهم:** Dilix موجودی واقعی نگه نمی‌دارد؛ `provider_ref` به Escrow بانک سامان اشاره می‌کند (ADR-07).

---

## ۸. مدل داده‌ی Growth & Incentives (قانونی)

```
referral_edge
  inviter_id, invitee_id, level SMALLINT,   -- ≤ 3 (ADR-08)
  activated BOOL, activated_at
reward_event
  id PK, earth_id, source(freight_settled,payment_done,subscription,...),
  economic_value, ref_id                    -- باید به تراکنش واقعی گره بخورد
reward_ledger_entry
  id PK, earth_id, reward_event_id FK, level, amount, capped BOOL, created_at
membership      earth_id, tier(basic,plus,pro), valid_until   -- Walmart+ style
revenue_share_pool  period, total_fees, distributed, policy   -- Vanguard style
```
> Invariant سطح دیتابیس: درج `reward_ledger_entry` بدون `reward_event` معتبر مجاز نیست (جلوگیری از پاداشِ صرفِ عضوگیری → اجتناب از طرح هرمی).

---

## ۹. مدل داده‌ی Reputation / AI / Provider

```
reputation_score   earth_id, trust, business, logistics, insurance,
                   financial, community, global_ai, computed_at
ai_session         id PK, earth_id, agent_type, started_at
ai_message         session_id FK, role, content, tokens, created_at
knowledge_chunk    (Vector DB) id, source, embedding, text, acl

provider           id PK, legal_name, type, country, license_no,
                   kyb_status(pending,verified,rejected), created_at
provider_api       id PK, provider_id FK, name, spec_url, env(sandbox,prod),
                   status, webhook_url
provider_credential provider_id FK, key_hash, scopes[], env
```

---

## ۱۰. سیاست‌های داده

- **Audit:** هر تغییر حساس → `audit_log` (append-only) در Audit Context.
- **Soft-delete + Right-to-erasure:** برای GDPR، حذف PII با نگهداری hashِ بی‌بازگشت برای یکپارچگی مالی.
- **Encryption at rest** برای ستون‌های حساس (KYC، اسناد) + TLS in transit.
- **Migration ایمن:** برای پروژه‌ی دارای کاربر فعال، تغییرات با مهارت `db-migration-planner` و الگوی expand/contract.
- **Partitioning:** `message`, `tracking_point`, `audit_log`, `reward_ledger_entry` بر اساس زمان/ریجن.
