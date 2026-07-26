import '../l10n/translations.dart';

/// لایهٔ ترجمهٔ اپ — سبکِ gettext: **خودِ متنِ فارسی کلید است**.
///
/// چرا کلیدِ متنی و نه کلیدِ نمادین (`wallet.title`)؟ چون سورس از پیش با هزاران
/// رشتهٔ فارسیِ هاردکد نوشته شده بود؛ با این روش کد خوانا می‌مانَد، فارسی هرگز
/// جدولِ ترجمه لازم ندارد (fallbackِ طبیعی = خودِ کلید) و اضافه‌شدنِ زبانِ جدید
/// فقط یک فایلِ نگاشت است، بدونِ دست‌زدن به UI.
///
/// جست‌وجو تک‌مرحله‌ای است: جدولِ زبانِ جاری → متنِ مبدأ (فارسی).
class L10n {
  L10n._();

  /// زبان‌هایی که راست‌به‌چپ نوشته می‌شوند.
  static const Set<String> rtlLanguages = {'fa', 'ar', 'ur', 'ps'};

  static String _language = 'fa';
  static Map<String, String> _table = const {};

  /// کدِ زبانِ فعالِ اپ (`fa`, `en`, ...).
  static String get language => _language;

  static bool get isRtl => rtlLanguages.contains(_language);

  /// فعال‌سازیِ یک زبان. اگر جدولِ ترجمه‌ای نداشته باشیم (مثلِ `fa` که زبانِ
  /// مبدأ است) جدول خالی می‌مانَد و [tr] خودِ متنِ مبدأ را برمی‌گردانَد.
  static void setLanguage(String code) {
    _language = code;
    _table = kTranslations[code] ?? const <String, String>{};
  }

  /// ترجمهٔ خام بدونِ جای‌گذاریِ پارامتر.
  static String lookup(String source) => _table[source] ?? source;

  /// آیا برای این زبان جدولی بارگذاری شده است؟ (برای تشخیصِ زبانِ ترجمه‌نشده)
  static bool get hasTable => _table.isNotEmpty;
}

/// ترجمهٔ [source] به زبانِ فعال، با جای‌گذاریِ اختیاریِ پارامترها.
///
/// پارامترها در متن با `{0}`، `{1}`، ... مشخص می‌شوند تا مترجم بتواند ترتیبِ
/// آن‌ها را متناسب با دستورِ زبانِ مقصد جابه‌جا کند:
/// ```dart
/// tr('بارگذاری ممکن نشد: {0}', [e]);
/// ```
String tr(String source, [List<Object?> args = const []]) {
  var out = L10n.lookup(source);
  for (var i = 0; i < args.length; i++) {
    out = out.replaceAll('{$i}', '${args[i]}');
  }
  return out;
}
