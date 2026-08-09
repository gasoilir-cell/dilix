#!/usr/bin/env python3
"""نگاشت‌های دستیِ i18n + پس‌پردازشِ ترجمهٔ ماشینی.

اینجا چیزهایی می‌آید که ترجمهٔ ماشینی ذاتاً درست درنمی‌آورد: نقطه‌گذاری (که
فاصلهٔ انتهایی‌اش معنادار است و در ساختِ متن استفاده می‌شود)، نامِ برند، و
حرفِ بزرگِ آغازِ برچسب.
"""
import json
import os
import re

LTR = ["en", "tr", "ru", "zh", "hi", "es", "fr", "de"]
RTL = ["ar", "ur", "ps"]
ALL = LTR + RTL

# ── نقطه‌گذاری: هرگز ماشینی ترجمه نشود ─────────────────────────────────────
PUNCT = {
    "؟": {**{l: "?" for l in LTR}, **{l: "؟" for l in RTL}},
    "،": {**{l: "," for l in LTR}, **{l: "،" for l in RTL}},
    "، ": {**{l: ", " for l in LTR}, **{l: "، " for l in RTL}},
    "{0}،": {**{l: "{0}," for l in LTR}, **{l: "{0}،" for l in RTL}},
    "{0}: {1}": {"zh": "{0}：{1}"},
    # نمونهٔ شمارهٔ تلفن — رقمِ فارسی فقط برای فارسی/اردو/پشتو خواناست
    "۰۲۱-۰۰۰۰۰۰۰۰": {
        **{l: "021-00000000"
           for l in ("en", "tr", "ru", "zh", "hi", "es", "fr", "de")},
        "ar": "٠٢١-٠٠٠٠٠٠٠٠",
    },
}

# ── برند و اسمِ خاص: ترجمه نمی‌شوند ────────────────────────────────────────
# مترجم این‌ها را واژه‌به‌واژه می‌شکند («اسنپِ بار» → «تحميل المفاجئة»).
BRANDS = {
    "اسنپِ بار": {**{l: "Snapp Bar" for l in LTR},
                  "ar": "سناب بار", "ur": "سنیپ بار", "ps": "سنیپ بار"},
}

