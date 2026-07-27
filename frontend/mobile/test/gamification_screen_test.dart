import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/gamification/gamification_screen.dart';

/// کلاینتِ ساختگی روی اندپوینتِ **زندهٔ** `/api/v1/gamification/me`.
/// (نسخهٔ قبلیِ این تست سرویسِ غیرزندهٔ `core` را موک می‌کرد.)
ApiClient _fakeApi() {
  final profile = jsonEncode({
    'points': 1250,
    'level': {
      'level': 3,
      'title': 'فعال',
      'points': 1250,
      'next_at': 3500,
      'to_next': 2250,
      'progress_pct': 42,
    },
    'streak_days': 4,
    'longest_streak': 9,
    'checked_in_today': false,
    'badges_earned': 1,
    'badges_total': 13,
    'rank': 7,
    'badges': [
      {
        'code': 'first_post',
        'title': 'نخستین پست',
        'description': 'نخستین پستت را منتشر کن',
        'points': 50,
        'earned': true,
        'progress': 1,
        'target': 1,
        'awarded_at': '2026-01-01T00:00:00Z',
      },
      {
        'code': 'creator_10',
        'title': 'سازنده',
        'description': '۱۰ پست منتشر کن',
        'points': 200,
        'earned': false,
        'progress': 3,
        'target': 10,
        'awarded_at': null,
      },
    ],
  });

  final mock = MockClient((http.Request req) async {
    if (req.url.path.contains('/api/v1/gamification/me')) {
      return http.Response(profile, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    return http.Response('[]', 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  return ApiClient(client: mock, baseUrl: 'http://test.local');
}

Widget _wrap(Widget child, ApiClient api) {
  return ApiScope(
    api: api,
    child: MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  testWidgets('کارتِ سطح با امتیاز، رتبه و نوارِ پیشرفت نمایش داده می‌شود',
      (tester) async {
    await tester.pumpWidget(_wrap(const GamificationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('دستاوردها'), findsOneWidget);
    expect(find.text('1250'), findsOneWidget);
    expect(find.text('سطحِ 3 — فعال'), findsOneWidget);
    expect(find.text('رتبهٔ 7'), findsOneWidget);
    expect(find.text('نشان: 1 از 13'), findsOneWidget);
    // یکی برای سطح + یکی برای نشانِ کسب‌نشده (نشانِ کسب‌شده نوار ندارد).
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });

  testWidgets('نشان‌های موکِ API با پیشرفتشان رندر می‌شوند', (tester) async {
    await tester.pumpWidget(_wrap(const GamificationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('نخستین پست'), findsOneWidget);
    expect(find.text('سازنده'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('+200'), findsOneWidget);
  });

  testWidgets('وقتی امروز ثبت نشده، دکمهٔ ورودِ روزانه فعال است', (tester) async {
    await tester.pumpWidget(_wrap(const GamificationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ورودِ روزانه'));
    expect(btn.onPressed, isNotNull);
  });
}
