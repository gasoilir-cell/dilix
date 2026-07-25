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
      'cargo_type': 'بارِ تهران',
      'origin': 'تهران',
      'destination': 'اصفهان',
      'status': 'open',
      'weight_kg': 5,
      'price': 500000,
    },
  ]);

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/api/v1/freight/posts')) {
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

    // کاشی‌های بیرونِ ویوپورتِ تست ساخته نمی‌شوند (Sliver فقط ناحیهٔ دید +
    // cache extent را می‌سازد)، پس هر کاشی جداگانه به دید آورده می‌شود؛ این
    // کار تست را نسبت به تعداد و ترتیبِ کاشی‌ها مقاوم می‌کند.
    for (final label in const [
      'حمل‌ونقل',
      'بیمه',
      'دستاوردها',
      'اعتبار',
      'ارائه‌دهنده',
    ]) {
      await tester.dragUntilVisible(
        find.text(label),
        find.byType(GridView),
        const Offset(0, -120),
      );
      expect(find.text(label), findsOneWidget);
    }
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
