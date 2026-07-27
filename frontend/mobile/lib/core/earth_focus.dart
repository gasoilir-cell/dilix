import 'package:flutter/foundation.dart';

/// پلِ «بردنِ کاربر به کره روی یک مختصات» از هر جای اپ — معادلِ بومیِ لینکِ
/// `/earth?focus=lat,lng` در وب.
///
/// چرا سراسری و نه ناوبریِ معمول؟ تبِ کره داخلِ `IndexedStack`ِ پوسته زنده
/// می‌مانَد؛ ساختِ نمونهٔ تازهٔ `EarthScreen` یعنی بارگذاریِ دوبارهٔ کلِ کرهٔ
/// سه‌بعدی. پس فقط تب عوض می‌شود و درخواستِ تمرکز به همان صفحهٔ زنده می‌رسد.
class EarthFocus {
  const EarthFocus._();

  /// آخرین درخواستِ تمرکز؛ `EarthScreen` به آن گوش می‌دهد.
  static final ValueNotifier<({double lat, double lng})?> request =
      ValueNotifier(null);

  /// پوستهٔ خانه این را ست می‌کند تا بتوان تبِ کره را فعال کرد.
  static void Function()? openEarthTab;

  static void show(double lat, double lng) {
    openEarthTab?.call();
    request.value = (lat: lat, lng: lng);
  }
}
