#!/usr/bin/env python3
"""apk-fingerprint.py — خواندنِ اثرِ انگشتِ گواهیِ امضای APK بدونِ نیاز به Java.

چرا این ابزار؟ نه کانتینرِ اجرا و نه سرورِ Core هیچ‌کدام JDK ندارند، پس
`apksigner` در دسترس نیست. این اسکریپت بلوکِ «APK Signing Block» را
مستقیم از فایلِ zip می‌خواند و گواهیِ X.509 امضاکننده را استخراج می‌کند.

خروجی: اثرِ انگشتِ SHA-256 با فرمتِ دو-نقطه‌ایِ assetlinks.json.

نمونه:
    python3 apk-fingerprint.py app-release.apk
    python3 apk-fingerprint.py app-release.apk --expect EB:F9:...:94
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys

APK_SIG_BLOCK_MAGIC = b"APK Sig Block 42"
BLOCK_ID_V2 = 0x7109871A
BLOCK_ID_V3 = 0xF05368C0

# گواهیِ پیش‌فرضِ debugِ اندروید (~/.android/debug.keystore) همیشه
# subjectِ «C=US, O=Android, CN=Android Debug» دارد. هر APK ای که با آن
# امضا شود App Linksاش تأیید نمی‌شود و روی نصبِ کاربر قابلِ ارتقا نیست.
#
# ⚠ اینجا عمداً دنبالِ *مقدارِ* CN می‌گردیم، نه رشتهٔ «CN=Android Debug»:
# در DER هر AttributeValue جداگانه کدگذاری می‌شود و رشتهٔ «CN=…» هرگز
# به‌صورتِ یکجا در بایت‌ها وجود ندارد. جست‌وجوی فرمِ نمایشی باعث می‌شد
# این گارد همیشه «debug نیست» بگوید — یعنی دقیقاً کور باشد.
DEBUG_CERT_CN = b"Android Debug"


def _find_eocd(data: bytes) -> int:
    """آفستِ رکوردِ End Of Central Directory را برمی‌گرداند."""
    # EOCD حداکثر ۶۵۵۳۵+۲۲ بایت از انتها فاصله دارد (به‌خاطرِ فیلدِ comment).
    search_start = max(0, len(data) - (0xFFFF + 22))
    idx = data.rfind(b"PK\x05\x06", search_start)
    if idx < 0:
        raise ValueError("رکوردِ EOCD پیدا نشد — فایل یک ZIP/APK معتبر نیست.")
    return idx


def _central_directory_offset(data: bytes) -> int:
    eocd = _find_eocd(data)
    (cd_offset,) = struct.unpack_from("<I", data, eocd + 16)
    return cd_offset


def _read_signing_block(data: bytes) -> dict[int, bytes]:
    """جفت‌های id→value داخلِ APK Signing Block را برمی‌گرداند."""
    cd_offset = _central_directory_offset(data)
    if cd_offset < 24:
        raise ValueError("آفستِ Central Directory نامعتبر است.")

    magic = data[cd_offset - 16 : cd_offset]
    if magic != APK_SIG_BLOCK_MAGIC:
        raise ValueError(
            "APK Signing Block پیدا نشد — این APK فقط v1 (JAR signing) دارد "
            "یا اصلاً امضا نشده است."
        )

    (block_size,) = struct.unpack_from("<Q", data, cd_offset - 24)
    block_start = cd_offset - block_size - 8
    if block_start < 0:
        raise ValueError("اندازهٔ Signing Block با اندازهٔ فایل نمی‌خواند.")

    (block_size_head,) = struct.unpack_from("<Q", data, block_start)
    if block_size_head != block_size:
        raise ValueError("اندازهٔ ابتدا و انتهای Signing Block یکسان نیست.")

    pairs: dict[int, bytes] = {}
    pos = block_start + 8
    end = cd_offset - 24  # ابتدای فیلدِ size انتهایی
    while pos < end:
        (pair_len,) = struct.unpack_from("<Q", data, pos)
        pos += 8
        if pair_len < 4 or pos + pair_len > end + 8:
            break
        (pair_id,) = struct.unpack_from("<I", data, pos)
        pairs[pair_id] = data[pos + 4 : pos + pair_len]
        pos += pair_len
    return pairs


def _length_prefixed_items(buf: bytes) -> list[bytes]:
    """دنبالهٔ عناصرِ uint32-length-prefixed را جدا می‌کند."""
    items: list[bytes] = []
    pos = 0
    while pos + 4 <= len(buf):
        (item_len,) = struct.unpack_from("<I", buf, pos)
        pos += 4
        if pos + item_len > len(buf):
            break
        items.append(buf[pos : pos + item_len])
        pos += item_len
    return items


def _certificates_from_signer_block(block: bytes) -> list[bytes]:
    """گواهی‌های DER را از بلوکِ v2/v3 استخراج می‌کند."""
    certs: list[bytes] = []
    # بیرونی‌ترین لایه: دنبالهٔ length-prefixed از signerها
    signers_seq = _length_prefixed_items(block)
    if not signers_seq:
        return certs
    for signer in _length_prefixed_items(signers_seq[0]):
        parts = _length_prefixed_items(signer)
        if not parts:
            continue
        signed_data = parts[0]
        sections = _length_prefixed_items(signed_data)
        # section[0] = digests ، section[1] = certificates
        if len(sections) < 2:
            continue
        certs.extend(_length_prefixed_items(sections[1]))
    return certs


def fingerprint(path: str) -> tuple[str, bytes, str]:
    """(اثرِ انگشتِ SHA-256، گواهیِ DER، نامِ نسخهٔ امضا) را برمی‌گرداند."""
    with open(path, "rb") as fh:
        data = fh.read()

    pairs = _read_signing_block(data)
    for block_id, scheme in ((BLOCK_ID_V3, "v3"), (BLOCK_ID_V2, "v2")):
        if block_id not in pairs:
            continue
        certs = _certificates_from_signer_block(pairs[block_id])
        if certs:
            digest = hashlib.sha256(certs[0]).hexdigest().upper()
            colon = ":".join(digest[i : i + 2] for i in range(0, len(digest), 2))
            return colon, certs[0], scheme
    raise ValueError(
        "هیچ گواهیِ v2/v3 در Signing Block نبود (idهای موجود: "
        + ", ".join(hex(k) for k in pairs)
        + ")"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="اثرِ انگشتِ گواهیِ امضای APK")
    parser.add_argument("apk", help="مسیرِ فایلِ APK")
    parser.add_argument(
        "--expect",
        help="اثرِ انگشتِ مورد انتظار؛ در صورتِ عدمِ تطابق خروجیِ ۱ برمی‌گرداند.",
    )
    args = parser.parse_args()

    try:
        fp, cert_der, scheme = fingerprint(args.apk)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    is_debug = DEBUG_CERT_CN in cert_der
    print(f"scheme      = APK Signature Scheme {scheme}")
    print(f"SHA-256     = {fp}")
    print(f"debug cert? = {'YES ❌' if is_debug else 'no ✅'}")

    if args.expect:
        want = args.expect.strip().upper().replace(" ", "")
        if want != fp:
            print(f"MISMATCH: انتظار می‌رفت {want}", file=sys.stderr)
            return 1
        print("match       = ✅ با مقدارِ انتظاری یکی است")

    if is_debug:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
