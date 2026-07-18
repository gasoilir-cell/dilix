import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/services/services_screen.dart';

/// کلاینتِ ساختگی: فهرستِ بار را با یک آیتمِ وضعیتِ `open` و سایرِ مسیرها را با
/// آرایه‌ی خالی پاسخ می‌دهد (بدونِ شبکه).
ApiClient _fakeApi() {
  final cargo = jsonEncode([
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'title': 'بارِ تهران',
      'origin': 'تهران',
      'destination': 'اصفهان',
      'status': 'open',
      'weight_grams': 5000,
      'currency': 'IRR',
    },
  ]);

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/v1/freight/cargo')) {
      return http.Response(cargo, 200,
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
  testWidgets('هابِ خدمات کاشی‌های اصلی را نشان می‌دهد',
      (tester) async {
    await tester.pumpWidget(_wrap(const ServicesScreen(), _fakeApi()));
    await tester.pump();

    expect(find.text('خدمات'), findsOneWidget);
    expect(find.text('حمل‌ونقل'), findsOneWidget);
    expect(find.text('بیمه'), findsOneWidget);
    expect(find.text('دستاوردها'), findsOneWidget);
    expect(find.text('اعتبار'), findsOneWidget);
    expect(find.text('ارائه‌دهنده'), findsOneWidget);
  });

  testWidgets('صفحهٔ حمل‌ونقل برچسبِ فارسیِ وضعیت (STATUS_LABEL) را نشان می‌دهد',
      (tester) async {
    await tester.pumpWidget(_wrap(const FreightScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('اسنپِ بار'), findsOneWidget);
    expect(find.text('بارِ تهران'), findsOneWidget);
    // وضعیتِ open → برچسبِ فارسیِ «باز»
    expect(find.text('باز'), findsOneWidget);
  });
}
