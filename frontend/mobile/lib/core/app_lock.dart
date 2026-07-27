import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

/// وضعیتِ سنجشِ زیستی روی این دستگاه.
enum BiometricStatus {
  /// سخت‌افزار هست و دستِ‌کم یک اثرِ انگشت/چهره ثبت شده.
  ready,

  /// سخت‌افزار هست ولی کاربر هیچ اثرِ انگشتی ثبت نکرده (یا قفلِ صفحه ندارد).
  notEnrolled,

  /// دستگاه اصلاً حسگر ندارد (یا اندرویدِ زیرِ ۲۳ که BiometricPrompt ندارد).
  unsupported,
}

/// امضای تابعِ احراز — تزریق‌پذیر است تا تستِ ویجت بدونِ پلاگینِ بومی
/// (که در محیطِ تست `MissingPluginException` می‌دهد) اجرا شود.
typedef Authenticator = Future<bool> Function(String reason);

/// قفلِ زیستیِ اپ («ورود با اثرِ انگشت»).
///
/// **مرزِ دقیقِ این قابلیت:** این یک قفلِ *محلیِ* روی رابطِ کاربری است، نه روشِ
/// ورود به سرور. نشستِ کاربر همان access/refresh tokenِ موجود است؛ اثرِ انگشت
/// فقط تعیین می‌کند چه‌کسی اجازه دارد اپِ *همین گوشی* را باز کند. یعنی جلوی
/// کسی که گوشیِ بازِ شما را برمی‌دارد گرفته می‌شود، ولی کسی که به فایل‌سیستمِ
/// روت‌شده دسترسی دارد همچنان می‌تواند توکن را بخوانَد. ادعای بیشتر از این
/// کردن، امنیتِ کاذب است.
///
/// چرا `ChangeNotifier`ِ سراسری و نه state درونِ یک صفحه؟ چون قفل باید هم در
/// شروعِ سرد و هم در بازگشت از پس‌زمینه اعمال شود، و `HomeShell` با
/// `IndexedStack` زنده می‌ماند؛ پس تصمیمِ قفل باید بالاتر از درختِ صفحه‌ها
/// (در `RootGate`) گرفته شود.
class AppLock extends ChangeNotifier {
  AppLock._();

  static final AppLock instance = AppLock._();

  static const _kEnabled = 'dilix.app_lock';

  /// بازگشتِ سریع به اپ (مثلاً باز کردنِ گالری برای انتخابِ عکس، یا رفتن به
  /// اپِ پیامک برای خواندنِ کد) نباید هر بار پرسشِ اثرِ انگشت بدهد؛ وگرنه
  /// کاربر قابلیت را همان روزِ اول خاموش می‌کند. فقط غیبتِ طولانی‌تر قفل می‌کند.
  static const grace = Duration(seconds: 30);

  final LocalAuthentication _local = LocalAuthentication();

  /// در تولید به پلاگین وصل است؛ در تست جای‌گزین می‌شود.
  @visibleForTesting
  Authenticator? authenticator;

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _locked = false;
  bool get locked => _locked;

  DateTime? _pausedAt;

  /// خواندنِ تنظیم از حافظهٔ محلی. اگر قفل روشن باشد، اپ **قفل‌شده** بالا
  /// می‌آید — نه باز؛ در غیر این صورت اولین فریم محتوای حساب را لو می‌داد.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _locked = _enabled;
    notifyListeners();
  }

  Future<BiometricStatus> status() async {
    try {
      final supported = await _local.isDeviceSupported();
      if (!supported) return BiometricStatus.unsupported;
      final available = await _local.getAvailableBiometrics();
      return available.isEmpty
          ? BiometricStatus.notEnrolled
          : BiometricStatus.ready;
    } catch (_) {
      return BiometricStatus.unsupported;
    }
  }

  Future<bool> authenticate(String reason) async {
    final custom = authenticator;
    if (custom != null) return custom(reason);
    try {
      return await _local.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // پرسش را در بازگشت از پس‌زمینه زنده نگه می‌دارد.
          stickyAuth: true,
          // عمداً `biometricOnly: false`: رمزِ خودِ گوشی هم پذیرفته می‌شود.
          // با `true` هر کسی که انگشتش خیس/زخمی است یا حسگرش خراب شده، از
          // حسابِ خودش بیرون می‌مانْد.
          biometricOnly: false,
        ),
      );
    } catch (_) {
      // خطای پلتفرم (حسگر مشغول، لغو توسطِ سیستم، …) = احرازِ ناموفق، نه باز.
      return false;
    }
  }

  /// روشن/خاموش کردنِ قفل. روشن‌کردن **فقط پس از یک احرازِ موفق** انجام
  /// می‌شود تا کاربر قابلیتی را که روی دستگاهش کار نمی‌کند فعال نکند و پشتِ
  /// در نمانَد. خاموش‌کردن هم احراز می‌خواهد، وگرنه هر کسی که گوشیِ باز را
  /// در دست دارد می‌توانست قفل را بردارد.
  Future<bool> setEnabled(bool value) async {
    final ok = await authenticate(
      value
          ? tr('برای روشن‌کردنِ قفلِ اپ، هویتتان را تأیید کنید')
          : tr('برای خاموش‌کردنِ قفلِ اپ، هویتتان را تأیید کنید'),
    );
    if (!ok) return false;
    _enabled = value;
    _locked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
    notifyListeners();
    return true;
  }

  /// تلاش برای بازکردنِ قفل از صفحهٔ قفل.
  Future<bool> unlock() async {
    final ok = await authenticate(tr('برای ورود به دیلیکس هویتتان را تأیید کنید'));
    if (ok) {
      _locked = false;
      _pausedAt = null;
      notifyListeners();
    }
    return ok;
  }

  /// راهِ فرار: اگر حسگر خراب شد یا اثرِ انگشت‌ها از تنظیماتِ گوشی پاک شدند،
  /// کاربر نباید برای همیشه از حسابش بیرون بمانَد. خروج از حساب قفل را هم
  /// برمی‌دارد؛ چیزی جز نیاز به ورودِ دوباره از دست نمی‌رود.
  Future<void> clearForLogout() async {
    _enabled = false;
    _locked = false;
    _pausedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEnabled);
    notifyListeners();
  }

  void onPaused() {
    if (!_enabled || _locked) return;
    _pausedAt = DateTime.now();
  }

  void onResumed() {
    if (!_enabled || _locked) return;
    final at = _pausedAt;
    if (at == null) return;
    _pausedAt = null;
    if (DateTime.now().difference(at) >= grace) {
      _locked = true;
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTest() {
    _enabled = false;
    _locked = false;
    _pausedAt = null;
    authenticator = null;
  }
}
