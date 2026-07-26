"""Wallet API endpoints."""

import io as _io
import re as _re
from urllib.parse import parse_qs, quote, urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction

router = APIRouter(prefix="/wallet", tags=["wallet"])


class WalletResponse(BaseModel):
    id: str
    currency: str
    balance_available: int
    balance_escrow: int
    balance_bonus: int
    is_frozen: bool


class TransactionResponse(BaseModel):
    id: str
    type: str
    status: str
    amount: int
    balance_before: int
    balance_after: int
    description: str | None
    created_at: str


class TransferRequest(BaseModel):
    to_earth_id: str
    amount: int = Field(..., gt=0, description="مبلغ به ریال")
    description: str = ""


async def _get_or_create_wallet(db: AsyncSession, user: User) -> Wallet:
    """کیف پول کاربر را برمی‌گرداند و اگر وجود نداشته باشد می‌سازد.

    برخی حساب‌ها (مثلاً ثبت‌نام با OTP/OAuth یا حساب‌های قدیمی) ممکن است بدون
    کیف پول ساخته شده باشند؛ این‌جا به‌صورت lazy با موجودی صفر ایجاد می‌شود.
    """
    result = await db.execute(select(Wallet).where(Wallet.user_id == user.id))
    wallet = result.scalar_one_or_none()
    if wallet is None:
        wallet = Wallet(user_id=user.id, currency="IRR")
        db.add(wallet)
        await db.commit()
        await db.refresh(wallet)
    return wallet


