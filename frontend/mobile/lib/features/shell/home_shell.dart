import 'package:flutter/material.dart';

import '../assistant/assistant_sheet.dart';
import '../earth/earth_screen.dart';
import '../feed/feed_screen.dart';
import '../me/me_screen.dart';
import '../messages/messages_screen.dart';
import '../notifications/unread_badge.dart';
import '../reels/reels_screen.dart';
import '../wallet/qr_scan_pay_screen.dart';

import '../../app.dart';
import '../../core/deep_links.dart';
import '../../core/earth_focus.dart';
import '../../core/l10n.dart';
import '../../core/notification_center.dart';
import '../../core/preferences.dart';

/// پوسته‌ی Super-App با ناوبریِ پایین ۵تایی + دکمه‌ی شناورِ دستیار (سند ۷ §۲).
///
/// ترتیبِ تب‌ها عمداً همان نوارِ پایینِ وب است (خانه، ریلز، پیام‌ها، کره، من) تا
/// کاربری که هر دو را استفاده می‌کند حافظهٔ عضلانی‌اش عوض نشود. هابِ «خدمات» —
/// که در وب هم تبِ اصلی نیست — از نوارِ بالای صفحهٔ خانه باز می‌شود.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// جایگاهِ تبِ کره در [_screens]؛ لینکِ عمیق و کارتِ موقعیت به آن می‌پرند.
  static const _earthTab = 3;

  static const _screens = <Widget>[
    FeedScreen(),
    ReelsScreen(),
    MessagesScreen(),
    EarthScreen(),
    MeScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // کارتِ موقعیتِ پست (فید، کاوش، لحظه‌ها) تبِ کره را فعال می‌کند؛ خودِ تمرکز
    // را `EarthScreen` از `EarthFocus.request` برمی‌دارد.
    EarthFocus.openEarthTab = () {
      if (mounted && _index != _earthTab) setState(() => _index = _earthTab);
    };
    DeepLinks.pending.addListener(_onDeepLink);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // شمارندهٔ اعلان تا وقتی پوستهٔ واردشده روی صفحه است پول می‌شود.
    NotificationCenter.instance.start(ApiScope.of(context));
    // لینکی که پیش از ساخته‌شدنِ این درخت رسیده (راه‌اندازیِ سرد) و کدِ معرفی که
    // از پیش از ثبت‌نام مانده، در همین نخستین فریم مصرف می‌شوند.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyPendingReferral();
      _onDeepLink();
    });
  }

  @override
  void dispose() {
    EarthFocus.openEarthTab = null;
    DeepLinks.pending.removeListener(_onDeepLink);
    NotificationCenter.instance.stop();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onDeepLink() async {
    final action = DeepLinks.pending.value;
    if (action == null || !mounted) return;
    // پیش از هر `await` مصرف می‌شود تا رسیدنِ لینکِ بعدی دوباره همین را اجرا نکند.
    DeepLinks.consume();
    switch (action.kind) {
      case DeepLinkKind.earthFocus:
        EarthFocus.show(action.lat!, action.lng!);
      case DeepLinkKind.referral:
        await _applyPendingReferral();
      case DeepLinkKind.pay:
        await _openPayLink(action.payUrl!);
    }
  }

  /// ثبتِ کدِ معرفِ باقی‌مانده از لینکِ دعوت. سرور اگر معرف قبلاً ثبت شده باشد
  /// ۴۰۰ می‌دهد؛ آن حالت *خطای کاربر* نیست، پس مثلِ وب بی‌صدا رد می‌شود.
  Future<void> _applyPendingReferral() async {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) return;
    final code = await DeepLinks.takePendingRef();
    if (code == null || code.isEmpty || !mounted) return;
    try {
      final by = await api.applyReferral(code);
      _snack(by.isEmpty
          ? tr('کدِ دعوت ثبت شد.')
          : tr('معرفِ شما ثبت شد: {0}', [by]));
    } catch (_) {
      // قبلاً معرف داشته یا کد نامعتبر بوده؛ کد یک‌بارمصرف مصرف شده و تمام.
    }
  }

  /// لینکِ `dilix.ir/pay/…` — همان مسیرِ کدِ QR، ولی بدونِ دوربین. پول هرگز
  /// خودکار جابه‌جا نمی‌شود: اول گیرنده از سرور بازگشایی و به کاربر نشان داده
  /// می‌شود، بعد خودش تأیید می‌کند.
  Future<void> _openPayLink(String url) async {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) return;
    try {
      final target = await api.resolveWalletQr(url);
      if (!mounted) return;
      if (target.isSelf) {
        _snack(tr('این لینکِ پرداختِ خودِ شماست؛ نمی‌توان به خود پرداخت کرد.'));
        return;
      }
      final paid = await showConfirmPaySheet(context, target);
      if (paid == true) _snack(tr('پرداخت انجام شد.'));
    } catch (e) {
      _snack(tr('لینکِ پرداخت خوانده نشد: {0}', [e]));
    }
  }

  void _openAssistant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AssistantSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // خواندنِ زبان از [PreferencesScope] این پوسته را «وابسته» می‌کند؛ وگرنه
    // `RootGate` پوسته را با نمونهٔ `const` می‌سازد و Flutter بازسازیِ زیردرخت را
    // رد می‌کند، پس برچسب‌های نوارِ پایین با تعویضِ زبان فارسی می‌مانند.
    final lang = PreferencesScope.of(context).locale?.languageCode ?? 'fa';
    return Scaffold(
      // صفحه‌های تب‌ها یک‌بار ساخته و در IndexedStack زنده نگه داشته می‌شوند؛
      // کلیدِ زبان آن‌ها را با تعویضِ زبان از نو می‌سازد (تبِ فعال حفظ می‌شود).
      body: KeyedSubtree(
        key: ValueKey(lang),
        child: IndexedStack(index: _index, children: _screens),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAssistant,
        tooltip: tr('دستیار هوشمند'),
        child: const Icon(Icons.auto_awesome),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('خانه')),
          NavigationDestination(icon: const Icon(Icons.slideshow_outlined), selectedIcon: const Icon(Icons.slideshow), label: tr('ریلز')),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), selectedIcon: const Icon(Icons.chat_bubble), label: tr('پیام‌ها')),
          NavigationDestination(icon: const Icon(Icons.public_outlined), selectedIcon: const Icon(Icons.public), label: tr('کره')),
          // نشانِ نخوانده روی «من» تنها جایی است که از هر تبی دیده می‌شود —
          // معادلِ زنگولهٔ همیشه‌حاضرِ هدرِ وب.
          NavigationDestination(
            icon: const UnreadBadge(child: Icon(Icons.person_outline)),
            selectedIcon: const UnreadBadge(child: Icon(Icons.person)),
            label: tr('من'),
          ),
        ],
      ),
    );
  }
}