# ── اصطلاحاتی که مترجم حتی با زمینه هم در UI اشتباه می‌دهد ─────────────────
# فقط جایی که خطا قطعی است، نه سلیقه‌ای.
OVERRIDES = {
    # «موجودی» را «انبار/inventory» می‌گیرد، درحالی‌که موجودیِ کیفِ پول است
    "موجودی: {0}": {
        "en": "Balance: {0}", "de": "Guthaben: {0}", "fr": "Solde : {0}",
        "es": "Saldo: {0}", "tr": "Bakiye: {0}", "ru": "Баланс: {0}",
        "zh": "余额：{0}", "hi": "शेष: {0}", "ar": "الرصيد: {0}",
        "ur": "بیلنس: {0}", "ps": "بیلانس: {0}",
    },
    # «کدِ ملی» را «country code» می‌گیرد
    "کدِ ملی": {
        "en": "National ID", "de": "Personalausweisnummer",
        "fr": "Numéro national d'identité",
        "es": "Documento nacional de identidad",
        "tr": "Ulusal kimlik numarası", "ru": "Национальный ID",
        "zh": "身份证号", "hi": "राष्ट्रीय पहचान संख्या",
        "ar": "الرقم القومي", "ur": "قومی شناختی نمبر",
        "ps": "ملي پیژندنې شمېره",
    },
    # در زمینهٔ کیفِ پول «اعتبار» یعنی credit، نه validity/credentials
    "اعتبار": {
        "en": "Credit", "de": "Guthaben", "fr": "Crédit", "es": "Crédito",
        "tr": "Kredi", "ru": "Кредит", "zh": "余额", "hi": "क्रेडिट",
        "ar": "الرصيد", "ur": "کریڈٹ", "ps": "کریډیټ",
    },
    # «بازارسال» در جمله به «بازار» + «ارسال» شکسته می‌شود («Bazarsal»،
    # «مارکیٹنگ»). واژهٔ تنها درست ترجمه می‌شود؛ فقط جمله‌ها دستی‌اند.
    "بازارسال از {0}": {
        "en": "Forwarded from {0}", "tr": "İletildi: {0}",
        "ru": "Переслано от {0}", "zh": "转发自 {0}",
        "hi": "{0} से अग्रेषित", "es": "Reenviado de {0}",
        "fr": "Transféré de {0}", "de": "Weitergeleitet von {0}",
        "ar": "أُعيد توجيهه من {0}", "ur": "{0} سے فارورڈ کیا گیا",
        "ps": "له {0} څخه لېږدول شوی",
    },
    "بازارسال‌شده": {
        "en": "Forwarded", "tr": "İletildi", "ru": "Переслано",
        "zh": "已转发", "hi": "अग्रेषित", "es": "Reenviado",
        "fr": "Transféré", "de": "Weitergeleitet", "ar": "مُعاد توجيهه",
        "ur": "فارورڈ شدہ", "ps": "لېږدول شوی",
    },
    "بازارسال شد.": {
        "en": "Forwarded.", "tr": "İletildi.", "ru": "Переслано.",
        "zh": "已转发。", "hi": "अग्रेषित कर दिया गया।", "es": "Reenviado.",
        "fr": "Transféré.", "de": "Weitergeleitet.",
        "ar": "تمت إعادة التوجيه.", "ur": "فارورڈ ہو گیا۔",
        "ps": "ولېږدول شو.",
    },
    "بازارسال به…": {
        "en": "Forward to…", "tr": "Şuraya ilet…", "ru": "Переслать в…",
        "zh": "转发到…", "hi": "इन्हें अग्रेषित करें…", "es": "Reenviar a…",
        "fr": "Transférer à…", "de": "Weiterleiten an…",
        "ar": "إعادة توجيه إلى…", "ur": "فارورڈ کریں…", "ps": "لېږدول ته…",
    },
    "بازارسال ناموفق بود": {
        "en": "Forwarding failed", "tr": "İletme başarısız",
        "ru": "Не удалось переслать", "zh": "转发失败",
        "hi": "अग्रेषण विफल", "es": "Error al reenviar",
        "fr": "Échec du transfert", "de": "Weiterleiten fehlgeschlagen",
        "ar": "فشلت إعادة التوجيه", "ur": "فارورڈ ناکام رہا",
        "ps": "لېږدول ناکام شو",
    },
    "گفتگویِ دیگری برای بازارسال نیست.": {
        "en": "There is no other conversation to forward to.",
        "tr": "İletilecek başka sohbet yok.",
        "ru": "Нет других чатов для пересылки.",
        "zh": "没有其他可转发的对话。",
        "hi": "अग्रेषित करने के लिए कोई अन्य बातचीत नहीं है।",
        "es": "No hay otra conversación a la que reenviar.",
        "fr": "Aucune autre conversation à qui transférer.",
        "de": "Es gibt keine andere Unterhaltung zum Weiterleiten.",
        "ar": "لا توجد محادثة أخرى لإعادة التوجيه إليها.",
        "ur": "فارورڈ کرنے کے لیے کوئی اور گفتگو نہیں ہے۔",
        "ps": "د لېږدولو لپاره بله خبرې اترې نشته.",
    },
    # برچسبِ تبِ کرهٔ زمین؛ مترجم آن را نامِ کشورِ «کُره» می‌خوانَد
    "کره": {
        "en": "Globe", "tr": "Küre", "ru": "Глобус", "zh": "地球",
        "hi": "ग्लोब", "es": "Globo", "fr": "Globe", "de": "Globus",
        "ar": "الكرة الأرضية", "ur": "گلوب", "ps": "ځمکه",
    },
    # `(lat)`/`(lng)` نامِ فنیِ فیلد است و باید دست‌نخورده بماند؛ مترجم آن را
    # ترجمه («(широта)») یا خراب («(lattitude)»، «(late)») می‌کند و در پشتو
    # حتی «طولِ جغرافیایی» را «عرض البلد» داده بود.
    "عرضِ جغرافیایی (lat)": {
        "en": "Latitude (lat)", "tr": "Enlem (lat)", "ru": "Широта (lat)",
        "zh": "纬度 (lat)", "hi": "अक्षांश (lat)", "es": "Latitud (lat)",
        "fr": "Latitude (lat)", "de": "Breitengrad (lat)",
        "ar": "خط العرض (lat)", "ur": "عرض البلد (lat)",
        "ps": "عرض البلد (lat)",
    },
    "طولِ جغرافیایی (lng)": {
        "en": "Longitude (lng)", "tr": "Boylam (lng)", "ru": "Долгота (lng)",
        "zh": "经度 (lng)", "hi": "देशांतर (lng)", "es": "Longitud (lng)",
        "fr": "Longitude (lng)", "de": "Längengrad (lng)",
        "ar": "خط الطول (lng)", "ur": "طول البلد (lng)",
        "ps": "طول البلد (lng)",
    },
    # مترجم «کیفِ پول» را در اردو «پرس» و «کشف» را «دریافت کریں» می‌دهد
    "کیفِ پول": {"ur": "والٹ"},
    "کشف": {"ur": "دریافت"},

    # ── کنترل‌های صفحهٔ تماس ──────────────────────────────────────────────
    # همه برچسبِ تک‌واژه‌ای یا دو‌واژه‌ایِ داخلِ صفحهٔ تماس‌اند؛ همان جایی که
    # مترجمِ ماشینی زمینه ندارد: «تصویری» را «visual/graphic»، «زیرنویس» را
    # «subtitle» (برای فیلم، نه گفتارِ زنده) و «دعوت» را «invitation» (اسم، نه
    # فعلِ دکمه) می‌دهد. دکمه در صفحهٔ تماس باید کوتاه باشد وگرنه زیرِ آیکون
    # می‌شکند، پس ترجمهٔ بلندِ ماشینی حتی وقتی درست است هم به‌درد نمی‌خورد.
    "تصویری": {
        "en": "Video", "tr": "Görüntülü", "ru": "Видео", "zh": "视频通话",
        "hi": "वीडियो", "es": "Vídeo", "fr": "Vidéo", "de": "Video",
        "ar": "فيديو", "ur": "ویڈیو", "ps": "ویډیو",
    },
    "فقط صدا": {
        "en": "Audio only", "tr": "Yalnızca ses", "ru": "Только звук",
        "zh": "仅语音", "hi": "केवल ऑडियो", "es": "Solo audio",
        "fr": "Audio seul", "de": "Nur Ton", "ar": "صوت فقط",
        "ur": "صرف آڈیو", "ps": "یوازې غږ",
    },
    "زیرنویس": {
        "en": "Captions", "tr": "Altyazı", "ru": "Субтитры", "zh": "字幕",
        "hi": "कैप्शन", "es": "Subtítulos", "fr": "Sous-titres",
        "de": "Untertitel", "ar": "الترجمة النصية", "ur": "کیپشن",
        "ps": "زیرنویس",
    },
    "اشتراکِ صفحه": {
        "en": "Share screen", "tr": "Ekranı paylaş",
        "ru": "Демонстрация экрана", "zh": "共享屏幕",
        "hi": "स्क्रीन साझा करें", "es": "Compartir pantalla",
        "fr": "Partager l'écran", "de": "Bildschirm teilen",
        "ar": "مشاركة الشاشة", "ur": "اسکرین شیئر کریں",
        "ps": "سکرین شریکول",
    },
    "در حالِ اشتراکِ صفحه": {
        "en": "Sharing screen", "tr": "Ekran paylaşılıyor",
        "ru": "Идёт демонстрация экрана", "zh": "正在共享屏幕",
        "hi": "स्क्रीन साझा हो रही है", "es": "Compartiendo pantalla",
        "fr": "Partage d'écran en cours", "de": "Bildschirm wird geteilt",
        "ar": "جارٍ مشاركة الشاشة", "ur": "اسکرین شیئر ہو رہی ہے",
        "ps": "سکرین شریکېږي",
    },
    "افزودنِ نفر": {
        "en": "Add person", "tr": "Kişi ekle", "ru": "Добавить участника",
        "zh": "添加成员", "hi": "व्यक्ति जोड़ें", "es": "Añadir persona",
        "fr": "Ajouter une personne", "de": "Person hinzufügen",
        "ar": "إضافة شخص", "ur": "فرد شامل کریں", "ps": "کس ورزیاتول",
    },
    "افزودنِ نفر به تماس": {
        "en": "Add someone to the call", "tr": "Aramaya kişi ekle",
        "ru": "Добавить участника в звонок", "zh": "将成员加入通话",
        "hi": "कॉल में किसी को जोड़ें",
        "es": "Añadir a alguien a la llamada",
        "fr": "Ajouter quelqu'un à l'appel",
        "de": "Jemanden zum Anruf hinzufügen",
        "ar": "إضافة شخص إلى المكالمة", "ur": "کال میں کسی کو شامل کریں",
        "ps": "په اړیکه کې څوک ورزیاتول",
    },
    "دعوت": {
        "en": "Invite", "tr": "Davet et", "ru": "Пригласить", "zh": "邀请",
        "hi": "आमंत्रित करें", "es": "Invitar", "fr": "Inviter",
        "de": "Einladen", "ar": "دعوة", "ur": "دعوت دیں", "ps": "بلنه",
    },
    # عنوانِ تماسِ گروهی. جمعِ زبان‌ها یکسان نیست و مترجم جای {0}/{1} را هم
    # جابه‌جا می‌کند؛ قالبِ هر زبان باید دستی درست بنشیند.
    "{0} و {1} نفرِ دیگر": {
        "en": "{0} and {1} others", "tr": "{0} ve {1} kişi daha",
        "ru": "{0} и ещё {1}", "zh": "{0} 和其他 {1} 人",
        "hi": "{0} और {1} अन्य", "es": "{0} y {1} más",
        "fr": "{0} et {1} autres", "de": "{0} und {1} weitere",
        "ar": "{0} و{1} آخرون", "ur": "{0} اور {1} دیگر",
        "ps": "{0} او {1} نور",
    },
}

