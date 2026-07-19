import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/wallet/wallet_screen.dart';

/// کلاینتِ ساختگی: کیفِ پاداش را با یک موجودیِ IRR پاسخ می‌دهد؛ لینکِ دعوت و
/// سهم از درآمد اختیاری‌اند و آرایه‌ی خالی (پارس‌نشدنی) عمداً به‌عنوانِ «نبود»
/// در همان try/catch صفحه هندل می‌شود.
ApiClient _fakeApi() {
  final wallet = jsonEncode({
    'id': 'w1',
    'currency': 'IRR',
    'balance_available': 50000,
    'balance_escrow': 0,
    'balance_bonus': 0,
    'is_frozen': false,
  });

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/api/v1/wallet/')) {
      return http.Response(wallet, 200,
          headers: {'content-type': 'application/json'});
    }
    if (path.contains('/api/v1/referral/stats')) {
      return http.Response(
          jsonEncode({'code': 'DLX-TEST', 'link': 'https://d.lix/DLX-TEST', 'total_referred': 3}),
          200,
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
  testWidgets('کیفِ پول بدونِ خطا رندر می‌شود و کارت‌های اصلی را دارد',
      (tester) async {
    await tester.pumpWidget(_wrap(const WalletScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('کیف پول'), findsOneWidget);
    expect(find.text('موجودیِ پاداش'), findsOneWidget);
    expect(find.text('انتقالِ امن'), findsOneWidget);

    // کارتِ لینکِ دعوت پایینِ ListView است و در ویوپورتِ پیش‌فرضِ تست ساخته
    // نمی‌شود تا اسکرول شود.
    await tester.dragUntilVisible(
      find.text('لینکِ دعوت'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('لینکِ دعوت'), findsOneWidget);
  });
}
