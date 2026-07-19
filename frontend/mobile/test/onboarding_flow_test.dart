import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/core/preferences.dart';
import 'package:dilix_mobile/features/onboarding/onboarding_flow.dart';

ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async {
    return http.Response('[]', 200, headers: {'content-type': 'application/json'});
  });
  return ApiClient(client: mock, baseUrl: 'http://test.local');
}

Widget _wrap(PreferencesController prefs, ApiClient api) {
  return PreferencesScope(
    controller: prefs,
    child: ApiScope(
      api: api,
      child: MaterialApp(
        locale: prefs.locale,
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: OnboardingFlow(onFinished: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('آنبوردینگ: صفحهٔ زبان ۱۲ زبان را نشان می‌دهد و به قوانین می‌رود',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesController();
    await prefs.load();

    await tester.pumpWidget(_wrap(prefs, _fakeApi()));
    await tester.pumpAndSettle();

    // مرحلهٔ ۱: انتخابِ زبان — نمونه‌ای از نام‌های بومی حاضرند.
    expect(find.text('English'), findsWidgets);
    expect(find.text('فارسی'), findsOneWidget);
    expect(find.text('Türkçe'), findsOneWidget);

    // ادامه → مرحلهٔ ۲: قوانین و مقررات (دکمهٔ موافقت).
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Agree & Continue'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('آنبوردینگ: لمسِ لینکِ شرایط، متنِ کاملِ حقوقی را باز می‌کند',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesController();
    await prefs.load();

    await tester.pumpWidget(_wrap(prefs, _fakeApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Terms of Service'));
    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();
    // متنِ سندِ حقوقی (پنجرهٔ پایین‌کشویی) نمایش داده می‌شود.
    expect(find.textContaining('intermediary platform'), findsOneWidget);
  });
}
