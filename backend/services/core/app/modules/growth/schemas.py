"""اسکیماهای Growth."""
from __future__ import annotations

from pydantic import BaseModel


class ReferralLinkOut(BaseModel):
    code: str
    url: str
    total_referred: int


class RewardBalance(BaseModel):
    currency: str
    amount_minor: int
    reward_count: int


class RewardWalletOut(BaseModel):
    """کیفِ پاداش — فقط پاداش‌هایِ gated به یک reward_event واقعی."""

    balances: list[RewardBalance]
    pending_count: int


class RevenueShareOut(BaseModel):
    """سهمِ عضو از درآمدِ کارمزدِ پلتفرم (Vanguard-style)."""

    eligible: bool
    plan: str
    entitlement_bps: int  # نرخِ سهم برحسبِ basis points
    investment_units: float
    note: str
