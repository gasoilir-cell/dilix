"""
Dilix — AI Chat Router
POST /api/v1/ai/chat    ارسال پیام و دریافت پاسخ
GET  /api/v1/ai/history تاریخچه مکالمات
"""
import uuid as _uuid
import re
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, ForeignKey, String, Text, Integer, select
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, Base
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/ai", tags=["AI Assistant"])


def _now():
    return datetime.now(timezone.utc)


# ── Model ──────────────────────────────────────────────────────
class AIChatMessage(Base):
    __tablename__ = "ai_chat_messages"
    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id    = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    role       = Column(String(20), nullable=False)   # user | assistant
    content    = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Schemas ────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)


class ChatResponse(BaseModel):
    id: str
    role: str
    content: str
    created_at: datetime


# ── Knowledge Base ─────────────────────────────────────────────
_FREIGHT_RATES = {
    "تهران-مشهد": (950, 1400),
    "تهران-اصفهان": (600, 900),
    "تهران-شیراز": (950, 1350),
    "تهران-تبریز": (750, 1100),
    "تهران-اهواز": (1050, 1500),
    "تهران-کرمان": (1100, 1600),
    "تهران-رشت": (400, 650),
    "تهران-کرج": (150, 250),
    "اصفهان-مشهد": (1200, 1700),
    "شیراز-مشهد": (1800, 2500),
}

_INSURANCE_RATES = {
    "الکترونیک": "۰.۸٪", "مواد فاسدشدنی": "۰.۶٪", "ماشین‌آلات": "۰.۵٪",
    "منسوجات": "۰.۴٪",   "مواد اولیه": "۰.۳٪",      "مواد شیمیایی": "۰.۹٪",
    "خودرو": "۰.۶٪",      "عمومی": "۰.۴٪",
}


def _extract_numbers(text: str):
    return [int(n.replace(",", "")) for n in re.findall(r"\d[\d,]*", text)]


def _find_route(text: str):
    for route, (lo, hi) in _FREIGHT_RATES.items():
        cities = route.split("-")
        if all(c in text for c in cities):
            return route, lo, hi
    return None, None, None


