import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/app_lock.dart';
import 'core/config.dart';
import 'core/deep_links.dart';
import 'core/preferences.dart';
import 'core/theme.dart';
import 'features/auth/lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/call/call_screen.dart';
import 'features/call/call_service.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'features/shell/home_shell.dart';

/// در دسترس‌گذاریِ ApiClient به کلِ درختِ ویجت (بدونِ وابستگیِ state-management اضافی).
class ApiScope extends InheritedWidget {
  const ApiScope({super.key, required this.api, required super.child});

  final ApiClient api;

  static ApiClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ApiScope>();
    assert(scope != null, 'ApiScope در درختِ ویجت یافت نشد');
    return scope!.api;
  }

  @override
  bool updateShouldNotify(ApiScope oldWidget) => api != oldWidget.api;
}

/// در دسترس‌گذاریِ نمونهٔ سراسریِ [CallService] به کلِ درختِ ویجت، مشابهِ
/// [ApiScope]. همهٔ صفحه‌ها (مثلِ گفتگو) از همین یک نمونه استفاده می‌کنند تا
/// signaling و UIِ تماس هماهنگ بماند.
class CallScope extends InheritedWidget {
  const CallScope({super.key, required this.call, required super.child});

  final CallService call;

  static CallService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CallScope>();
    assert(scope != null, 'CallScope در درختِ ویجت یافت نشد');
    return scope!.call;
  }

  @override
  bool updateShouldNotify(CallScope oldWidget) => call != oldWidget.call;
}

class DilixApp extends StatefulWidget {
  const DilixApp({super.key});

  @override
  State<DilixApp> createState() => _DilixAppState();
}

class _DilixAppState extends State<DilixApp> with WidgetsBindingObserver {
  final ApiClient _api = ApiClient();
  late final CallService _call = CallService(_api);
  final PreferencesController _prefs = PreferencesController();

  @override
  void initState() {
    super.initState();
    _prefs.load();
    // باید پیش از نخستین فریم باشد: لینکی که اپ را از حالتِ سرد بالا آورده،
    // فقط یک‌بار و در همان ابتدا از پلاگین بیرون می‌آید.
    DeepLinks.start();
    // قفلِ زیستی باید پیش از نخستین فریمِ محتوا مشخص باشد، وگرنه اپ یک لحظه
    // باز دیده می‌شود و بعد قفل می‌افتد.
    AppLock.instance.load();
    WidgetsBinding.instance.addObserver(this);
  }