# ── واژه‌های دامنه‌ای که مترجم معنایِ عمومی‌شان را می‌گیرد ─────────────────
# «ریل» را راه‌آهن می‌فهمد (Schiene/القضبان/铁轨)، «دیلیکس» را Deluxe، و
# «امانت» را واژه‌به‌واژه ترجمه نمی‌کند. راه‌حل: پیش از ترجمه واژه با
# جای‌نگهدارِ {9} پوشانده می‌شود و پس از ترجمه صورتِ درستِ هر زبان می‌نشیند.
# این‌طور ساختارِ جمله را مترجم می‌سازد و فقط واژهٔ دامنه‌ای دستی است.
MASK = "{9}"
TERMS = {
    "brand": {l: "Dilix" for l in ALL},
    "reel": {
        "en": "Reel", "tr": "Reel", "ru": "Reels", "zh": "短视频",
        "hi": "रील", "es": "Reel", "fr": "Reel", "de": "Reel",
        "ar": "ريل", "ur": "ریل", "ps": "ریل",
    },
    "reels": {
        "en": "Reels", "tr": "Reels", "ru": "Reels", "zh": "短视频",
        "hi": "रील्स", "es": "Reels", "fr": "Reels", "de": "Reels",
        "ar": "ريلز", "ur": "ریلز", "ps": "ریلونه",
    },
    "escrow": {
        "en": "Escrow", "tr": "Emanet", "ru": "Эскроу", "zh": "托管",
        "hi": "एस्क्रो", "es": "Depósito en garantía", "fr": "Séquestre",
        "de": "Treuhand", "ar": "الضمان", "ur": "ایسکرو", "ps": "امانت",
    },
}

