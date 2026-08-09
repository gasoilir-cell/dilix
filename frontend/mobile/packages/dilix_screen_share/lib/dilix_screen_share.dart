import 'package:flutter/services.dart';

/// سرویسِ پیش‌زمینهٔ لازم برای اشتراکِ صفحه روی اندروید.
///
/// `flutter_webrtc` فقط `getDisplayMedia` را صدا می‌زند و سرویسی ندارد؛ از
/// اندروید ۱۴ همین باعثِ `SecurityException` می‌شود. پس دنبالهٔ درست:
///
/// ```dart
/// await DilixScreenShare.start(title: …, body: …);
/// try {
///   stream = await navigator.mediaDevices.getDisplayMedia(…);
/// } catch (_) {
///   await DilixScreenShare.stop();   // وگرنه اعلان روی نوار می‌مانَد
/// }
/// ```
class DilixScreenShare {
  const DilixScreenShare._();

  static const MethodChannel _ch = MethodChannel('ir.dilix/screen_share');

  /// روی تست/دسکتاپ/وب `false` — فراخوان باید دکمه را پنهان کند.
  static Future<bool> get isSupported async {
    try {
      return await _ch.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// بالا آوردنِ سرویس. باید **پیش از** `getDisplayMedia` صدا زده شود.
  ///
  /// `false` یعنی سیستم اجازه نداد (معمولاً اپ در پس‌زمینه است) و نباید سراغِ
  /// گرفتنِ تصویرِ صفحه رفت.
  static Future<bool> start({
    required String title,
    required String body,
  }) async {
    try {
      return await _ch.invokeMethod<bool>('start', {
            'title': title,
            'body': body,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// خاموش‌کردنِ سرویس و برداشتنِ اعلان. idempotent است.
  static Future<void> stop() async {
    try {
      await _ch.invokeMethod<void>('stop');
    } on MissingPluginException {
      // پلتفرمِ بدونِ پلاگین — چیزی برای خاموش‌کردن نیست.
    } on PlatformException {
      // سرویس بالا نبود.
    }
  }
}
