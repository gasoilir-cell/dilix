import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/investment/investment_screen.dart';

/// کلاینتِ ساختگی: فهرستِ موقعیت‌ها (`investmentPositions`) را با آرایه‌ی خالی
/// پاسخ می‌دهد تا صفحه بدونِ خطا از حالتِ بارگذاری خارج شود.
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
  testWidgets('سرمایه‌گذاری بدونِ خطا رندر می‌شود و کارتِ خرید را دارد',
      (tester) async {
    await tester.pumpWidget(_wrap(const InvestmentScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('سرمایه‌گذاری'), findsOneWidget);
    expect(find.text('خریدِ واحدِ صندوق'), findsOneWidget);
    expect(find.text('موقعیت‌های من'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'خرید'), findsOneWidget);
  });
}
