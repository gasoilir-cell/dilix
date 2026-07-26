import httpx
import structlog
from app.providers.payment.base import PaymentProvider, PaymentRequest, PaymentResult, PaymentStatus
from app.core.config import settings

log = structlog.get_logger()

IRAN_CURRENCIES = {"IRR", "IRT"}  # IRT = Toman (IRR / 10)


class ZarinpalProvider(PaymentProvider):
    """ZarinPal — Iranian payment gateway (Shaparak)."""

    BASE_URL = "https://api.zarinpal.com/pg/v4/payment"
    SANDBOX_URL = "https://sandbox.zarinpal.com/pg/v4/payment"
    PAYMENT_URL = "https://www.zarinpal.com/pg/StartPay"

    def supports_currency(self, currency: str) -> bool:
        return currency in IRAN_CURRENCIES

    def _base(self) -> str:
        return self.SANDBOX_URL if settings.is_development else self.BASE_URL

    async def initiate(self, request: PaymentRequest) -> PaymentResult:
        amount = request.amount  # Must be in Rial
        if request.currency == "IRT":
            amount = amount * 10  # Convert Toman → Rial

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(
                    f"{self._base()}/request.json",
                    json={
                        "merchant_id": settings.ZARINPAL_MERCHANT_ID,
                        "amount": amount,
                        "description": request.description,
                        "callback_url": request.callback_url,
                        "metadata": {"mobile": request.user_id},
                    },
                )
                data = resp.json().get("data", {})
                code = data.get("code")
                if code == 100:
                    authority = data["authority"]
                    return PaymentResult(
                        success=True,
                        status=PaymentStatus.PENDING,
                        payment_url=f"{self.PAYMENT_URL}/{authority}",
                        authority=authority,
                        provider="zarinpal",
                    )
                return PaymentResult(
                    success=False,
                    status=PaymentStatus.FAILED,
                    error=f"ZarinPal error code: {code}",
                    provider="zarinpal",
                )
        except Exception as exc:
            log.error("payment.zarinpal_initiate_error", error=str(exc))
            return PaymentResult(success=False, status=PaymentStatus.FAILED, error=str(exc), provider="zarinpal")

    async def verify(self, authority: str, amount: int) -> PaymentResult:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(
                    f"{self._base()}/verify.json",
                    json={
                        "merchant_id": settings.ZARINPAL_MERCHANT_ID,
                        "amount": amount,
                        "authority": authority,
                    },
                )
                data = resp.json().get("data", {})
                code = data.get("code")
                if code in (100, 101):
                    return PaymentResult(
                        success=True,
                        status=PaymentStatus.SUCCESS,
                        ref_id=str(data.get("ref_id")),
                        authority=authority,
                        provider="zarinpal",
                    )
                return PaymentResult(
                    success=False,
                    status=PaymentStatus.FAILED,
                    error=f"Verify error code: {code}",
                    provider="zarinpal",
                )
        except Exception as exc:
            log.error("payment.zarinpal_verify_error", error=str(exc))
            return PaymentResult(success=False, status=PaymentStatus.FAILED, error=str(exc), provider="zarinpal")
