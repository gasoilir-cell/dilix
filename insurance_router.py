"""
Dilix — Insurance Router (Cargo Insurance)
POST /api/v1/insurance/quote        محاسبه حق بیمه
POST /api/v1/insurance/requests     ثبت درخواست بیمه
GET  /api/v1/insurance/requests     لیست درخواست‌های من
GET  /api/v1/insurance/requests/{id} جزئیات
"""
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional, List
from enum import Enum as PyEnum

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, Enum, Float, ForeignKey, String, Text, BigInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db, Base
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/insurance", tags=["Insurance"])

# ── Inline model (avoid separate file for simplicity) ─────────
def _now():
    return datetime.now(timezone.utc)


class InsuranceRequest(Base):
    __tablename__ = "insurance_requests"

    id            = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    ref           = Column(String(20), unique=True, nullable=False)
    owner_id      = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    cargo_type    = Column(String(100), nullable=False)
    cargo_value   = Column(BigInteger, nullable=False)      # تومان
    origin        = Column(String(300), nullable=False)
    destination   = Column(String(300), nullable=False)
    coverage_type = Column(
        Enum("basic", "comprehensive", "all_risk", name="coverage_type_enum"),
        nullable=False, default="basic"
    )
    premium       = Column(BigInteger, nullable=False)       # تومان
    notes         = Column(Text, nullable=True)
    status        = Column(
        Enum("pending", "reviewed", "approved", "rejected", name="insurance_status_enum"),
        nullable=False, default="pending"
    )
    created_at    = Column(DateTime(timezone=True), nullable=False, default=_now)


# ── Rate table ──────────────────────────────────────────────────
CARGO_RATES = {
    "electronics":    0.0080,
    "perishables":    0.0065,
    "machinery":      0.0055,
    "textiles":       0.0040,
    "raw_materials":  0.0035,
    "chemicals":      0.0090,
    "artwork":        0.0100,
    "vehicles":       0.0060,
    "general":        0.0045,
}
COVERAGE_MULTIPLIER = {
    "basic":         1.0,
    "comprehensive": 1.55,
    "all_risk":      2.10,
}
CARGO_LABEL = {
    "electronics": "الکترونیک",    "perishables":   "مواد فاسدشدنی",
    "machinery":   "ماشین‌آلات",   "textiles":      "منسوجات و پارچه",
    "raw_materials":"مواد اولیه",  "chemicals":     "مواد شیمیایی",
    "artwork":     "آثار هنری",    "vehicles":      "خودرو",
    "general":     "عمومی",
}
COVERAGE_LABEL = {
    "basic":         "پایه (خسارت فیزیکی)",
    "comprehensive": "جامع (+ سرقت)",
    "all_risk":      "همه‌خطر (all risk)",
}


def calc_premium(cargo_type: str, cargo_value: int, coverage_type: str) -> int:
    base_rate = CARGO_RATES.get(cargo_type, 0.0045)
    mult      = COVERAGE_MULTIPLIER.get(coverage_type, 1.0)
    premium   = int(cargo_value * base_rate * mult)
    return max(premium, 50_000)   # حداقل ۵۰ هزار تومان


def gen_ref() -> str:
    return "INS-" + _uuid.uuid4().hex[:8].upper()


# ── Schemas ─────────────────────────────────────────────────────
class QuoteRequest(BaseModel):
    cargo_type:    str   = Field(..., description="نوع کالا")
    cargo_value:   int   = Field(..., gt=0, description="ارزش کالا (تومان)")
    coverage_type: str   = Field("basic", description="نوع پوشش")
    origin:        str   = Field(..., min_length=2)
    destination:   str   = Field(..., min_length=2)


class QuoteResponse(BaseModel):
    cargo_type:       str
    cargo_type_label: str
    cargo_value:      int
    coverage_type:    str
    coverage_label:   str
    base_rate_pct:    float
    premium:          int


