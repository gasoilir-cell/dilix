import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/membership/membership_screen.dart';

/// کلاینتِ ساختگی: عضویتِ فعلی (پلنِ standard) را با JSON حداقلی و سایرِ
/// مسیرها (نشان‌ها/هویت/اعتبار) را با آرایه‌ی خالی پاسخ می‌دهد (بدونِ شبکه).
ApiClient _fakeApi() {
  final membership = jsonEncode({
    'id': '11111111-1111-1111-1111-111111111111',
    'earth_id': '22222222-2222-2222-2222-222222222222',
    'plan': 'standard',
    'status': 'active',
    'cashback_bps': 150,
    'expires_at': null,
  });

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/v1/membership')) {
      return http.Response(membership, 200,
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
  testWidgets('عضویتِ فعلی و پلن‌ها با برچسبِ فارسی نمایش داده می‌شوند',
      (tester) async {
    await tester.pumpWidget(_wrap(const MembershipScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('عضویت و اعتبار'), findsOneWidget);
    expect(find.text('عضویتِ فعلی'), findsOneWidget);
    expect(find.text('پلن‌ها'), findsOneWidget);
    // برچسب‌های فارسیِ پلن (parity با PLANS وب)
    expect(find.text('رایگان'), findsOneWidget);
    expect(find.text('استاندارد'), findsWidgets);
    expect(find.text('ویژه'), findsOneWidget);
  });

  testWidgets('پلنِ فعال چیپِ «فعال» و بقیه دکمهٔ «انتخاب» دارند',
      (tester) async {
    await tester.pumpWidget(_wrap(const MembershipScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    // پلنِ standard فعال است → چیپِ «فعال»
    expect(find.widgetWithText(Chip, 'فعال'), findsOneWidget);
    // دو پلنِ دیگر → دکمهٔ «انتخاب»
    expect(find.widgetWithText(FilledButton, 'انتخاب'), findsNWidgets(2));
  });
}
