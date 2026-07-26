import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/core/l10n.dart';
import 'package:dilix_mobile/core/preferences.dart';
import 'package:dilix_mobile/features/shell/home_shell.dart';

ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async {
    return http.Response('[]', 200,
        headers: {'content-type': 'application/json'});
  });
  return ApiClient(client: mock, baseUrl: 'http://test.local');
}

/// همان ترکیبِ ریشهٔ اپ در `DilixApp`: تغییرِ ترجیحات باید کلِ درخت را بازبسازد.
Widget _app(PreferencesController prefs, ApiClient api) {
  return PreferencesScope(
    controller: prefs,
    child: ApiScope(
      api: api,
      child: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => MaterialApp(
          locale: prefs.locale,
          supportedLocales: PreferencesController.languages
              .map((l) => Locale(l.code))
              .toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomeShell(),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.setLanguage('fa');
  });

  tearDown(() => L10n.setLanguage('fa'));

  test('fa زبانِ مبدأ است و جدول ندارد؛ tr خودِ کلید را برمی‌گردانَد', () {
    L10n.setLanguage('fa');
    expect(L10n.hasTable, isFalse);
    expect(tr('خانه'), 'خانه');
  });

  test('کلیدِ نایافته به متنِ فارسی برمی‌گردد', () {
    L10n.setLanguage('en');
    expect(tr('یک رشتهٔ کاملاً ناموجود'), 'یک رشتهٔ کاملاً ناموجود');
  });

  test('جای‌نگهدارها با آرگومان‌ها پر می‌شوند', () {
    L10n.setLanguage('en');
    expect(tr('ریل‌ها ({0})', [7]), 'Reels (7)');
  });

  test('جهتِ متن برای زبان‌های راست‌به‌چپ درست است', () {
    for (final code in ['fa', 'ar', 'ur', 'ps']) {
      L10n.setLanguage(code);
      expect(L10n.isRtl, isTrue, reason: code);
    }
    for (final code in ['en', 'tr', 'ru', 'zh', 'hi', 'es', 'fr', 'de']) {
      L10n.setLanguage(code);
      expect(L10n.isRtl, isFalse, reason: code);
    }
  });

  test('هر ۱۱ زبانِ مقصد جدولِ ترجمه دارند', () {
    for (final lang in PreferencesController.languages) {
      L10n.setLanguage(lang.code);
      if (lang.code == 'fa') continue;
      expect(L10n.hasTable, isTrue, reason: lang.code);
      expect(tr('خانه'), isNot('خانه'), reason: lang.code);
    }
  });

  testWidgets('تعویضِ زبان صفحهٔ ازپیش‌ساخته را دوباره رندر می‌کند',
      (tester) async {
    final prefs = PreferencesController();
    await prefs.load();
    // زبانِ دستگاهِ محیطِ تست فارسی نیست، پس `load()` انگلیسی می‌دهد؛ برای
    // سنجشِ تعویض، صریحاً از فارسی شروع می‌کنیم.
    await prefs.setLocale('fa');
    await tester.pumpWidget(_app(prefs, _fakeApi()));
    await tester.pump();

    expect(find.text('خانه'), findsWidgets);

    await prefs.setLocale('en');
    await tester.pump();

    // اگر فقط متغیرِ سراسری عوض شود و درخت بازساخته نشود، این‌ها رد می‌شوند
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Globe'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('خانه'), findsNothing);
  });
}
