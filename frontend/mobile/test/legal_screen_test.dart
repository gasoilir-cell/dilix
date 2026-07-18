import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/legal/legal_screen.dart';

/// `LegalScreen` ایستا است و به API نیاز ندارد؛ یک کلاینتِ ساختگیِ حداقلی برای
/// هماهنگی با الگوی سایرِ تست‌ها فراهم می‌شود.
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
  testWidgets('عنوان و دو سندِ حقوقی به‌صورتِ آکاردئون نمایش داده می‌شوند',
      (tester) async {
    await tester.pumpWidget(_wrap(const LegalScreen(), _fakeApi()));
    await tester.pump();

    expect(find.text('اسنادِ حقوقی'), findsOneWidget);
    expect(find.text('قوانین و مقررات'), findsOneWidget);
    expect(find.text('حریمِ خصوصی'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNWidgets(2));
  });

  testWidgets('بازکردنِ سندِ قوانین، متنِ حقوقی را نشان می‌دهد',
      (tester) async {
    await tester.pumpWidget(_wrap(const LegalScreen(), _fakeApi()));
    await tester.pump();

    await tester.tap(find.text('قوانین و مقررات'));
    await tester.pumpAndSettle();

    expect(find.textContaining('بسترِ واسط'), findsOneWidget);
  });
}
