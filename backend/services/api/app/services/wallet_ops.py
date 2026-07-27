"""
Dilix — عملیاتِ پایهٔ کیفِ پول (مشترک بینِ همهٔ جریان‌های پولی)

این منطق **یک نسخه بیشتر ندارد**. جابه‌جاییِ پول بینِ دو کیف قواعدِ ظریفی
دارد (قفلِ هم‌زمان، ترتیبِ قفل، ثبتِ دو تراکنش) که اگر در هر feature دوباره
نوشته شود، اصلاحِ یک باگ به بقیه نمی‌رسد.
"""
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.wallet import Wallet, WalletTransaction


async def get_or_create_wallet(db: AsyncSession, user_id) -> Wallet:
    """کیف‌پولِ کاربر را برمی‌گرداند و در نبودش با موجودی صفر می‌سازد."""
    w = (await db.execute(
        select(Wallet).where(Wallet.user_id == user_id)
    )).scalar_one_or_none()
    if w is None:
        w = Wallet(user_id=user_id, currency="IRR")
        db.add(w)
        await db.flush()
    return w


async def move_money(db: AsyncSession, from_id, to_id, amount: int,
                     out_desc: str, in_desc: str,
                     reference_id: str | None = None,
                     fee: int = 0, fee_desc: str | None = None) -> None:
    """جابه‌جاییِ اتمیکِ پول بینِ دو کیف‌پول + دو ردیفِ تراکنش (بدونِ commit).

    هر دو ردیف در **یک** کوئری و با ترتیبِ ثابتِ `id` قفل می‌شوند: بدونِ قفل، دو
    درخواستِ هم‌زمان هر دو همان موجودی را می‌خوانند و خرجِ دوباره ممکن می‌شود؛ و
    اگر جداگانه قفل شوند، دو انتقالِ متقابل به بن‌بست (deadlock) می‌خورند.

    `fee` کارمزدِ پلتفرم است: پرداخت‌کننده **کلِ** `amount` را می‌دهد و گیرنده
    `amount - fee` می‌گیرد. با همان معناشناسیِ `release_escrow` تا جریانِ
    مستقیم و جریانِ امانی دو تعریفِ متفاوت از کارمزد پیدا نکنند.
    """
    if fee < 0 or fee > amount:
        raise HTTPException(status_code=500, detail="کارمزدِ نامعتبر")
    await get_or_create_wallet(db, from_id)
    await get_or_create_wallet(db, to_id)

    locked = await db.execute(
        select(Wallet)
        .where(Wallet.user_id.in_([from_id, to_id]))
        .order_by(Wallet.id)
        .with_for_update()
    )
    wallets = {w.user_id: w for w in locked.scalars().all()}
    sw, rw = wallets[from_id], wallets[to_id]

    if sw.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")
    if rw.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پولِ مقصد مسدود است")
    if sw.balance_available < amount:
        raise HTTPException(status_code=400, detail="موجودی کافی نیست")

    before_out = sw.balance_available
    sw.balance_available -= amount
    db.add(WalletTransaction(
        wallet_id=sw.id, type="transfer_out", status="completed",
        amount=amount, balance_before=before_out, balance_after=sw.balance_available,
        reference_id=reference_id,
        description=out_desc,
    ))

    net = amount - fee
    before_in = rw.balance_available
    rw.balance_available += net
    db.add(WalletTransaction(
        wallet_id=rw.id, type="transfer_in", status="completed",
        amount=net, balance_before=before_in, balance_after=rw.balance_available,
        reference_id=reference_id,
        description=in_desc,
    ))
    if fee > 0:
        db.add(WalletTransaction(
            wallet_id=rw.id, type="fee", status="completed",
            amount=fee, balance_before=rw.balance_available,
            balance_after=rw.balance_available,
            reference_id=reference_id,
            description=fee_desc or "کارمزدِ پلتفرم",
        ))
    await db.flush()


async def _locked_wallet(db: AsyncSession, user_id) -> Wallet:
    """کیفِ کاربر را می‌سازد (در نبود) و سپس ردیفش را قفل می‌کند."""
    await get_or_create_wallet(db, user_id)
    return (await db.execute(
        select(Wallet).where(Wallet.user_id == user_id).with_for_update()
    )).scalar_one()


