import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// نتیجهٔ یک تلاش برای گرفتنِ موقعیت: یا مختصات، یا پیامِ خطایِ قابلِ نمایش.
class LocationFix {
  const LocationFix.ok(this.lat, this.lng, this.accuracy) : error = null;
  const LocationFix.failed(this.error)
      : lat = 0,
        lng = 0,
        accuracy = null;

  final double lat;
  final double lng;
  final double? accuracy;
  final String? error;

  bool get isOk => error == null;
}

/// پوششِ نازکِ `geolocator` با پیام‌های فارسی. تنها راهِ گرفتنِ GPS در اپ است تا
/// منطقِ مجوز در یک جا بماند (کره، موقعیتِ چت، موقعیتِ زنده).
class LocationService {
  const LocationService();

  /// دقتِ متوسط برای به‌روزرسانی‌های پیوسته (مصرفِ باتریِ کمتر) و دقتِ بالا برای
  /// ثبتِ تک‌باره.
  static final _highAccuracy =
      LocationSettings(accuracy: LocationAccuracy.high);
  static final _mediumAccuracy =
      LocationSettings(accuracy: LocationAccuracy.medium);

  /// مجوز را در صورتِ نیاز درخواست می‌کند و موقعیتِ فعلی را برمی‌گرداند.
  /// هرگز throw نمی‌کند؛ خطا در [LocationFix.error] برمی‌گردد.
  Future<LocationFix> current({bool highAccuracy = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFix.failed(
            'مکان‌یابِ دستگاه خاموش است. آن را روشن کن و دوباره تلاش کن.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationFix.failed(
            'اجازهٔ دسترسی به مکان برای همیشه رد شده است؛ از تنظیماتِ اپ آن را فعال کن.');
      }
      if (permission == LocationPermission.denied) {
        return const LocationFix.failed('اجازهٔ دسترسی به مکان داده نشد.');
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings: highAccuracy ? _highAccuracy : _mediumAccuracy);
      return LocationFix.ok(p.latitude, p.longitude, p.accuracy);
    } catch (e) {
      return LocationFix.failed('دریافتِ موقعیت ناموفق بود: $e');
    }
  }

  /// جریانِ پیوستهٔ موقعیت برای اشتراکِ زنده.
  ///
  /// روی اندروید با `foregroundNotificationConfig` سرویس به‌صورتِ **foreground
  /// service** (نوعِ `location`، از مانیفستِ خودِ geolocator) اجرا می‌شود؛ بدونِ
  /// آن اندروید ۸+ موقعیتِ اپِ پس‌زمینه را به چند بار در ساعت throttle می‌کند و
  /// اشتراکِ زنده عملاً می‌ایستد. با آن، تا وقتی نوتیفیکیشنِ پایدار دیده می‌شود
  /// فیکس‌ها می‌رسند حتی اگر کاربر اپ را عوض کند.
  ///
  /// ⚠ محدودیتِ شناخته‌شده (مستندِ خودِ geolocator): این سرویس به activity گره
  /// خورده است؛ اگر کاربر اپ را از recents ببندد (force-kill) جریان قطع می‌شود.
  /// اشتراکِ سمتِ سرور خودش با `duration_minutes` منقضی می‌شود، پس داده‌ی بیات
  /// نمی‌ماند.
  ///
  /// چون سرویس همیشه با کنشِ کاربر و درحالی‌که اپ دیده می‌شود آغاز می‌گردد،
  /// `ACCESS_BACKGROUND_LOCATION` لازم **نیست** (foreground serviceِ نوعِ
  /// location این را پوشش می‌دهد) و عمداً درخواست نمی‌شود.
  /// خروجی `LocationFix` است (نه `Position`) تا هیچ صفحه‌ای نیاز به importِ
  /// `geolocator` نداشته باشد و مرزِ سرویس حفظ شود.
  Stream<LocationFix> liveStream({
    Duration interval = const Duration(seconds: 30),
    int distanceFilterMeters = 20,
    required String notificationTitle,
    required String notificationText,
  }) {
    Stream<Position> raw;
    if (defaultTargetPlatform == TargetPlatform.android) {
      raw = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
          intervalDuration: interval,
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: notificationTitle,
            notificationText: notificationText,
            notificationChannelName: 'اشتراکِ موقعیتِ زنده',
            // بدونِ wake lock، فیکس‌ها تا بیدارشدنِ دستگاه انبار می‌شوند و
            // «زنده» بودنِ اشتراک از بین می‌رود.
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      );
    } else {
      raw = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        ),
      );
    }
    // خطای جریان (مثلِ خاموش‌شدنِ مکان‌یاب در میانِ اشتراک) به یک fix ناموفق
    // تبدیل می‌شود تا مصرف‌کننده مجبور به try/catch روی stream نباشد.
    return raw.transform(
      StreamTransformer<Position, LocationFix>.fromHandlers(
        handleData: (p, sink) =>
            sink.add(LocationFix.ok(p.latitude, p.longitude, p.accuracy)),
        handleError: (e, _, sink) =>
            sink.add(LocationFix.failed('دریافتِ موقعیت قطع شد: $e')),
      ),
    );
  }
}
