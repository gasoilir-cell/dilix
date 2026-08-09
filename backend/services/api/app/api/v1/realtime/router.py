"""
Dilix — Realtime (WebSocket)

جایگزینِ pollِ ۱.۵ثانیه‌ایِ `/calls/poll`. هدف ظرفیت است: در حالتِ poll هر کاربرِ
لاگین‌کرده — حتی بی‌کار — دائماً ~۰.۶۷ req/s به سرور می‌زند و ~۹۹٪ پاسخ‌ها خالی‌اند.
با یک اتصالِ باز، کاربرِ بی‌کار عملاً صفر درخواست می‌زند.

    GET /api/v1/ws?token=<access_token>     (WebSocket)

## چرا pub/sub فقط «زنگِ بیدارباش» است و خودِ داده را نمی‌برد
سرویس با چند workerِ uvicorn اجرا می‌شود، پس فرستنده و گیرنده معمولاً روی دو
پروسهٔ متفاوت‌اند. اگر payload از راهِ pub/sub می‌رفت، همان سیگنال هم در صفِ Redis
می‌مانْد و در reconnect دوباره تحویل می‌شد (offer/ICEِ تکراری = تماسِ خراب).
پس منبعِ حقیقت همان صفِ `calls:q:{earth}` می‌مانَد و pub/sub فقط می‌گوید
«چیزی برایت آمد، صف را خالی کن». درِین اتمی است (LRANGE+DELETE) ⇒ تحویلِ حداکثر
یک‌بار، دقیقاً مثلِ poll.

## چرا drainِ دوره‌ای هم هست
pub/sub در Redis تحویلِ تضمین‌شده ندارد (اگر لحظهٔ publish مشترکی نباشد پیام گم
می‌شود). گم‌شدنِ یک offer یعنی تماسِ بی‌جواب، پس یک درِینِ آرام هر SAFETY_DRAIN
ثانیه به‌عنوان تورِ ایمنی می‌مانَد — هزینه‌اش در مقایسه با poll ناچیز است
(هر ۱۰ ثانیه به‌جای هر ۱.۵ ثانیه) و تضمین می‌کند هیچ سیگنالی برای همیشه نمی‌مانَد.
"""
import asyncio
import contextlib
import json

import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from jose import JWTError
from sqlalchemy import select

from app.api.v1.calls.router import EV_PREFIX, Q_PREFIX, SEEN_PREFIX, SEEN_TTL
from app.core.database import AsyncSessionLocal
from app.core.redis import get_redis
from app.core.security import decode_token
from app.models.user import User

log = structlog.get_logger(__name__)

router = APIRouter(tags=["Realtime"])

HEARTBEAT = 5      # ثانیه — تازه‌کردنِ کلیدِ حضور (باید محکم زیرِ SEEN_TTL باشد)
SAFETY_DRAIN = 10  # ثانیه — تورِ ایمنی برای پیامِ گم‌شدهٔ pub/sub
CLOSE_UNAUTHORIZED = 4001


class _Hub:
    """
    یک اتصالِ pub/subِ مشترک برای کلِ پروسه، به‌جای یکی به‌ازای هر نشست.

    چرا: نسخهٔ اول برای هر WebSocket یک `r.pubsub()` جدا می‌ساخت. هر pubsub یک
    اتصالِ اختصاصیِ Redis می‌گیرد و آن را تا پایانِ نشست نگه می‌دارد، پس سقفِ
    کاربرِ هم‌زمان به اندازهٔ استخرِ Redis می‌چسبید و در بارِ ۳۰۰ اتصال دقیقاً همین
    شد: `MaxConnectionsError` ⇒ taskِ wakeup خطا می‌داد ⇒ کلِ نشست بسته می‌شد.
    این یعنی مهاجرت به WebSocket به‌جای بالابردنِ ظرفیت، سقفِ تازه‌ای می‌ساخت.

    حالا هر پروسه یک اتصال دارد و پخشِ داخلی با Event انجام می‌شود؛ اشتراکِ هر
    کانال شمارشِ مرجع دارد تا با رفتنِ آخرین نشست، unsubscribe شود.
    """

    def __init__(self) -> None:
        self._pubsub = None
        self._reader: asyncio.Task | None = None
        self._waiters: dict[str, set[asyncio.Event]] = {}
        self._lock = asyncio.Lock()

    async def register(self, earth_id: str, ev: asyncio.Event) -> None:
        async with self._lock:
            if self._pubsub is None:
                r = await get_redis()
                self._pubsub = r.pubsub()
            first = earth_id not in self._waiters
            self._waiters.setdefault(earth_id, set()).add(ev)
            if first:
                await self._pubsub.subscribe(EV_PREFIX + earth_id)
            # خواننده فقط بعد از وجودِ حداقل یک اشتراک معنا دارد.
            if self._reader is None or self._reader.done():
                self._reader = asyncio.create_task(self._read_loop())

    async def unregister(self, earth_id: str, ev: asyncio.Event) -> None:
        async with self._lock:
            waiters = self._waiters.get(earth_id)
            if waiters is None:
                return
            waiters.discard(ev)
            if waiters:
                return
            del self._waiters[earth_id]
            with contextlib.suppress(Exception):
                await self._pubsub.unsubscribe(EV_PREFIX + earth_id)

    async def _read_loop(self) -> None:
        """تنها مصرف‌کنندهٔ اتصالِ pub/sub؛ زنگ را به نشست‌های محلی پخش می‌کند."""
        while True:
            try:
                msg = await self._pubsub.get_message(
                    ignore_subscribe_messages=True, timeout=1.0
                )
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001
                # قطعِ موقتِ Redis نباید خواننده را برای همیشه بکشد؛ تورِ ایمنیِ
                # درِینِ دوره‌ای در این فاصله سیگنال‌ها را می‌رسانَد.
                log.warning("realtime_hub_read_error", exc_info=True)
                await asyncio.sleep(1)
                continue
            if not msg:
                continue
            channel = msg.get("channel")
            if isinstance(channel, bytes):
                channel = channel.decode()
            if not channel or not channel.startswith(EV_PREFIX):
                continue
            for waiter in tuple(self._waiters.get(channel[len(EV_PREFIX):], ())):
                waiter.set()