def generate_response(question: str, user: User) -> str:
    """موتور پاسخ هوشمند دیلیکس"""
    q = question.strip()
    ql = q.lower()

    # ── احوالپرسی ─────────────────────────────
    greetings = ["سلام", "درود", "هلو", "hello", "hi", "چطوری", "خوبی"]
    if any(g in ql for g in greetings) and len(q) < 20:
        name = user.full_name.split()[0] if user.full_name else "دوست عزیز"
        return (
            f"سلام {name} عزیز! 👋\n\n"
            "من دستیار هوشمند دیلیکس هستم. می‌تونم کمکت کنم با:\n\n"
            "• 🚛 **محاسبه قیمت باربری** بین شهرها\n"
            "• 🛡️ **استعلام بیمه بار** با نرخ دقیق\n"
            "• 📍 **راهنمای ثبت بار** یا قبول بار\n"
            "• 💰 **امور مالی** — کیف پول و escrow\n"
            "• ❓ **پاسخ به سوالات** درباره پلتفرم\n\n"
            "چطور می‌تونم کمکت کنم؟"
        )

    # ── محاسبه قیمت باربری ────────────────────
    if any(k in ql for k in ["قیمت", "هزینه", "کرایه", "نرخ", "چقدر", "محاسبه"]) and \
       any(k in ql for k in ["بار", "باربری", "حمل", "ارسال", "تن", "کیلو"]):

        route, lo, hi = _find_route(q)
        nums = _extract_numbers(q)
        weight = next((n for n in nums if 1 <= n <= 100000), None)

        if route:
            lo_total = lo * (weight or 1) * 1000 if weight else lo * 1000 * 10  # per ton or estimate
            hi_total = hi * (weight or 1) * 1000 if weight else hi * 1000 * 10
            w_str = f"برای {weight:,} کیلوگرم" if weight else "برای یک تریلر استاندارد"
            return (
                f"🚛 **قیمت باربری {route}**\n\n"
                f"{w_str}:\n"
                f"• حداقل: **{lo_total:,}** تومان\n"
                f"• حداکثر: **{hi_total:,}** تومان\n\n"
                f"💡 نرخ پایه: {lo:,}–{hi:,} تومان/تن\n\n"
                "برای دریافت پیشنهاد دقیق‌تر، بار را در صفحه **باربری** ثبت کنید تا رانندگان قیمت بدهند."
            )
        elif weight:
            return (
                f"🚛 برای **{weight:,} کیلوگرم** بار:\n\n"
                "برای محاسبه دقیق، مسیر را هم بگو. مثال:\n"
                "_قیمت حمل ۵۰۰ کیلو از تهران به مشهد چقدره؟_\n\n"
                "نرخ‌های رایج (تومان/تن):\n"
                "• تهران–مشهد: ۹۵۰,۰۰۰ – ۱,۴۰۰,۰۰۰\n"
                "• تهران–اصفهان: ۶۰۰,۰۰۰ – ۹۰۰,۰۰۰\n"
                "• تهران–شیراز: ۹۵۰,۰۰۰ – ۱,۳۵۰,۰۰۰"
            )
        else:
            return (
                "🚛 **نرخ‌نامه باربری** (تومان به ازای هر تن):\n\n"
                "| مسیر | حداقل | حداکثر |\n"
                "|------|-------|--------|\n"
                "| تهران–مشهد | ۹۵۰,۰۰۰ | ۱,۴۰۰,۰۰۰ |\n"
                "| تهران–اصفهان | ۶۰۰,۰۰۰ | ۹۰۰,۰۰۰ |\n"
                "| تهران–شیراز | ۹۵۰,۰۰۰ | ۱,۳۵۰,۰۰۰ |\n"
                "| تهران–تبریز | ۷۵۰,۰۰۰ | ۱,۱۰۰,۰۰۰ |\n"
                "| تهران–اهواز | ۱,۰۵۰,۰۰۰ | ۱,۵۰۰,۰۰۰ |\n\n"
                "قیمت‌ها بسته به نوع ماشین، فصل و اورژانسی‌بودن متفاوت است."
            )

    # ── بیمه بار ──────────────────────────────
    if any(k in ql for k in ["بیمه", "خسارت", "پوشش", "سرقت", "حق بیمه"]):
        cargo = next((c for c in _INSURANCE_RATES if c in q), None)
        nums = _extract_numbers(q)
        value = next((n for n in nums if n >= 1_000_000), None)

        if cargo and value:
            rate_str = _INSURANCE_RATES[cargo]
            rate_num = float(rate_str.replace("٪", "").replace("۰.", "0.").replace("۸", "8").replace("۶", "6").replace("۵", "5").replace("۴", "4").replace("۳", "3").replace("۹", "9")) / 100
            premium = int(value * rate_num)
            return (
                f"🛡️ **استعلام بیمه {cargo}**\n\n"
                f"• ارزش کالا: {value:,} تومان\n"
                f"• نرخ بیمه: {rate_str} سالانه\n"
                f"• **حق بیمه تقریبی: {premium:,} تومان**\n\n"
                "برای صدور رسمی و ثبت درخواست، به صفحه **بیمه بار** برو."
            )

        return (
            "🛡️ **راهنمای بیمه بار دیلیکس**\n\n"
            "**نوع پوشش‌ها:**\n"
            "• **پایه** — خسارت فیزیکی در حمل (نرخ پایه)\n"
            "• **جامع** — پایه + سرقت (۱.۵× نرخ پایه)\n"
            "• **همه‌خطر** — کامل‌ترین پوشش (۲.۱× نرخ)\n\n"
            "**نرخ بیمه بر اساس نوع کالا:**\n" +
            "\n".join(f"• {c}: {r}" for c, r in _INSURANCE_RATES.items()) +
            "\n\n💡 برای استعلام دقیق: بگو «بیمه ۵۰۰ میلیون الکترونیک»"
        )

    # ── ثبت بار / راهنمای راننده ─────────────
    if any(k in ql for k in ["ثبت بار", "پست بار", "آگهی بار", "بار ثبت"]):
        return (
            "📦 **راهنمای ثبت بار:**\n\n"
            "۱. به صفحه **باربری** برو\n"
            "۲. دکمه «ثبت بار جدید» را بزن\n"
            "۳. اطلاعات را کامل کن:\n"
            "   • مبدأ و مقصد\n"
            "   • نوع و وزن کالا\n"
            "   • قیمت پیشنهادی\n"
            "   • تاریخ بارگیری\n"
            "۴. منتظر پیشنهاد رانندگان بمان\n\n"
            "💡 بار بیمه‌شده جذاب‌تر است — از صفحه بیمه استفاده کن."
        )

    if any(k in ql for k in ["راننده", "تریلر", "کامیون", "ثبت نام راننده", "ثبت‌نام"]) and \
       any(k in ql for k in ["چطور", "نحوه", "چگونه", "راهنما"]):
        return (
            "🚛 **ثبت‌نام راننده در دیلیکس:**\n\n"
            "۱. **انتخاب نقش**: در پروفایل، نقش «راننده» انتخاب کن\n"
            "۲. **تأیید هویت (KYC)**: اطلاعات شناسنامه‌ای بارگذاری کن\n"
            "۳. **مدارک خودرو**: گواهینامه + بیمه ناوگان\n"
            "۴. **تأیید پلتفرم**: ۱ تا ۲ روز کاری\n\n"
            "پس از تأیید، بارهای موجود در صفحه **باربری** برات نمایش داده می‌شه."
        )

    # ── کیف پول و مالی ───────────────────────
    if any(k in ql for k in ["کیف پول", "موجودی", "شارژ", "واریز", "برداشت", "انتقال"]):
        return (
            "💰 **کیف پول دیلیکس:**\n\n"
            "**موجودی‌ها:**\n"
            "• **آزاد** — قابل برداشت و انتقال\n"
            "• **اسکرو** — امانت قراردادها\n"
            "• **جایزه** — پاداش معرفی دوستان\n\n"
            "**عملیات:**\n"
            "• 🔼 **شارژ**: از درگاه شاپرک (بانک سامان)\n"
            "• 🔽 **برداشت**: به شماره شبا (۱–۳ روز)\n"
            "• ↔️ **انتقال**: با Earth ID گیرنده فوری\n\n"
            "برای مشاهده موجودی واقعی، صفحه **کیف پول** را باز کن."
        )

    # ── Earth Map ────────────────────────────
    if any(k in ql for k in ["کره زمین", "earth", "نقشه", "کاربران"]):
        return (
            "🌍 **کره زمین دیلیکس:**\n\n"
            "کره سه‌بعدی دیلیکس نشان می‌دهد:\n"
            "• رانندگان فعال در سراسر کشور و جهان\n"
            "• صاحبان بار و کارگزاران\n"
            "• نمایندگان بیمه\n\n"
            "**قابلیت‌ها:**\n"
            "• فیلتر بر اساس نقش (راننده/صاحب بار/...)\n"
            "• کلیک روی هر کاربر و شروع مکالمه مستقیم\n"
            "• نمایش clustering برای مناطق پرجمعیت\n\n"
            "💡 برای دیده‌شدن، گزینه «نمایش روی کره» را در پروفایل فعال کن."
        )

    # ── پلتفرم ───────────────────────────────
    if any(k in ql for k in ["دیلیکس", "پلتفرم", "چیه", "چیست", "معرفی"]):
        return (
            "🌐 **دیلیکس (Dilix) چیست؟**\n\n"
            "دیلیکس یک **پلتفرم B2B2C جهانی** برای اتصال:\n\n"
            "• 🚛 **رانندگان** با صاحبان بار\n"
            "• 📦 **صاحبان بار** با کارگزاران حمل\n"
            "• 🛡️ **نمایندگان بیمه** با مشتریان\n"
            "• 💼 **شرکت‌ها** با شبکه جهانی\n\n"
            "**خدمات اصلی:**\n"
            "باربری · بیمه · کیف پول Escrow · پیام‌رسان · Earth Map\n\n"
            f"Earth ID شما: **{user.earth_id}**"
        )

    # ── KYC ──────────────────────────────────
    if any(k in ql for k in ["kyc", "تأیید هویت", "احراز هویت", "مدارک", "سطح"]):
        kyc = user.kyc_level or 0
        return (
            f"🔐 **تأیید هویت (KYC)**\n\n"
            f"سطح فعلی شما: **{kyc} از ۵**\n\n"
            "**سطح‌ها:**\n"
            "• **۰** — ثبت‌نام (محدود)\n"
            "• **۱** — تأیید شماره موبایل\n"
            "• **۲** — احراز هویت پایه (کارت ملی)\n"
            "• **۳** — تأیید کامل (چهره)\n"
            "• **۴** — کسب‌وکار تأیید شده\n"
            "• **۵** — Enterprise\n\n"
            "برای ارتقا، صفحه **پروفایل → ارتقای سطح تأیید** را ببین."
        )

    # ── پیش‌فرض ──────────────────────────────
    return (
        "🤔 سوال جالبیه!\n\n"
        "من می‌تونم درباره این موضوعات کمکت کنم:\n\n"
        "• 🚛 **قیمت باربری** بین شهرها\n"
        "• 🛡️ **استعلام بیمه** بار\n"
        "• 📦 **راهنمای ثبت بار** و قبول بار\n"
        "• 💰 **کیف پول** و انتقال وجه\n"
        "• 🌍 **کره زمین** و شبکه‌سازی\n"
        "• ❓ **سوالات** درباره دیلیکس\n\n"
        "سوالت را دقیق‌تر بنویس تا بهتر کمکت کنم."
    )