class RequestCreate(BaseModel):
    cargo_type:    str
    cargo_value:   int   = Field(..., gt=0)
    coverage_type: str   = "basic"
    origin:        str   = Field(..., min_length=2)
    destination:   str   = Field(..., min_length=2)
    notes:         Optional[str] = None


class RequestOut(BaseModel):
    id:            str
    ref:           str
    cargo_type:    str
    cargo_value:   int
    origin:        str
    destination:   str
    coverage_type: str
    premium:       int
    notes:         Optional[str]
    status:        str
    created_at:    datetime

    class Config:
        from_attributes = True

    @classmethod
    def from_orm(cls, obj) -> "RequestOut":
        return cls(
            id=str(obj.id), ref=obj.ref,
            cargo_type=obj.cargo_type, cargo_value=obj.cargo_value,
            origin=obj.origin, destination=obj.destination,
            coverage_type=obj.coverage_type, premium=obj.premium,
            notes=obj.notes, status=obj.status, created_at=obj.created_at,
        )


# ── Endpoints ───────────────────────────────────────────────────

@router.post("/quote", response_model=QuoteResponse)
async def get_quote(body: QuoteRequest, me: User = Depends(get_current_user)):
    """محاسبه حق بیمه بدون ثبت درخواست"""
    if body.cargo_type not in CARGO_RATES:
        raise HTTPException(400, detail=f"نوع کالا معتبر نیست. گزینه‌ها: {list(CARGO_RATES)}")
    if body.coverage_type not in COVERAGE_MULTIPLIER:
        raise HTTPException(400, detail="نوع پوشش معتبر نیست")
    premium = calc_premium(body.cargo_type, body.cargo_value, body.coverage_type)
    return QuoteResponse(
        cargo_type       = body.cargo_type,
        cargo_type_label = CARGO_LABEL.get(body.cargo_type, body.cargo_type),
        cargo_value      = body.cargo_value,
        coverage_type    = body.coverage_type,
        coverage_label   = COVERAGE_LABEL.get(body.coverage_type, body.coverage_type),
        base_rate_pct    = round(CARGO_RATES[body.cargo_type] * 100, 3),
        premium          = premium,
    )


@router.post("/requests", response_model=RequestOut, status_code=201)
async def create_request(
    body:  RequestCreate,
    db:    AsyncSession = Depends(get_db),
    me:    User         = Depends(get_current_user),
):
    """ثبت رسمی درخواست بیمه"""
    if body.cargo_type not in CARGO_RATES:
        raise HTTPException(400, detail="نوع کالا معتبر نیست")
    premium = calc_premium(body.cargo_type, body.cargo_value, body.coverage_type)
    req = InsuranceRequest(
        ref           = gen_ref(),
        owner_id      = me.id,
        cargo_type    = body.cargo_type,
        cargo_value   = body.cargo_value,
        origin        = body.origin,
        destination   = body.destination,
        coverage_type = body.coverage_type,
        premium       = premium,
        notes         = body.notes,
        status        = "pending",
    )
    db.add(req)
    await db.commit()
    await db.refresh(req)
    return RequestOut.from_orm(req)


@router.get("/requests", response_model=List[RequestOut])
async def list_requests(
    db: AsyncSession = Depends(get_db),
    me: User         = Depends(get_current_user),
):
    r = await db.execute(
        select(InsuranceRequest)
        .where(InsuranceRequest.owner_id == me.id)
        .order_by(InsuranceRequest.created_at.desc())
        .limit(50)
    )
    return [RequestOut.from_orm(x) for x in r.scalars().all()]


@router.get("/requests/{req_id}", response_model=RequestOut)
async def get_request(
    req_id: str,
    db:     AsyncSession = Depends(get_db),
    me:     User         = Depends(get_current_user),
):
    req = await db.get(InsuranceRequest, _uuid.UUID(req_id))
    if not req:
        raise HTTPException(404, "درخواست پیدا نشد")
    if req.owner_id != me.id:
        raise HTTPException(403, "دسترسی ندارید")
    return RequestOut.from_orm(req)