@router.get("", response_model=WalletResponse, include_in_schema=False)
@router.get("/", response_model=WalletResponse)
async def get_wallet(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    wallet = await _get_or_create_wallet(db, current_user)
    return WalletResponse(
        id=str(wallet.id),
        currency=wallet.currency,
        balance_available=wallet.balance_available,
        balance_escrow=wallet.balance_escrow,
        balance_bonus=wallet.balance_bonus,
        is_frozen=wallet.is_frozen,
    )


@router.get("/transactions", response_model=list[TransactionResponse])
async def get_transactions(
    page: int = 1,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    wallet = await _get_or_create_wallet(db, current_user)

    offset = (page - 1) * limit
    tx_result = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.wallet_id == wallet.id)
        .order_by(WalletTransaction.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    txs = tx_result.scalars().all()
    return [
        TransactionResponse(
            id=str(tx.id),
            type=tx.type,
            status=tx.status,
            amount=tx.amount,
            balance_before=tx.balance_before,
            balance_after=tx.balance_after,
            description=tx.description,
            created_at=tx.created_at.isoformat(),
        )
        for tx in txs
    ]


# ─── پرداختِ QR ───────────────────────────────────────────────────────────────
# قالبِ بار: یک URLِ https معمولی، نه اسکیمای اختصاصی. با این کار دوربینِ خودِ
# گوشی و هر اسکنرِ عمومی هم آن را می‌خواند و به وب می‌بَرد؛ اسکیمای `dilix://`
# بیرون از اپ فقط یک متنِ بی‌معنا می‌شد.
PAY_URL_BASE = "https://dilix.ir/pay"
ALLOWED_QR_HOSTS = {"dilix.ir", "www.dilix.ir"}
_EARTH_ID_RE = _re.compile(r"^DLX-[A-Z0-9]{4,16}$")
_MAX_NOTE = 60


class QRPayload(BaseModel):
    payload: str = Field(..., max_length=512)


class QRResolved(BaseModel):
    earth_id: str
    display_name: str
    avatar_url: str | None
    amount: int | None = Field(None, description="مبلغ به ریال، اگر در QR آمده باشد")
    note: str | None
    is_self: bool


def _build_payload(earth_id: str, amount: int | None, note: str | None) -> str:
    url = f"{PAY_URL_BASE}/{earth_id}"
    params = []
    if amount:
        params.append(f"a={amount}")
    if note:
        params.append(f"n={quote(note[:_MAX_NOTE])}")
    return f"{url}?{'&'.join(params)}" if params else url


def _parse_payload(payload: str) -> tuple[str, int | None, str | None]:
    """از بارِ اسکن‌شده «شناسه‌ی مقصد، مبلغ، یادداشت» را درمی‌آورد.

    سه شکل پذیرفته می‌شود: لینکِ پرداخت، لینکِ پروفایل (`/u/DLX-…` — کاربر ممکن
    است QRِ پروفایل را برای پرداخت اسکن کند و بن‌بست‌دادن به او بی‌دلیل است)، و
    خودِ شناسه‌ی خام.
    """
    raw = payload.strip()
    earth_id, amount, note = "", None, None

    if raw.upper().startswith("DLX-"):
        earth_id = raw.upper()
    else:
        parsed = urlparse(raw)
        if parsed.scheme not in ("http", "https"):
            raise HTTPException(status_code=400, detail="کد QR معتبر نیست")
        # بدونِ بررسیِ دامنه، یک QR از سایتِ فیشینگ با مسیرِ `/pay/DLX-…` هم
        # پذیرفته می‌شد و کاربر خیال می‌کرد کدِ دیلیکس را اسکن کرده است.
        if parsed.hostname not in ALLOWED_QR_HOSTS:
            raise HTTPException(status_code=400, detail="این کد QR مربوط به دیلیکس نیست")
        segments = [s for s in parsed.path.split("/") if s]
        if len(segments) < 2 or segments[0] not in ("pay", "u"):
            raise HTTPException(status_code=400, detail="این کد QR مربوط به دیلیکس نیست")
        earth_id = segments[1].upper()
        query = parse_qs(parsed.query)
        raw_amount = (query.get("a") or [""])[0]
        if raw_amount:
            if not raw_amount.isdigit() or int(raw_amount) <= 0:
                raise HTTPException(status_code=400, detail="مبلغِ داخلِ کد QR معتبر نیست")
            amount = int(raw_amount)
        note = ((query.get("n") or [""])[0] or None)
        if note:
            note = note[:_MAX_NOTE]

    if not _EARTH_ID_RE.match(earth_id):
        raise HTTPException(status_code=400, detail="شناسه‌ی داخلِ کد QR معتبر نیست")
    return earth_id, amount, note


@router.get("/qr/payload", response_model=dict)
async def my_qr_payload(
    amount: int | None = Query(None, gt=0, description="مبلغ به ریال (اختیاری)"),
    note: str | None = Query(None, max_length=_MAX_NOTE),
    current_user: User = Depends(get_current_user),
):
    """متنِ کدِ QRِ دریافتِ من — برای اشتراک‌گذاری یا رندرِ سمتِ کلاینت."""
    return {"payload": _build_payload(current_user.earth_id, amount, note)}


@router.get("/qr")
async def my_qr_svg(
    amount: int | None = Query(None, gt=0, description="مبلغ به ریال (اختیاری)"),
    note: str | None = Query(None, max_length=_MAX_NOTE),
    current_user: User = Depends(get_current_user),
):
    """SVGِ کدِ QRِ «به من پرداخت کن»."""
    import segno

    buf = _io.BytesIO()
    segno.make(_build_payload(current_user.earth_id, amount, note), error="m").save(
        buf, kind="svg", scale=7, border=3, dark="#0A0A0A", light="#FFFFFF"
    )
    return Response(
        content=buf.getvalue(),
        media_type="image/svg+xml",
        # مبلغ/یادداشت داخلِ کد است، پس کشِ عمومی می‌تواند QRِ یک کاربر را به
        # دیگری بدهد. no-store.
        headers={"Cache-Control": "no-store"},
    )


@router.post("/qr/resolve", response_model=QRResolved)
async def resolve_qr(
    body: QRPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """پیش از کسرِ پول، مقصد را به کاربر نشان می‌دهد.

    پرداختِ کورکورانه پس از اسکن، کلاسیک‌ترین راهِ کلاهبرداریِ QR است (برچسبِ
    جعلی روی QRِ فروشنده). این‌جا نام و آواتارِ گیرنده برمی‌گردد تا کاربر پیش از
    تأیید ببیند پول به چه کسی می‌رود.
    """
    earth_id, amount, note = _parse_payload(body.payload)
    result = await db.execute(select(User).where(User.earth_id == earth_id))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="کاربرِ این کد QR یافت نشد")
    return QRResolved(
        earth_id=target.earth_id,
        display_name=target.full_name or target.username or target.earth_id,
        avatar_url=target.avatar_url,
        amount=amount,
        note=note,
        is_self=target.id == current_user.id,
    )


@router.post("/transfer", response_model=dict)
async def transfer(
    body: TransferRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """انتقال موجودی به کاربر دیگر با Earth ID."""
    rec_result = await db.execute(select(User).where(User.earth_id == body.to_earth_id))
    recipient = rec_result.scalar_one_or_none()
    if not recipient:
        raise HTTPException(status_code=404, detail="کاربر مقصد یافت نشد")
    if recipient.id == current_user.id:
        raise HTTPException(status_code=400, detail="نمی‌توانید به خودتان انتقال دهید")

    # حساب‌های ساخته‌شده با OTP/OAuth ممکن است هنوز ردیفِ کیف‌پول نداشته باشند؛
    # پیش از این هم فرستنده و هم گیرنده در آن حالت «کیف پول یافت نشد» می‌گرفتند.
    # ساختِ احتمالی باید *پیش از* هر تغییرِ موجودی انجام شود، چون کامیت می‌کند.
    await _get_or_create_wallet(db, current_user)
    await _get_or_create_wallet(db, recipient)

    # هر دو ردیف در یک کوئری و با ترتیبِ ثابتِ id قفل می‌شوند: بدونِ قفل، دو
    # درخواستِ هم‌زمان هر دو موجودی را می‌خواندند و خرجِ دوباره ممکن می‌شد؛ و
    # اگر جداگانه قفل می‌کردیم، دو انتقالِ متقابل به بن‌بست (deadlock) می‌خوردند.
    locked = await db.execute(
        select(Wallet)
        .where(Wallet.user_id.in_([current_user.id, recipient.id]))
        .order_by(Wallet.id)
        .with_for_update()
    )
    wallets = {w.user_id: w for w in locked.scalars().all()}
    sender_wallet = wallets[current_user.id]
    recipient_wallet = wallets[recipient.id]

    if sender_wallet.is_frozen:
        raise HTTPException(status_code=403, detail="کیف پول مسدود است")
    if recipient_wallet.is_frozen:
        raise HTTPException(status_code=403, detail="کیف پولِ مقصد مسدود است")
    if sender_wallet.balance_available < body.amount:
        raise HTTPException(status_code=400, detail="موجودی کافی نیست")

    before_sender = sender_wallet.balance_available
    sender_wallet.balance_available -= body.amount
    db.add(WalletTransaction(
        wallet_id=sender_wallet.id,
        type="transfer_out",
        status="completed",
        amount=body.amount,
        balance_before=before_sender,
        balance_after=sender_wallet.balance_available,
        description=body.description or f"انتقال به {body.to_earth_id}",
    ))

    before_recipient = recipient_wallet.balance_available
    recipient_wallet.balance_available += body.amount
    db.add(WalletTransaction(
        wallet_id=recipient_wallet.id,
        type="transfer_in",
        status="completed",
        amount=body.amount,
        balance_before=before_recipient,
        balance_after=recipient_wallet.balance_available,
        description=f"دریافت از {current_user.earth_id}",
    ))

    await db.commit()
    return {"success": True, "amount": body.amount, "to": body.to_earth_id}