# ── Endpoints ──────────────────────────────────────────────────

@router.post("/chat", response_model=ChatResponse, status_code=201)
async def chat(
    body: ChatRequest,
    db:   AsyncSession = Depends(get_db),
    me:   User         = Depends(get_current_user),
):
    # save user message
    user_msg = AIChatMessage(user_id=me.id, role="user", content=body.message)
    db.add(user_msg)

    # generate response
    answer = generate_response(body.message, me)

    # save assistant message
    ai_msg = AIChatMessage(user_id=me.id, role="assistant", content=answer)
    db.add(ai_msg)
    await db.commit()
    await db.refresh(ai_msg)

    return ChatResponse(
        id=str(ai_msg.id),
        role=ai_msg.role,
        content=ai_msg.content,
        created_at=ai_msg.created_at,
    )


@router.get("/history", response_model=List[ChatResponse])
async def get_history(
    limit: int = 50,
    db:    AsyncSession = Depends(get_db),
    me:    User         = Depends(get_current_user),
):
    r = await db.execute(
        select(AIChatMessage)
        .where(AIChatMessage.user_id == me.id)
        .order_by(AIChatMessage.created_at.asc())
        .limit(limit)
    )
    msgs = r.scalars().all()
    return [
        ChatResponse(id=str(m.id), role=m.role, content=m.content, created_at=m.created_at)
        for m in msgs
    ]
