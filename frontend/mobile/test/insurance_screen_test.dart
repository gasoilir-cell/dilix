import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/insurance/insurance_screen.dart';

/// کلاینتِ ساختگی: صفحهٔ بیمه در شروع هیچ درخواستی نمی‌زند (فقط هنگامِ استعلام)،
/// پس پاسخِ پیش‌فرضِ خالی کافی است.
ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async {
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
    await tester.pump();

    expect(find.text('بیمه'), findsOneWidget);
    expect(find.text('استعلامِ بیمه'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'استعلام'), findsOneWidget);
  });
}