  /// رفتنِ اپ به پس‌زمینه و بازگشتش تنها جایی است که قفل دوباره اعمال می‌شود؛
  /// خودِ [AppLock] تصمیم می‌گیرد که غیبت به‌اندازهٔ کافی طولانی بوده یا نه.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        AppLock.instance.onPaused();
      case AppLifecycleState.resumed:
        AppLock.instance.onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeepLinks.stop();
    _call.dispose();
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreferencesScope(
      controller: _prefs,
      child: ApiScope(
        api: _api,
        child: CallScope(
          call: _call,
          // با تغییرِ زبان/تم توسطِ کاربر، MaterialApp دوباره ساخته می‌شود.
          child: ListenableBuilder(
            listenable: _prefs,
            builder: (context, _) {
              return MaterialApp(
                title: AppConfig.appName,
                debugShowCheckedModeBanner: false,
                theme: DilixTheme.light(),
                darkTheme: DilixTheme.dark(),
                themeMode: _prefs.themeMode,
                locale: _prefs.locale,
                supportedLocales: PreferencesController.languages
                    .map((l) => Locale(l.code))
                    .toList(),
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                // overlayِ سراسریِ تماس: هر صفحه‌ای که فعال باشد، وقتی فازِ تماس
                // از idle خارج شود (ورودی/خروجی/برقرار) صفحهٔ تماس روی کلِ اپ
                // نمایش داده می‌شود؛ با idle دوباره پنهان می‌شود.
                builder: (context, child) {
                  return ListenableBuilder(
                    listenable: _call,
                    builder: (context, _) {
                      return Stack(
                        children: [
                          if (child != null) child,
                          if (_call.phase != CallPhase.idle)
                            Positioned.fill(
                              child: CallScreen(service: _call),
                            ),
                        ],
                      );
                    },
                  );
                },
                home: const RootGate(),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// دروازهٔ ریشه: ابتدا نشستِ پایدارشده را می‌خواند (توکنِ ذخیره‌شده در
/// `shared_preferences`) و تا پایانِ آن یک اسپینر نشان می‌دهد؛ سپس بسته به
/// احراز هویت `LoginScreen` یا `HomeShell` را نمایش می‌دهد.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _sessionLoaded = false;

  @override
  void initState() {
    super.initState();
    // قفل‌شدن/بازشدن هم از چرخهٔ عمرِ اپ می‌آید و هم از صفحهٔ امنیت، پس دروازه
    // باید به تغییرِ وضعیتِ قفل گوش بدهد نه اینکه یک‌بار بخوانَدش.
    AppLock.instance.addListener(_onLockChanged);
  }

  void _onLockChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLock.instance.removeListener(_onLockChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sessionLoaded) {
      _restoreSession();
    }
  }

  Future<void> _restoreSession() async {
    final api = ApiScope.of(context);
    // اگر رفرش‌توکن هم باطل شده باشد، کلاینت نشست را پاک می‌کند و اینجا خبر
    // می‌دهد تا اپ به‌جای ماندن در صفحهٔ خطا به ورود برگردد.
    api.onSessionExpired = () {
      if (!mounted) return;
      CallScope.of(context).stopPolling();
      setState(() {});
    };
    await api.loadSession();
    if (mounted) setState(() => _sessionLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.of(context);
    if (!_sessionLoaded || !prefs.loaded) {
      // نخستین چیزی که کاربر در هر بار بازکردنِ اپ می‌بیند. یک اسپینرِ تنها روی
      // صفحهٔ خالی، این لحظه را شبیهِ «گیرکردن» نشان می‌داد؛ نامِ برند بالای آن
      // همان انتظار را به «در حالِ بالا آمدن» تبدیل می‌کند.
      final theme = Theme.of(context);
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConfig.appName,
                style: theme.textTheme.displaySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: DilixSpacing.xl),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
    }
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) {
      // ورودِ اول: جریانِ ۴ مرحله‌ای (زبان/قوانین/ورود/تم). پس از تکمیلِ یک‌بارِ
      // آنبوردینگ، دفعاتِ بعدی فقط صفحهٔ ورود نمایش داده می‌شود.
      if (!prefs.onboardingComplete) {
        return OnboardingFlow(onFinished: () => setState(() {}));
      }
      return LoginScreen(onAuthenticated: () => setState(() {}));
    }
    // قفلِ زیستی *بعد* از بررسیِ نشست می‌آید: کاربرِ خارج‌شده چیزی برای محافظت
    // ندارد و نباید پشتِ اثرِ انگشت گیر کند.
    if (AppLock.instance.locked) {
      return LockScreen(
        onLogout: () async {
          await AppLock.instance.clearForLogout();
          await api.logout();
          if (mounted) setState(() {});
        },
      );
    }
    // پس از احرازِ هویت، سرویسِ تماس را راه‌اندازی می‌کنیم. حلقهٔ pollِ آن هم
    // تماسِ ورودی را می‌گیرد و هم حضورِ کاربر را زنده نگه می‌دارد (بدونِ آن
    // دیگران «آفلاین» می‌بینندش). init() idempotent است.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final call = CallScope.of(context);
      call.init();
      call.startPolling(); // پس از ورودِ دوباره، حلقهٔ خاموش‌شده روشن می‌شود.
    });
    return const HomeShell();
  }
}
