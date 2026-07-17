import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
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

class DilixApp extends StatefulWidget {
  const DilixApp({super.key});

  @override
  State<DilixApp> createState() => _DilixAppState();
}

class _DilixAppState extends State<DilixApp> {
  final ApiClient _api = ApiClient();

  @override
  Widget build(BuildContext context) {
    return ApiScope(
      api: _api,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: DilixTheme.light(),
        darkTheme: DilixTheme.dark(),
        locale: Locale(AppConfig.defaultLocale),
        supportedLocales: const [
          Locale('fa'),
          Locale('ar'),
          Locale('en'),
          Locale('ru'),
          Locale('tr'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RootGate(),
      ),
    );
  }
}

/// دروازهٔ ریشه: تا وقتی کاربر احراز هویت نشده `LoginScreen`، و پس از
/// ورودِ موفق `HomeShell` را نشان می‌دهد.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) {
      return LoginScreen(onAuthenticated: () => setState(() {}));
    }
    return const HomeShell();
  }
}
