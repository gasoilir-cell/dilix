"""تستِ یکپارچهٔ HTTP برای reputation (نظر + امتیاز). schema: reputation."""
from __future__ import annotations

import uuid

import pytest_asyncio

from tests._harness import assert_auth_required, build_module_client

_SCHEMAS = ("reputation",)
_MODELS = ("app.modules.reputation.models",)


@pytest_asyncio.fixture
async def rep_client():
    async with build_module_client(_SCHEMAS, _MODELS) as cs:
        yield cs


async def test_submit_review_then_read(rep_client) -> None:
    client, _ = rep_client
    reviewee = str(uuid.uuid4())
    res = await client.post(
        "/v1/reputation/reviews",
        json={
            "reviewee_earth_id": reviewee,
            "domain": "marketplace",
            "transaction_ref": "tx-1",
            "rating": 5,
            "comment": "عالی بود",
        },
    )
    assert res.status_code == 201, res.text
    assert res.json()["rating"] == 5

    reviews = await client.get(f"/v1/reputation/reviews/{reviewee}")
    assert reviews.status_code == 200, reviews.text
    assert len(reviews.json()) == 1

    scores = await client.get(f"/v1/reputation/scores/{reviewee}")
    assert scores.status_code == 200, scores.text
    assert any(s["domain"] == "marketplace" for s in scores.json())


async def test_reputation_auth_required() -> None:
    await assert_auth_required("POST", "/v1/reputation/reviews")
