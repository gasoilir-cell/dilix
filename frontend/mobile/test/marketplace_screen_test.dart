import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/marketplace/marketplace_screen.dart';

/// کلاینتِ ساختگی که مسیرها را مسیریابی می‌کند: فهرستِ آگهی‌ها، هویت، و
/// سایرِ مسیرها را با آرایه‌ی خالی/داده‌ی حداقلی پاسخ می‌دهد (بدونِ شبکه).
ApiClient _fakeApi() {
  final listings = jsonEncode([
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'provider_earth_id': '22222222-2222-2222-2222-222222222222',
      'title': 'طراحیِ لوگو',
      'description': 'طراحیِ حرفه‌ایِ لوگو',
      'category': 'طراحی',
      'base_price_minor': 1500000,
      'currency': 'IRR',
      'delivery_days': 3,
      'tags': <String>[],
      'status': 'active',
      'is_featured': false,
    },
  ]);
  final identity = jsonEncode({
    'earth_id': 'DLX-TEST0003',
    'entity_type': 'individual',
    'status': 'active',
    'kyc_level': 0,
    'country_code': 'IR',
    'full_name': 'کاربرِ آزمایشی',
  });

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/v1/marketplace/listings')) {
      return http.Response(listings, 200,
          headers: {'content-type': 'application/json'});
    }
    if (path.contains('/auth/me')) {
      return http.Response(identity, 200,
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
  testWidgets('بازارگاه دو تبِ خدمات و سفارش‌های من را نشان می‌دهد',
      (tester) async {
    await tester.pumpWidget(_wrap(const MarketplaceScreen(), _fakeApi()));
    await tester.pump();

    expect(find.text('بازارگاه'), findsOneWidget);
    expect(find.text('خدمات'), findsOneWidget);
    expect(find.text('سفارش‌های من'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
  });

  testWidgets('آگهی‌های موکِ API رندر می‌شوند و دکمهٔ سفارش دارند',
      (tester) async {
    await tester.pumpWidget(_wrap(const MarketplaceScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('طراحیِ لوگو'), findsOneWidget);
    expect(find.text('طراحیِ حرفه‌ایِ لوگو'), findsOneWidget);
    expect(find.text('سفارش'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
  });
}
