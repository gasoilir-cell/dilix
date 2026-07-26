"""Payment router — selects the right provider by currency."""

import structlog
from app.providers.payment.base import PaymentProvider, PaymentRequest, PaymentResult, PaymentStatus
from app.providers.payment.zarinpal import ZarinpalProvider
from app.providers.payment.stripe import StripeProvider

log = structlog.get_logger()


class PaymentRouter(PaymentProvider):
    def __init__(self) -> None:
        self._providers: list[PaymentProvider] = [
            ZarinpalProvider(),
            StripeProvider(),
        ]

    def supports_currency(self, currency: str) -> bool:
        return True

    async def initiate(self, request: PaymentRequest) -> PaymentResult:
        provider = self._select(request.currency)
        if provider is None:
            return PaymentResult(
                success=False,
                status=PaymentStatus.FAILED,
                error=f"No payment provider for currency: {request.currency}",
            )
        result = await provider.initiate(request)
        log.info("payment.initiated", currency=request.currency, provider=result.provider, success=result.success)
        return result

    async def verify(self, authority: str, amount: int) -> PaymentResult:
        # Try all providers; the correct one will succeed
        for provider in self._providers:
            result = await provider.verify(authority, amount)
            if result.success:
                return result
        return PaymentResult(success=False, status=PaymentStatus.FAILED, error="Verification failed on all providers")

    def _select(self, currency: str) -> PaymentProvider | None:
        for p in self._providers:
            if p.supports_currency(currency):
                return p
        return None


_router: PaymentRouter | None = None


def get_payment_router() -> PaymentRouter:
    global _router
    if _router is None:
        _router = PaymentRouter()
    return _router
