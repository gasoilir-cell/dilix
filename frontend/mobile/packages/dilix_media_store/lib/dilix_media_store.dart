import 'package:flutter/services.dart';

/// ذخیرهٔ فایل در گالری/دانلودِ عمومیِ اندروید از راهِ MediaStore.
///
/// چرا بستهٔ محلی و نه پکیجِ pub؟ چون CI پوشهٔ `android/` اپ را با
/// `rm -rf android && flutter create` از صفر می‌سازد؛ کدِ بومی فقط داخلِ یک
/// ماژولِ پلاگین پایدار می‌ماند (همان دلیلِ وجودِ `dilix_permissions`).
class DilixMediaStore {
  const DilixMediaStore._();

  static const MethodChannel _ch = MethodChannel('ir.dilix/media_store');

  /// وقتی پلاگینِ بومی در دسترس نیست (تست، دسکتاپ، وب) `false` می‌دهد تا
  /// فراخوان بتواند به برگهٔ اشتراک‌گذاری برگردد.
  static Future<bool> get isSupported async {
    try {
      return await _ch.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// فایلِ [path] را با نامِ [name] در مجموعهٔ عمومیِ متناسب با [mime] می‌نویسد
  /// و توضیحِ محلِ ذخیره را برمی‌گرداند (مثلاً `Pictures/Dilix`).
  ///
  /// روی اندروید ۱۰ به بالا هیچ مجوزی لازم نیست (Scoped Storage). روی نسخه‌های
  /// پایین‌تر `WRITE_EXTERNAL_STORAGE` در زمانِ اجرا درخواست می‌شود.
  ///
  /// در صورتِ شکست [PlatformException] پرتاب می‌کند.
  static Future<String> save({
    required String path,
    required String name,
    String? mime,
  }) async {
    final res = await _ch.invokeMethod<String>('save', {
      'path': path,
      'name': name,
      'mime': mime,
    });
    return res ?? '';
  }
}
