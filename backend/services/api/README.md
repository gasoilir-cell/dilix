# dilix-api — سرویسِ زنده‌ی production

**این سرویسی است که اپِ موبایل و وب امروز واقعاً به آن وصل‌اند.**
`AppConfig.apiBaseUrl` در اپِ Flutter و کلاینتِ Next.js هر دو به
`http://185.55.226.250:8000` با پیشوندِ `/api/v1` می‌روند.

سرویسِ دیگر — [`../core`](../core) — پیاده‌سازیِ Modular Monolithِ معماریِ هدف
روی پورت ۸۰۱۰ با پیشوندِ `/v1` است و مقصدِ مهاجرت. تا وقتی مهاجرت کامل نشده،
**هر تغییری که به کاربرِ واقعی می‌رسد باید اینجا هم اعمال شود.**

## چرا این پوشه تازه است

تا امروز سورسِ این سرویس فقط روی سرور بود (`/var/www/dilix-api`) و **زیرِ هیچ
کنترلِ نسخه‌ای نبود**؛ تنها «تاریخچه» فایل‌های `*.bak-<timestamp>` بود که کنارِ
هر ویرایش دستی ساخته می‌شدند (۲۷ فایلِ بکاپ فقط در `app/`). یعنی هیچ diff،
هیچ blame، هیچ بازگشتِ امن و هیچ code review. حالا سورس اینجاست و آن بکاپ‌ها
وارد نشدند — گیت جایشان را گرفته است.

## ساختار

```
app/
  main.py            # FastAPI app، میان‌افزارها (CORS, GZip, security headers, rate limit)
  core/              # config, database, redis, security, netutil, ratelimit
  api/v1/            # ~۲۵ بستهٔ روت: auth, wallet, paygate, messages, posts, reels, ...
  api/deps.py        # get_current_user و وابستگی‌های مشترک
  models/            # مدل‌های SQLAlchemy
  schemas/           # مدل‌های Pydantic
  services/          # منطقِ دامنه (auth, otp, fx, mlm, geo, oauth, ...)
  providers/         # آداپترهای بیرونی (SMS: magfa/twilio + router)
alembic/             # مهاجرت‌های دیتابیس
requirements.txt     # وابستگی‌ها (venv روی سرور: /var/www/dilix-api/venv)
```

## استقرار

```bash
# از ریشهٔ مخزن
./infra/deploy/deploy-api.sh
```

اسکریپت فقط سورس را می‌فرستد و سرویس را ری‌استارت می‌کند. چیزهایی که **عمداً
منتقل نمی‌شوند** و فقط روی سرور زندگی می‌کنند:

| مورد | چرا |
|---|---|
| `.env` | سکرتِ واقعی. الگو: [`.env.example`](.env.example) |
| `venv/` | ۱۸۹ مگابایت؛ با `requirements.txt` بازسازی می‌شود |
| `uploads/` | محتوای کاربر |

> pypi از سرور در دسترس نیست (شبکهٔ ایران). نصبِ پکیجِ تازه یعنی دانلودِ wheel در
> محیطِ توسعه و `scp` کردنِ آن، یا کپی از venvِ سرویسِ دیگر (هر دو Python 3.12.3).

## نکته‌های عملیاتی

- سرویس: `systemctl {status,restart} dilix-api` · لاگ: `journalctl -u dilix-api -f`
- پورتِ ۸۰۰۰ مستقیم روی `0.0.0.0` باز است (پروکسیِ Node فقط ۸۰/۴۴۳ را می‌گیرد).
  هر تصمیمِ امنیتی باید فرض کند درخواست می‌تواند بدونِ عبور از پروکسی برسد —
  دلیلِ مرزِ اعتمادِ `X-Forwarded-For` در `app/core/ratelimit.py`.
- `create_all` در production خاموش است؛ تغییرِ اسکیمای جدید از راهِ `alembic`.