_hub = _Hub()


async def _resolve_user(token: str) -> User | None:
    """توکنِ access را به کاربر تبدیل می‌کند. هر خطایی ⇒ None (بدونِ نشتِ جزئیات)."""
    try:
        payload = decode_token(token)
    except JWTError:
        return None
    if payload.get("type") != "access":
        return None
    user_id = payload.get("sub")
    if not user_id:
        return None
    async with AsyncSessionLocal() as db:
        user = (
            await db.execute(select(User).where(User.id == user_id))
        ).scalar_one_or_none()
    if user is None or not user.is_active:
        return None
    return user


async def _drain(r, earth_id: str) -> list[dict]:
    """خالی‌کردنِ اتمیِ صفِ سیگنال — همان قراردادِ `/calls/poll`."""
    key = Q_PREFIX + earth_id
    items = await r.lrange(key, 0, -1)
    if not items:
        return []
    await r.delete(key)
    out: list[dict] = []
    for it in reversed(items):  # lpush ⇒ جدیدترین اول؛ برعکس تا ترتیبِ زمانی شود
        try:
            out.append(json.loads(it))
        except (ValueError, TypeError):
            pass
    return out


@router.websocket("/ws")
async def realtime_ws(websocket: WebSocket):
    token = websocket.query_params.get("token") or ""
    user = await _resolve_user(token)
    if user is None:
        # پیش از accept فقط می‌شود اتصال را رد کرد؛ کدِ اپلیکیشنی بعد از accept معنا دارد.
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return

    await websocket.accept()
    earth_id = user.earth_id
    r = await get_redis()
    send_lock = asyncio.Lock()

    async def push_signals(signals: list[dict]) -> None:
        if not signals:
            return
        async with send_lock:
            await websocket.send_text(json.dumps({"type": "signals", "signals": signals}))

    async def touch_presence() -> None:
        await r.set(SEEN_PREFIX + earth_id, "1", ex=SEEN_TTL)

    await touch_presence()
    # صفِ جامانده از قطعیِ قبلی نباید گم شود.
    await push_signals(await _drain(r, earth_id))
    async with send_lock:
        await websocket.send_text(json.dumps({"type": "ready", "earth_id": earth_id}))

    wake = asyncio.Event()
    await _hub.register(earth_id, wake)

    async def wakeup_loop() -> None:
        """زنگِ بیدارباشِ pub/sub ⇒ درِینِ فوری (مسیرِ کم‌تأخیر)."""
        while True:
            await wake.wait()
            wake.clear()
            await push_signals(await _drain(r, earth_id))

    async def keepalive_loop() -> None:
        """حضور + تورِ ایمنیِ درِین."""
        ticks = 0
        while True:
            await asyncio.sleep(HEARTBEAT)
            ticks += 1
            await touch_presence()
            if ticks * HEARTBEAT >= SAFETY_DRAIN:
                ticks = 0
                await push_signals(await _drain(r, earth_id))

    async def recv_loop() -> None:
        """قطعِ اتصال را تشخیص می‌دهد؛ `ping`ِ کلاینت را هم پاسخ می‌دهد."""
        while True:
            raw = await websocket.receive_text()
            if raw == "ping":
                async with send_lock:
                    await websocket.send_text("pong")

    tasks = [
        asyncio.create_task(wakeup_loop()),
        asyncio.create_task(keepalive_loop()),
        asyncio.create_task(recv_loop()),
    ]
    try:
        # اولین taskی که تمام شود (قطعِ اتصال یا خطا) کلِ نشست را می‌بندد.
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except WebSocketDisconnect:
        pass
    except Exception:  # noqa: BLE001
        log.warning("realtime_ws_error", earth_id=earth_id, exc_info=True)
    finally:
        for t in tasks:
            t.cancel()
        for t in tasks:
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await t
        with contextlib.suppress(Exception):
            await _hub.unregister(earth_id, wake)
        with contextlib.suppress(Exception):
            await websocket.close()
