import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// شمارندهٔ سراسریِ اعلان‌های نخوانده.
///
/// وب زنگوله و شمارِ نخوانده را در هدرِ **هر** صفحه دارد؛ موبایل هدرِ مشترک
/// ندارد، پس شمارنده یک‌جا نگه داشته می‌شود و هم روی تبِ «من» (نشانِ نقطه‌ای در
/// نوارِ پایین) و هم روی زنگولهٔ صفحهٔ خانه نمایش داده می‌شود. بدونِ این، کاربر
/// تا وارد تبِ «من» نشود از اعلانِ تازه خبردار نمی‌شد.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter._();

  static final NotificationCenter instance = NotificationCenter._();

  /// همان بازهٔ پولِ وب (`AppShell`).
  static const pollInterval = Duration(seconds: 60);

  int _unread = 0;
  int get unread => _unread;

  ApiClient? _api;
  Timer? _timer;

  /// راه‌اندازیِ idempotent؛ پوستهٔ خانه صدایش می‌زند. تا وقتی نشستی نیست
  /// تایمری هم ساخته نمی‌شود (هر درخواست ۴۰۱ می‌گرفت).
  void start(ApiClient api) {
    if (identical(_api, api) && _timer != null) return;
    _api = api;
    _timer?.cancel();
    _timer = null;
    if (!api.isAuthenticated) return;
    _timer = Timer.periodic(pollInterval, (_) => refresh());
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null || !api.isAuthenticated) return;
    try {
      setUnread(await api.unreadNotificationCount());
    } catch (_) {
      // قطعیِ شبکه شمارندهٔ قبلی را خراب نکند.
    }
  }

  /// به‌روزرسانیِ محلی پس از خواندنِ اعلان‌ها داخلِ خودِ اپ، بدونِ رفت‌وبرگشتِ شبکه.
  void setUnread(int value) {
    final next = value < 0 ? 0 : value;
    if (next == _unread) return;
    _unread = next;
    notifyListeners();
  }
}
