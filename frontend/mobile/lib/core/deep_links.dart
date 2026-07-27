import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// کاری که یک لینکِ ورودی می‌خواهد در اپ انجام دهد.
enum DeepLinkKind {
  /// `/join?ref=CODE` — ثبتِ معرف (بازاریابیِ شبکه‌ای).
  referral,

  /// `/pay/DLX-…?a=…&n=…` — همان بارِ کدِ QRِ کیف‌پول.
  pay,

  /// `/earth?focus=lat,lng` — پرواز روی مختصات.
  earthFocus,
}

/// یک لینکِ عمیقِ بازگشایی‌شده. فیلدها بسته به [kind] پر می‌شوند.
@immutable
class DeepLinkAction {
  const DeepLinkAction._(this.kind, {this.code, this.payUrl, this.lat, this.lng});

  const DeepLinkAction.referral(String code)
      : this._(DeepLinkKind.referral, code: code);

  const DeepLinkAction.pay(String payUrl)
      : this._(DeepLinkKind.pay, payUrl: payUrl);

  const DeepLinkAction.earthFocus(double lat, double lng)
      : this._(DeepLinkKind.earthFocus, lat: lat, lng: lng);

  final DeepLinkKind kind;

  /// کدِ معرف (فقط [DeepLinkKind.referral]).
  final String? code;

  /// نشانیِ کانونیِ پرداخت که به `wallet/qr/resolve` داده می‌شود
  /// (فقط [DeepLinkKind.pay]).
  final String? payUrl;

  /// مختصاتِ تمرکز (فقط [DeepLinkKind.earthFocus]).
  final double? lat;
  final double? lng;
}

/// لینک‌های عمیقِ ورودی — معادلِ بومیِ مسیرهای وبِ `dilix.ir`.
///
/// بدونِ این، لینکِ دعوت و لینکِ پرداخت روی گوشی مرورگر را باز می‌کردند و کاربر
/// از اپ بیرون می‌افتاد، با اینکه هر دو قابلیت داخلِ اپ پیاده شده‌اند.
///
/// چرا [pending] و نه ناوبریِ مستقیم؟ لینک می‌تواند پیش از ساخته‌شدنِ درختِ
/// ویجت (راه‌اندازیِ سرد) یا در حالتِ ناواردشده برسد؛ پس اینجا فقط نگه داشته
/// می‌شود تا پوستهٔ خانه در اولین فرصتِ ممکن مصرفش کند.
class DeepLinks {
  DeepLinks._();

  /// کدِ معرف باید از مرزِ «ثبت‌نام» رد شود (کاربر هنگامِ کلیک هنوز حساب ندارد)،
  /// پس برخلافِ بقیه روی دیسک پایدار می‌شود — همان کاری که وب با localStorage
  /// می‌کند.
  static const _kPendingRef = 'dilix.pending_ref_code';

  static const Set<String> _hosts = {'dilix.ir', 'www.dilix.ir'};

  /// آخرین لینکِ مصرف‌نشده.
  static final ValueNotifier<DeepLinkAction?> pending = ValueNotifier(null);

  static StreamSubscription<Uri>? _sub;

  /// شروعِ گوش‌دادن به لینک‌های ورودی. `uriLinkStream` علاوه بر لینک‌های بعدی،
  /// لینکی را که اپ با آن از حالتِ سرد بالا آمده هم می‌دهد.
  static void start() {
    if (_sub != null) return;
    _sub = AppLinks().uriLinkStream.listen(handle, onError: (_) {});
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static void handle(Uri uri) {
    final action = parse(uri);
    if (action == null) return;
    if (action.kind == DeepLinkKind.referral) {
      // آتش‌کن‌و‌فراموش‌کن: تا رسیدنِ کاربر به ثبت‌نام روی دیسک می‌مانَد.
      savePendingRef(action.code!);
    }
    pending.value = action;
  }

  static void consume() => pending.value = null;

  /// بازگشاییِ یک نشانی. `null` یعنی این لینک به اپ ربطی ندارد و باید به
  /// مرورگر واگذار شود.
  static DeepLinkAction? parse(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final List<String> segments;
    if (scheme == 'dilix') {
      // در `dilix://join?ref=…` نخستین بخشِ مسیر به‌عنوانِ host پارس می‌شود.
      segments = [
        if (uri.host.isNotEmpty) uri.host,
        ...uri.pathSegments,
      ];
    } else if ((scheme == 'https' || scheme == 'http') &&
        _hosts.contains(uri.host.toLowerCase())) {
      segments = uri.pathSegments;
    } else {
      return null;
    }
    if (segments.isEmpty) return null;

    switch (segments.first.toLowerCase()) {
      case 'join':
        final ref = uri.queryParameters['ref']?.trim() ?? '';
        if (ref.isEmpty) return null;
        return DeepLinkAction.referral(ref.toUpperCase());

      case 'pay':
        if (segments.length < 2 || segments[1].isEmpty) return null;
        // نشانی همیشه با دامنهٔ رسمی بازسازی می‌شود: سرور میزبانِ بارِ QR را در
        // برابرِ فهرستِ مجاز بررسی می‌کند و `dilix://…` را رد می‌کرد.
        final canonical = Uri.https(
          'dilix.ir',
          '/pay/${segments[1]}',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
        return DeepLinkAction.pay(canonical.toString());

      case 'earth':
        final parts = (uri.queryParameters['focus'] ?? '').split(',');
        if (parts.length != 2) return null;
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat == null || lng == null) return null;
        if (lat.abs() > 90 || lng.abs() > 180) return null;
        return DeepLinkAction.earthFocus(lat, lng);
    }
    return null;
  }

  static Future<void> savePendingRef(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingRef, code);
  }

  /// کدِ معرفِ ذخیره‌شده را برمی‌دارد و پاک می‌کند (یک‌بارمصرف).
  static Future<String?> takePendingRef() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kPendingRef);
    if (code != null) await prefs.remove(_kPendingRef);
    return code;
  }
}