MASKED = {
    # برندِ محصول
    "اگر کسی شما را به دیلیکس دعوت کرده، Earth ID او را ثبت کنید. "
    "این کار فقط یک‌بار ممکن است.":
        ("اگر کسی شما را به {9} دعوت کرده، Earth ID او را ثبت کنید. "
         "این کار فقط یک‌بار ممکن است.", "brand"),
    "به دیلیکس خوش آمدید": ("به {9} خوش آمدید", "brand"),
    "در حالِ حاضر مرکزِ فعالی پاسخ نداد؛ فقط نرخِ پایهٔ دیلیکس در دسترس است.":
        ("در حالِ حاضر مرکزِ فعالی پاسخ نداد؛ فقط نرخِ پایهٔ {9} در دسترس است.",
         "brand"),
    "نرخِ پایهٔ دیلیکس": ("نرخِ پایهٔ {9}", "brand"),
    "کاربرِ دیلیکس": ("کاربرِ {9}", "brand"),
    # ویدیوی کوتاه — مفرد
    "انتشارِ ریل": ("انتشارِ {9}", "reel"),
    "انتشارِ ریل ناموفق بود: {0}": ("انتشارِ {9} ناموفق بود: {0}", "reel"),
    "این ریل برای همیشه حذف می‌شود.": ("این {9} برای همیشه حذف می‌شود.",
                                       "reel"),
    "این ریل رسانه‌ای ندارد": ("این {9} رسانه‌ای ندارد", "reel"),
    "حذفِ ریل": ("حذفِ {9}", "reel"),
    "ریل منتشر شد.": ("{9} منتشر شد.", "reel"),
    "کپشنِ ریل": ("کپشنِ {9}", "reel"),
    # ویدیوی کوتاه — جمع
    "ریلز": ("{9}", "reels"),
    "ریل‌ها": ("{9}", "reels"),
    "ریل‌ها ({0})": ("{9} ({0})", "reels"),
    "بارگذاری ریلز ممکن نشد.\n{0}": ("بارگذاری {9} ممکن نشد.\n{0}", "reels"),
    "ریلی نمانده است.": ("فهرستِ {9} تمام شد.", "reels"),
    "هنوز ریلی نیست.\nاولین ویدیوی کوتاه را منتشر کنید.":
        ("هنوز {9} وجود ندارد.\nاولین ویدیوی کوتاه را منتشر کنید.", "reels"),
    # نگه‌داشتِ وجه تا تسویه
    "امانت": ("{9}", "escrow"),
    "{0} · امانت": ("{0} · {9}", "escrow"),
    "سفارش ثبت شد؛ مبلغ در امانت نگه داشته شد.":
        ("سفارش ثبت شد؛ مبلغ در {9} نگه داشته شد.", "escrow"),
}

