"""Payment API endpoints — initiate & verify."""

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.api.deps import get_current_user
from app.models.user import User
from app.providers.payment.router import get_payment_router
from app.providers.payment.base import PaymentRequest
from app.core.config import settings

router = APIRouter(prefix="/payment", tags=["payment"])


class InitiateRequest(BaseModel):
    amount: int       # in smallest unit (Rial or cents)
    currency: str = "IRR"
    description: str = "شارژ کیف پول"


class InitiateResponse(BaseModel):
    success: bool
    payment_url: str | None = None
    authority: str | None = None
    error: str | None = None


class VerifyRequest(BaseModel):
    authority: str
    amount: int
    currency: str = "IRR"


@router.post("/initiate", response_model=InitiateResponse)
async def initiate_payment(
    body: InitiateRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
):
    router_ = get_payment_router()
    callback_url = f"{settings.APP_URL}/api/v1/payment/callback"

    result = await router_.initiate(
        PaymentRequest(
            amount=body.amount,
            currency=body.currency,
            description=body.description,
            user_id=str(current_user.id),
            callback_url=callback_url,
            metadata={"user_earth_id": current_user.earth_id},
        )
    )
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error)

    return InitiateResponse(
        success=True,
        payment_url=result.payment_url,
        authority=result.authority,
    )


@router.post("/verify")
async def verify_payment(
    body: VerifyRequest,
    current_user: User = Depends(get_current_user),
):
    router_ = get_payment_router()
    result = await router_.verify(body.authority, body.amount)
    if not result.success:
        raise HTTPException(status_code=400, detail=result.error or "Payment verification failed")
    return {"success": True, "ref_id": result.ref_id, "provider": result.provider}


@router.get("/callback")
async def payment_callback(status: str = "success", Authority: str = "", session_id: str = ""):
    """Redirect target after payment gateway — frontend handles the rest."""
    return {"status": status, "authority": Authority or session_id}
