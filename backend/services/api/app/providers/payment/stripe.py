import httpx
import structlog
from app.providers.payment.base import PaymentProvider, PaymentRequest, PaymentResult, PaymentStatus
from app.core.config import settings

log = structlog.get_logger()

INTERNATIONAL_CURRENCIES = {"USD", "EUR", "GBP", "AED", "TRY"}


class StripeProvider(PaymentProvider):
    """Stripe — for international payments via UAE entity."""

    BASE_URL = "https://api.stripe.com/v1"

    def supports_currency(self, currency: str) -> bool:
        return currency in INTERNATIONAL_CURRENCIES

    async def initiate(self, request: PaymentRequest) -> PaymentResult:
        if not settings.STRIPE_SECRET_KEY:
            return PaymentResult(
                success=True,
                status=PaymentStatus.PENDING,
                payment_url="https://checkout.stripe.com/dev",
                authority="dev_session",
                provider="stripe_dev",
            )

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(
                    f"{self.BASE_URL}/checkout/sessions",
                    auth=(settings.STRIPE_SECRET_KEY, ""),
                    data={
                        "payment_method_types[]": "card",
                        "line_items[0][price_data][currency]": request.currency.lower(),
                        "line_items[0][price_data][product_data][name]": request.description,
                        "line_items[0][price_data][unit_amount]": str(request.amount),
                        "line_items[0][quantity]": "1",
                        "mode": "payment",
                        "success_url": request.callback_url + "?status=success&session_id={CHECKOUT_SESSION_ID}",
                        "cancel_url": request.callback_url + "?status=cancel",
                        "metadata[user_id]": request.user_id,
                    },
                )
                session = resp.json()
                if resp.status_code == 200:
                    return PaymentResult(
                        success=True,
                        status=PaymentStatus.PENDING,
                        payment_url=session["url"],
                        authority=session["id"],
                        provider="stripe",
                    )
                return PaymentResult(
                    success=False,
                    status=PaymentStatus.FAILED,
                    error=session.get("error", {}).get("message"),
                    provider="stripe",
                )
        except Exception as exc:
            log.error("payment.stripe_initiate_error", error=str(exc))
            return PaymentResult(success=False, status=PaymentStatus.FAILED, error=str(exc), provider="stripe")

    async def verify(self, authority: str, amount: int) -> PaymentResult:
        """For Stripe, verification is done via webhook; this retrieves session status."""
        if not settings.STRIPE_SECRET_KEY:
            return PaymentResult(success=True, status=PaymentStatus.SUCCESS, ref_id="dev_pi", provider="stripe_dev")

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(
                    f"{self.BASE_URL}/checkout/sessions/{authority}",
                    auth=(settings.STRIPE_SECRET_KEY, ""),
                )
                session = resp.json()
                if session.get("payment_status") == "paid":
                    return PaymentResult(
                        success=True,
                        status=PaymentStatus.SUCCESS,
                        ref_id=session.get("payment_intent"),
                        authority=authority,
                        provider="stripe",
                    )
                return PaymentResult(success=False, status=PaymentStatus.FAILED, error="Payment not completed", provider="stripe")
        except Exception as exc:
            log.error("payment.stripe_verify_error", error=str(exc))
            return PaymentResult(success=False, status=PaymentStatus.FAILED, error=str(exc), provider="stripe")