async def lock_escrow(db: AsyncSession, user_id, amount: int,
                      description: str, reference_id: str | None = None) -> None:
    """بلوکِ وجه: از `balance_available` کم و به `balance_escrow` اضافه می‌شود.

    پول در همان کیفِ خریدار می‌ماند اما دیگر خرج‌کردنی نیست. تا وقتی معامله
    تمام نشده، پول نه دستِ فروشنده است نه در دسترسِ خریدار — همین چیزی است که
    escrow را از یک انتقالِ ساده جدا می‌کند.
    """
    w = await _locked_wallet(db, user_id)
    if w.is_frozen:
        raise HTTPException(status_code=403, detail="کیف‌پول مسدود است")
    if w.balance_available < amount:
        raise HTTPException(status_code=400, detail="موجودی کافی نیست")

    before = w.balance_available
    w.balance_available -= amount
    w.balance_escrow = (w.balance_escrow or 0) + amount
    db.add(WalletTransaction(
        wallet_id=w.id, type="escrow_lock", status="completed",
        amount=amount, balance_before=before, balance_after=w.balance_available,
        reference_id=reference_id, description=description,
    ))
    await db.flush()


async def release_escrow(db: AsyncSession, from_id, to_id, amount: int,
                         out_desc: str, in_desc: str,
                         fee: int = 0, fee_desc: str | None = None,
                         reference_id: str | None = None) -> None:
    """آزادسازیِ وجهِ بلوکه به سودِ گیرنده، منهای کارمزدِ اختیاری.

    فراخوانِ این تابع باید **idempotent** نگه داشته شود؛ یعنی صداکننده باید
    پیش از آن وضعیتِ escrow را بررسی کند. اگر دوبار اجرا شود، پولِ بلوکه‌نشده
    آزاد می‌شود و از هیچ پول ساخته می‌شود.
    """
    if fee < 0 or fee > amount:
        raise HTTPException(status_code=500, detail="کارمزدِ نامعتبر")

    sw = await _locked_wallet(db, from_id)
    rw = await _locked_wallet(db, to_id)

    # کاهشِ escrow پرداخت‌کننده — موجودیِ در دسترسش تغییر نمی‌کند چون پول
    # هنگامِ بلوک از آن کم شده بود.
    sw.balance_escrow = max(0, (sw.balance_escrow or 0) - amount)
    db.add(WalletTransaction(
        wallet_id=sw.id, type="escrow_release", status="completed",
        amount=amount, balance_before=sw.balance_available,
        balance_after=sw.balance_available,
        reference_id=reference_id, description=out_desc,
    ))

    net = amount - fee
    before_in = rw.balance_available
    rw.balance_available = before_in + net
    db.add(WalletTransaction(
        wallet_id=rw.id, type="escrow_release", status="completed",
        amount=net, balance_before=before_in, balance_after=rw.balance_available,
        reference_id=reference_id, description=in_desc,
    ))
    if fee > 0:
        db.add(WalletTransaction(
            wallet_id=rw.id, type="fee", status="completed",
            amount=fee, balance_before=rw.balance_available,
            balance_after=rw.balance_available,
            reference_id=reference_id,
            description=fee_desc or "کارمزدِ پلتفرم",
        ))
    await db.flush()


async def spend_escrow(db: AsyncSession, user_id, amount: int,
                       description: str, reference_id: str | None = None) -> None:
    """مصرفِ بخشی از وجهِ بلوکه به سودِ پلتفرم (بدونِ گیرندهٔ کاربر).

    برای بودجه‌ای است که کاربر از پیش بلوکه کرده و به‌تدریج خرج می‌شود
    (تبلیغات). چون گیرنده کاربر نیست، تنها ردیفِ `fee` ثبت می‌شود و
    `balance_available` دست نمی‌خورد — پول هنگامِ بلوک از آن کم شده بود.

    مانندِ `release_escrow`، صداکننده باید سقف را **پیش از** فراخوانی تضمین
    کند؛ اینجا فقط `balance_escrow` را می‌کاهد و منفی نمی‌کند.
    """
    w = await _locked_wallet(db, user_id)
    w.balance_escrow = max(0, (w.balance_escrow or 0) - amount)
    db.add(WalletTransaction(
        wallet_id=w.id, type="fee", status="completed",
        amount=amount, balance_before=w.balance_available,
        balance_after=w.balance_available,
        reference_id=reference_id, description=description,
    ))
    await db.flush()


async def refund_escrow(db: AsyncSession, user_id, amount: int,
                        description: str, reference_id: str | None = None) -> None:
    """بازگشتِ وجهِ بلوکه به موجودیِ در دسترسِ همان کاربر. بدونِ کارمزد."""
    w = await _locked_wallet(db, user_id)
    before = w.balance_available
    w.balance_escrow = max(0, (w.balance_escrow or 0) - amount)
    w.balance_available = before + amount
    db.add(WalletTransaction(
        wallet_id=w.id, type="refund", status="completed",
        amount=amount, balance_before=before, balance_after=w.balance_available,
        reference_id=reference_id, description=description,
    ))
    await db.flush()
