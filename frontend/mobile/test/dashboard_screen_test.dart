import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/dashboard/dashboard_screen.dart';

/// کلاینتِ ساختگی: هویت را برای `/api/v1/auth/me` و کیفِ پاداشِ خالی را برای
/// `/v1/growth/rewards` پاسخ می‌دهد؛ سایرِ مسیرها آرایه‌ی خالی (بدونِ شبکه).
ApiClient _fakeApi() {
  final me = jsonEncode({
    'earth_id': 'DLX-TEST0001',
    'entity_type': 'individual',
    'status': 'active',
    'kyc_level': 1,
    'country_code': 'IR',
    'full_name': 'کاربرِ آزمایشی',
  });
  final wallet = jsonEncode({'balances': [], 'pending_count': 0});

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/auth/me')) {
      return http.Response(me, 200,
          headers: {'content-type': 'application/json'});
    }
    if (path.contains('/v1/growth/rewards')) {
      return http.Response(wallet, 200,
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
  testWidgets('داشبورد بدونِ خطا رندر می‌شود و میان‌برهای اصلی را دارد',
      (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('نمای کلی'), findsOneWidget);
    expect(find.text('خدماتِ من'), findsOneWidget);
    expect(find.text('کیفِ پول'), findsOneWidget);
    expect(find.text('کرهٔ زمین'), findsOneWidget);
    expect(find.text('همهٔ خدمات'), findsOneWidget);
  });
}