# ── نقابِ خودکارِ برند ─────────────────────────────────────────────────────
# فهرستِ دستیِ `MASKED` شکننده است: هر رشتهٔ تازه‌ای که نامِ محصول در آن باشد و
# کسی یادش برود اینجا اضافه‌اش کند، بی‌صدا «Deluxe / Делюкс / 豪华版 / ڈیلکس»
# می‌شود — مترجم «دیلیکس» را واژهٔ عمومیِ deluxe می‌خوانَد. پس هر منبعی که نامِ
# برند دارد و دستی پوشانده نشده، خودکار پوشانده می‌شود.
#
# اولویتش عمداً پایین‌ترِ از `MASKED` است و در `generate.py` **بعد از** دیکشنریِ
# وب می‌نشیند: هرجا ترجمهٔ انسانیِ همین محصول هست همان بهتر است، و این نقاب فقط
# جای خالی را پر می‌کند — به‌ویژه اردو و پشتو که دیکشنریِ وب ندارند.
BRAND_RE = re.compile(r"دیلیکس|Dilix")


def _auto_brand_masks() -> dict:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "data", "sources.json")
    if not os.path.exists(path):
        return {}   # هنوز extract.py اجرا نشده؛ مرحلهٔ بعدیِ خط‌لوله می‌سازدش
    with open(path, encoding="utf-8") as fh:
        sources = json.load(fh)["strings"]
    return {src: (BRAND_RE.sub(MASK, src), "brand")
            for src in sources
            if src not in MASKED and BRAND_RE.search(src)}


MASKED_AUTO = _auto_brand_masks()

CURATED = {}
for _table in (PUNCT, BRANDS, OVERRIDES):
    for _src, _row in _table.items():
        CURATED.setdefault(_src, {}).update(_row)

NO_CASE = set(PUNCT) | set(BRANDS)
CASED = {"en", "tr", "es", "fr", "de", "ru"}
LETTER = re.compile(r"[^\W\d_]", re.UNICODE)
CJK = re.compile(r"[\u4e00-\u9fff]")


def unmask(lang: str, src: str, terms_mt: dict, table: dict = None):
    """ترجمهٔ رشتهٔ پوشانده‌شده را با واژهٔ دامنه‌ایِ همان زبان کامل می‌کند.

    اگر متنِ پوشانده‌شده جز جای‌نگهدار چیزی برای ترجمه ندارد (`{0} · {9}`)،
    خودش قالب است. اگر جای‌نگهدار در ترجمه گم شده باشد نتیجه رد می‌شود تا
    مسیرهای بعدیِ خط‌لوله سرِ جایشان بمانند.

    `table` پیش‌فرض `MASKED`ِ دستی است؛ `MASKED_AUTO` با اولویتِ پایین‌تر از
    همین تابع استفاده می‌کند.
    """
    table = MASKED if table is None else table
    if src not in table:
        return None
    masked, key = table[src]
    term = TERMS[key].get(lang)
    if not term:
        return None
    if LETTER.search(masked.replace(MASK, "")):
        template = terms_mt.get(lang, {}).get(masked)
    else:
        template = masked
    if not template or MASK not in template:
        return None
    out = template.replace(MASK, term)
    if CJK.search(term):
        # خطِ چینی فاصلهٔ واژگانی ندارد؛ فاصلهٔ کنارِ جای‌نگهدار زائد است
        out = re.sub(r"(?<=[\u4e00-\u9fff]) (?=[\u4e00-\u9fff])", "", out)
    return out


def sentence_case(lang: str, src: str, val: str) -> str:
    """حرفِ نخستِ برچسب بزرگ شود — خروجیِ ماشینی اغلب کوچک است.

    فقط وقتی مبدأ خودش با حرف شروع شده (نه پسوند/جداکننده) و زبانِ مقصد مفهومِ
    حرفِ بزرگ دارد. در ترکی «i» باید «İ» شود، نه «I».
    """
    if lang not in CASED or not val or src in NO_CASE:
        return val
    if src[:1].isspace() or not LETTER.match(src[:1]):
        return val
    first = val[0]
    if not first.islower():
        return val
    return ("İ" if (lang == "tr" and first == "i") else first.upper()) + val[1:]
