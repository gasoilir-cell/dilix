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
}
