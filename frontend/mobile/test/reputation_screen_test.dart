import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/reputation/reputation_screen.dart';

/// کلاینتِ ساختگی: هویت + امتیازِ اعتبار + نظرها را با JSON حداقلی و بقیه را با
/// آرایه‌ی خالی پاسخ می‌دهد (بدونِ شبکه).
ApiClient _fakeApi() {
  final identity = jsonEncode({
    'earth_id': '33333333-3333-3333-3333-333333333333',
    'entity_type': 'individual',
    'status': 'active',
    'kyc_level': 0,
    'home_region': 'IR',
  });
  final scores = jsonEncode([
    {
      'earth_id': '33333333-3333-3333-3333-333333333333',
      'domain': 'freight',
      'score': 85,
      'review_count': 12,
    },
  ]);
  final reviews = jsonEncode([
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'reviewee_earth_id': '33333333-3333-3333-3333-333333333333',
      'reviewer_earth_id': '44444444-4444-4444-4444-444444444444',
      'domain': 'freight',
      'transaction_ref': 'TX-1',
      'rating': 5,
      'comment': 'همکاریِ عالی بود',
    },
  ]);

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/v1/identity/me')) {
      return http.Response(identity, 200,
          headers: {'content-type': 'application/json'});
    }
    if (path.contains('/v1/reputation/scores/')) {
      return http.Response(scores, 200,
          headers: {'content-type': 'application/json'});
    }
    if (path.contains('/v1/reputation/reviews/')) {
      return http.Response(reviews, 200,
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
  testWidgets('عنوانِ اعتبار و کارت‌های امتیاز و نظرها نمایش داده می‌شوند',
      (tester) async {
    await tester.pumpWidget(_wrap(const ReputationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('اعتبار'), findsOneWidget);
    expect(find.text('امتیازِ اعتبار'), findsOneWidget);
    expect(find.text('نظرهای دریافتی'), findsOneWidget);
    // امتیازِ موکِ 85 → 8.5/۱۰
    expect(find.textContaining('8.5/۱۰'), findsOneWidget);
  });

  testWidgets('نظرِ موکِ API با ستاره و کامنت رندر می‌شود',
      (tester) async {
    await tester.pumpWidget(_wrap(const ReputationScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('همکاریِ عالی بود'), findsOneWidget);
    // ۵ ستاره
    expect(find.text('⭐⭐⭐⭐⭐'), findsOneWidget);
  });
}
