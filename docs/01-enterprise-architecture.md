# سند ۱ — معماری سازمانی (Enterprise Architecture)
**فاز ۱** · Dilix v1.0

---

## ۱. چشم‌انداز معماری

Dilix یک پلتفرم چندوجهی (multi-sided platform) است با سه گروه ذی‌نفع:

1. **کاربران نهایی** (افراد، رانندگان، صاحبان بار، فریلنسرها).
2. **ارائه‌دهندگان خدمات** (بانک، بیمه، حمل‌ونقل، اپراتور، third-party).
3. **ناظران/ادمین‌ها** (Moderator، Regional/Country/Global Admin، رگولاتورها).

اصل معماری: **«هسته‌ی واسط + پلاگین‌های ارائه‌دهنده»**. هسته (Core) ثابت و امن است؛ ارائه‌دهندگان از طریق Adapterهای استاندارد متصل می‌شوند.

---

## ۲. نمای System Context (C4 — Level 1)

```mermaid
graph TB
    subgraph Users
      U1[Individual / Driver / Cargo Owner]
      U2[Business / Freelancer]
    end
    subgraph Providers
      P1[Bank Saman - PSP]
      P2[Bime Alborz - Insurance]
      P3[Iran Transport Org / Carriers]
      P4[Telecom Operators]
      P5[Third-Party API Providers]
    end
    Dilix((Dilix Platform))
    Reg[Regulators: شاپرک / بیمه مرکزی / راهداری]

    U1 --> Dilix
    U2 --> Dilix
    Dilix <--> P1
    Dilix <--> P2
    Dilix <--> P3
    Dilix <--> P4
    Dilix <--> P5
    Dilix -. compliance/reporting .-> Reg
```

---

## ۳. نمای Container (C4 — Level 2)

```mermaid
graph TB
    subgraph Client
      M[Flutter Mobile/Desktop]
      W[Next.js Web + PWA]
      PP[Provider Portal - Next.js]
      AD[Admin Console - Next.js]
    end

    GW[API Gateway / BFF]
    RT[Realtime Gateway - WS/WebRTC]

    subgraph PlatformCore [Layer 0 - Platform Core]
      IAM[Identity & Earth ID]
      AUTH[Auth / MFA / Session]
      AUTHZ[Authorization RBAC/ABAC]
      PAF[Provider Adapter Framework]
      EVT[Event Backbone - Kafka/NATS]
      NOTIF[Notification]
      I18N[i18n / Localization]
      AIGW[AI Gateway]
    end

    subgraph Engagement [Layer 1]
      MSG[Messenger]
      SOC[Social]
      EARTH[3D Earth Discovery]
      GROW[Growth & Incentives]
    end

    subgraph Verticals [Layer 2+]
      FRT[Freight]
      INS[Insurance]
      FIN[Financial Orchestration]
      TEL[Telecom]
      SVC[Service Marketplace]
    end

    DBs[(PostgreSQL / Redis / Elasticsearch / MinIO)]

    M --> GW
    W --> GW
    PP --> GW
    AD --> GW
    M --> RT
    W --> RT
    GW --> PlatformCore
    GW --> Engagement
    GW --> Verticals
    RT --> MSG
    Verticals --> PAF
    PAF <--> ProvidersExt[External Provider APIs]
    PlatformCore --> EVT
    Engagement --> EVT
    Verticals --> EVT
    PlatformCore --> DBs
    Engagement --> DBs
    Verticals --> DBs
    AIGW --> LLM[LLM Providers / Local Models]
```

---

## ۴. سبک معماری

- **API-First / Contract-First:** هر سرویس قبل از کد، OpenAPI (sync) و AsyncAPI (events) دارد.
- **Modular Monolith → Microservices تدریجی:** لایه ۰ و ۱ ابتدا به‌صورت چند سرویس درشت (Core، Engagement، Vertical) با مرزهای ماژولار داخلی؛ تفکیک به میکروسرویس وقتی scale واقعی ایجاب کند.
- **Event-Driven:** ارتباط بین Bounded Contextها از طریق رویداد (Kafka یا NATS JetStream). درخواست‌های همزمان از طریق API Gateway.
- **CQRS سبک** در ماژول‌های پرخواندن (Social feed, Earth discovery, Reputation) با Elasticsearch به‌عنوان read-model.
- **BFF (Backend-for-Frontend)** جدا برای Mobile، Web، Provider Portal، Admin.

---

## ۵. استراتژی Multi-Region / Hybrid

```mermaid
graph LR
    subgraph IranRegion [Region: Iran - ابر داخلی]
      IR_CORE[Core+Engagement+Verticals]
      IR_DB[(Data - residency ایران)]
      IR_PSP[Adapter سامان/شاپرک]
    end
    subgraph GlobalRegion [Region: Global - بین‌المللی]
      GL_CORE[Core+Engagement+Verticals]
      GL_DB[(Data - residency منطقه‌ای)]
      GL_PSP[Adapter بین‌المللی]
    end
    EarthID[Earth ID - Global Identity Plane]
    EarthID -. هویت یکپارچه، داده محلی .- IranRegion
    EarthID -. هویت یکپارچه، داده محلی .- GlobalRegion
```

