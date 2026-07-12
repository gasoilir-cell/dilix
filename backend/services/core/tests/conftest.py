"""پیکربندیِ مشترکِ pytest.

قبل از هر import از `app.*`، متغیرِ محیطیِ دیتابیس را روی SQLite درون‌حافظه‌ای
ست می‌کند تا `app.core.database` هنگامِ ساختِ engine به asyncpg/Postgres نیاز
نداشته باشد و `make core-test` بدونِ تنظیمِ دستیِ env سبز شود.
"""
from __future__ import annotations

import os

os.environ.setdefault("DILIX_DATABASE_URL", "sqlite+aiosqlite:///:memory:")
