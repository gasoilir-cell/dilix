import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// یک زبانِ قابلِ انتخاب در صفحهٔ اولِ آنبوردینگ.
class AppLanguage {
  const AppLanguage(this.code, this.native, this.english, this.flag);

  /// کدِ locale (مثلِ `fa`, `en`).
  final String code;

  /// نامِ زبان به خطِ خودش (برای نمایش در فهرست).
  final String native;

  /// نامِ انگلیسیِ زبان (زیرنویس).
  final String english;

  /// پرچمِ ایموجی برای شناساییِ سریع.
  final String flag;
}

/// نگه‌دارندهٔ ترجیحاتِ کاربر (زبان + تم + وضعیتِ آنبوردینگ) با پایداری در
/// `shared_preferences`. به‌صورتِ [ChangeNotifier] بالای [MaterialApp] قرار
/// می‌گیرد تا تغییرِ زبان/تم بلافاصله در کلِ اپ اعمال شود.
class PreferencesController extends ChangeNotifier {
  static const _kLocale = 'dilix.locale';
  static const _kThemeMode = 'dilix.theme_mode';
  static const _kOnboarding = 'dilix.onboarding_complete';

  /// دوازده زبانِ پشتیبانی‌شده در انتخاب‌گرِ زبان.
  static const List<AppLanguage> languages = [
    AppLanguage('fa', 'فارسی', 'Persian', '🇮🇷'),
    AppLanguage('en', 'English', 'English', '🇬🇧'),
    AppLanguage('ar', 'العربية', 'Arabic', '🇸🇦'),
    AppLanguage('tr', 'Türkçe', 'Turkish', '🇹🇷'),
    AppLanguage('ru', 'Русский', 'Russian', '🇷🇺'),
    AppLanguage('zh', '中文', 'Chinese', '🇨🇳'),
    AppLanguage('hi', 'हिन्दी', 'Hindi', '🇮🇳'),
    AppLanguage('es', 'Español', 'Spanish', '🇪🇸'),
    AppLanguage('fr', 'Français', 'French', '🇫🇷'),
    AppLanguage('de', 'Deutsch', 'German', '🇩🇪'),
    AppLanguage('ur', 'اردو', 'Urdu', '🇵🇰'),
    AppLanguage('ps', 'پښتو', 'Pashto', '🇦🇫'),
  ];

  bool _loaded = false;
  bool get loaded => _loaded;

  Locale? _locale;
  Locale? get locale => _locale;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool _onboardingComplete = false;
  bool get onboardingComplete => _onboardingComplete;

  /// خواندنِ ترجیحاتِ ذخیره‌شده هنگامِ راه‌اندازیِ اپ.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocale);
    // اگر کاربر هنوز زبان را انتخاب نکرده، زبانِ مؤثرِ اولیه هوشمندانه بر اساسِ
    // زبانِ دستگاه (فارسی یا انگلیسی) تعیین می‌شود تا جهتِ RTL/LTR از همان
    // فریمِ اول درست باشد؛ این مقدار تا تأییدِ کاربر پایدار (persist) نمی‌شود.
    _locale = Locale(
      (code != null && code.isNotEmpty) ? code : deviceSuggestedLanguage(),
    );
    _themeMode = _parseThemeMode(prefs.getString(_kThemeMode));
    _onboardingComplete = prefs.getBool(_kOnboarding) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// زبانِ پیشنهادیِ اولیه بر اساسِ زبانِ دستگاه: فارسی یا انگلیسی (سند کاربر).
  static String deviceSuggestedLanguage() {
    final sys = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return sys == 'fa' ? 'fa' : 'en';
  }

  Future<void> setLocale(String code) async {
    _locale = Locale(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, code);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> completeOnboarding() async {
    _onboardingComplete = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarding, true);
  }

  static ThemeMode _parseThemeMode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

/// دسترسیِ درختِ ویجت به [PreferencesController]. با [InheritedNotifier]
/// وابسته‌ها هنگامِ تغییرِ زبان/تم دوباره ساخته می‌شوند.
class PreferencesScope extends InheritedNotifier<PreferencesController> {
  const PreferencesScope({
    super.key,
    required PreferencesController controller,
    required super.child,
  }) : super(notifier: controller);

  static PreferencesController of(BuildContext context) {
    final c =
        context.dependOnInheritedWidgetOfExactType<PreferencesScope>()?.notifier;
    assert(c != null, 'PreferencesScope در درختِ ویجت یافت نشد');
    return c!;
  }
}