اصل **Data Residency**: داده‌ی شخصی هر کاربر در ریجن کشورش ذخیره می‌شود. فقط **شناسه و متادیتای هویتی حداقلی** (Earth ID Global Plane) بین‌ریجنی است. این هم‌زمان GDPR (اروپا)، قوانین داده‌ی ایران، و الزامات روسیه/عمان/ترکیه را پوشش می‌دهد.

---

## ۶. لایه‌بندی منطقی

| لایه | مسئولیت |
|---|---|
| **Experience** | Flutter, Next.js, PWA, Provider Portal, Admin |
| **Edge** | CDN, WAF, API Gateway, Realtime Gateway, Rate Limiting |
| **Application (Domain)** | Bounded Contextها (Core, Engagement, Verticals) |
| **Integration** | Provider Adapter Framework, Event Backbone, AI Gateway |
| **Data** | PostgreSQL, Redis, Elasticsearch, MinIO, Vector DB |
| **Platform/Infra** | Kubernetes, Service Mesh, Observability, Secrets |

---

## ۷. کیفیت‌های معماری (Non-Functional / Architecture Drivers)

| ویژگی | هدف baseline |
|---|---|
| Availability | 99.9% (Core/Messenger 99.95%) |
| Latency (API p95) | < 300ms داخل ریجن |
| Realtime delivery | < 1s تحویل پیام |
| Scalability | افقی؛ طراحی برای 10M+ MAU، 100k اتصال همزمان WS در فاز رشد |
| Data residency | per-region، قابل‌اثبات |
| Security | Zero Trust، E2EE برای پیام، audit کامل |
| Extensibility | افزودن ارائه‌دهنده‌ی جدید بدون تغییر هسته |
| Observability | Tracing (OpenTelemetry)، Metrics (Prometheus)، Logs ساختاریافته |

---

## ۸. Provider Adapter Framework (ستون فقرات)

هر ماژول vertical یک **Port** استاندارد تعریف می‌کند؛ هر ارائه‌دهنده یک **Adapter** که آن Port را پیاده می‌کند.

```mermaid
graph LR
    INS[Insurance Domain] -->|Port: IssuePolicy/Quote/Claim| AlborzAdapter
    INS -->|Port| OtherInsurerAdapter
    FRT[Freight Domain] -->|Port: IssueWaybill/Track| CarrierAdapter
    FIN[Financial Domain] -->|Port: Pay/Refund/Settle/Escrow| SamanAdapter
    FIN -->|Port| IntlPSPAdapter
    AlborzAdapter --> AlborzAPI[(Bime Alborz API)]
    SamanAdapter --> SamanAPI[(Saman PSP API)]
    CarrierAdapter --> RahdariAPI[(راهداری/باربری API)]
```

ویژگی‌ها:
- **Capability Registry:** هر Adapter قابلیت‌هایش را اعلام می‌کند (مثلاً «بیمه باربری»، «بیمه ثالث»).
- **Self-Registration + KYB:** ارائه‌دهنده از Provider Portal ثبت‌نام می‌کند، مدارک مجوز را آپلود می‌کند، در Sandbox تست، سپس approval.
- **Contract Versioning + Sandbox + Production keys.**
- **Resilience:** Circuit Breaker، Retry، Timeout، Idempotency برای هر فراخوانی بیرونی.

---

## ۹. جریان نمونه (Cross-Cutting) — اعلام بار تا تسویه

```mermaid
sequenceDiagram
    actor Owner as صاحب بار
    participant FRT as Freight
    participant AI as AI Gateway
    participant DRV as رانندگان
    participant CAR as Carrier Adapter (راهداری)
    participant INS as Insurance (البرز)
    participant FIN as Financial (سامان)

    Owner->>FRT: ثبت بار (مبدا/مقصد/نوع)
    FRT->>AI: تحلیل و قیمت پیشنهادی
    FRT->>DRV: انتشار به رانندگان منطقه (Earth)
    DRV-->>FRT: پذیرش بار
    Owner->>FRT: تأیید راننده
    FRT->>CAR: درخواست صدور بارنامه
    CAR-->>FRT: بارنامه‌ی رسمی
    Owner->>INS: (اختیاری) صدور بیمه‌ی بار
    INS-->>Owner: بیمه‌نامه
    FRT->>FIN: قفل وجه در Escrow بانکی
    Note over DRV,FRT: بارگیری → تأیید دوطرفه → GPS Tracking
    DRV->>FRT: تحویل + تأیید گیرنده
    FRT->>FIN: آزادسازی Escrow → تسویه با راننده
```

---

## ۱۰. ریسک‌های معماری و کاهش آن‌ها

| ریسک | اثر | کاهش |
|---|---|---|
| تحریم زیرساخت بین‌المللی | عدم دسترسی ایران | Hybrid، ابر داخلی، عدم وابستگی سخت به یک کلاد |
| Scope بزرگ | تأخیر/شکست | ساخت لایه‌ای، طراحی جامع/اجرای محدود |
| وابستگی به ارائه‌دهنده‌ی واحد | تک‌نقطه شکست | Adapter چندگانه + fallback |
| حریم‌خصوصی نقشه افراد | ریسک حقوقی/ایمنی | Opt-in + fuzzing + privacy-by-design |
| تناقض E2EE با AI | نقض رمزنگاری | مرزبندی صریح (سند ۶ و ۸) |
| رگولاتوری مالی/بیمه | توقف فعالیت | نقش «واسط»، وجه نزد بانک، کارگزاری بیمه |
