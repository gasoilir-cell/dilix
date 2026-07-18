import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/gamification/gamification_screen.dart';

/// کلاینتِ ساختگی: امتیازِ پاداش و نشان‌ها را با JSON حداقلی و بقیه را با
/// آرایه‌ی خالی پاسخ می‌دهد (بدونِ شبکه).
ApiClient _fakeApi() {
  final points = jsonEncode({'balance': 1250});
  final badges = jsonEncode([
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'badge_code': 'first_trade',
      'description': 'اولین معامله',
      'awarded_at': '2026-01-01T00:00:00Z',
    },
  ]);

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/v1/gamification/points')) {
      return http.Response(points, 200,
          headers: {'content-type': 'application/json'});
    }
    if (path.contains('/v1/gamification/badges')) {
      return http.Response(badges, 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('[]', 200,
        headers: {'content-type': 'application/json'});
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
  testWidgets('عنوانِ دستاوردها و کارتِ امتیاز با نوارِ پیشرفت نمایش داده می‌شود',
      (tester) async {
    await tester.pumpWidget(_wrap(const GamificationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('دستاوردها'), findsOneWidget);
    expect(find.text('امتیازِ من'), findsOneWidget);
    expect(find.text('نشان‌ها'), findsOneWidget);
    // موجودیِ موکِ API روی چیپِ امتیاز
    expect(find.text('1250'), findsOneWidget);
    // نوارِ پیشرفت
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('نشانِ موکِ API رندر می‌شود',
      (tester) async {
    await tester.pumpWidget(_wrap(const GamificationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('اولین معامله'), findsOneWidget);
    expect(find.byType(Chip), findsWidgets);
  });
}
