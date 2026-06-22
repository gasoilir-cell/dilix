"""Entrypointِ workerِ Outbox Relay — جدا از API اجرا می‌شود (ADR-03/سند ۴).

اجرا: `python -m app.worker`  (یا هدفِ Makefile: `make core-relay`).
این فرایند ردیف‌های pending جدولِ outbox را به NATS JetStream می‌فرستد.
"""
from __future__ import annotations

import asyncio
import logging

from app.core.relay import run_relay

logging.basicConfig(level=logging.INFO)


def main() -> None:
    asyncio.run(run_relay())


if __name__ == "__main__":
    main()
