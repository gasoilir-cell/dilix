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
                     reference_id: str | None = None) -> None:
    """جابه‌جاییِ اتمیکِ پول بینِ دو کیف‌پول + دو ردیفِ تراکنش (بدونِ commit).

    هر دو ردیف در **یک** کوئری و با ترتیبِ ثابتِ `id` قفل می‌شوند: بدونِ قفل، دو
    درخواستِ هم‌زمان هر دو همان موجودی را می‌خوانند و خرجِ دوباره ممکن می‌شود؛ و
    اگر جداگانه قفل شوند، دو انتقالِ متقابل به بن‌بست (deadlock) می‌خورند.
    """
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

    before_in = rw.balance_available
    rw.balance_available += amount
    db.add(WalletTransaction(
        wallet_id=rw.id, type="transfer_in", status="completed",
        amount=amount, balance_before=before_in, balance_after=rw.balance_available,
        reference_id=reference_id,
        description=in_desc,
    ))
    await db.flush()
