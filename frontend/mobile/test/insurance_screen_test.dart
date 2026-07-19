import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/insurance/insurance_screen.dart';

/// کلاینتِ ساختگی: کاتالوگِ محصولات یک محصولِ ساده برمی‌گرداند و فهرستِ
/// درخواست‌ها خالی است (پارس‌پذیر با شکلِ dilix-api).
ApiClient _fakeApi() {
  final products = jsonEncode([
    {
      'id': 'third_party',
      'label': 'بیمه شخص ثالث',
      'emoji': '🚗',
      'needs_route': false,
      'needs_cargo_type': false,
      'value_label': 'سرمایه تعهدی',
      'base_rate_pct': 1.2,
    }
  ]);

  final mock = MockClient((http.Request req) async {
    if (req.url.path.contains('/api/v1/insurance/products')) {
      return http.Response(products, 200,
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
  testWidgets('صفحهٔ بیمه بدونِ خطا رندر می‌شود و فرمِ استعلام را دارد',
      (tester) async {
    await tester.pumpWidget(_wrap(const InsuranceScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('بیمه'), findsOneWidget);
    expect(find.text('استعلامِ بیمه'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'استعلامِ نرخ'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'ثبتِ درخواست'), findsOneWidget);
  });
}
