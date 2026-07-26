import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/wallet/wallet_screen.dart';

/// درخواست‌هایی که کلاینت واقعاً فرستاده، تا قرارداد (مسیر، کوئری، بدنه) سنجیده
/// شود نه فقط خروجیِ پارس‌شده.
late List<http.Request> _seen;

ApiClient _api({
  Map<String, dynamic>? resolveBody,
  int resolveStatus = 200,
}) {
  _seen = [];
  final mock = MockClient((http.Request req) async {
    _seen.add(req);
    final path = req.url.path;
    if (path == '/api/v1/wallet/qr/payload') {
      return http.Response(
        jsonEncode({'payload': 'https://dilix.ir/pay/DLX-ME?a=250000'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == '/api/v1/wallet/qr') {
      return http.Response.bytes(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"><!-- کدِ آزمایشی --></svg>'),
        200,
        headers: {'content-type': 'image/svg+xml'},
      );
    }
    if (path == '/api/v1/wallet/qr/resolve') {
      return http.Response(
        jsonEncode(resolveBody ?? {'detail': 'این کد QR مربوط به دیلیکس نیست'}),
        resolveStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.startsWith('/api/v1/wallet')) {
      return http.Response(
        jsonEncode({
          'id': 'w1',
          'currency': 'IRR',
          'balance_available': 500000,
          'balance_escrow': 0,
          'balance_bonus': 0,
          'is_frozen': false,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('[]', 200,
        headers: {'content-type': 'application/json'});
  });
  return ApiClient(client: mock, baseUrl: 'http://test.local');
}

Widget _wrap(Widget child, ApiClient api) => ApiScope(
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

void main() {
  test('بدونِ مبلغ و یادداشت، کوئریِ اضافه به کدِ QR چسبانده نمی‌شود', () async {
    final api = _api();
    await api.walletQrPayload();
    expect(_seen.single.url.path, '/api/v1/wallet/qr/payload');
    expect(_seen.single.url.query, isEmpty);
  });

  test('مبلغ و یادداشت به کوئریِ کد می‌روند و یادداشت encode می‌شود', () async {
    final api = _api();
    await api.walletQrPayload(amountMinor: 250000, note: 'بابتِ ناهار');
    final url = _seen.single.url;
    // مبلغ ریال است و همان‌طور که داده شده می‌رود؛ تبدیلِ تومان کارِ UI است.
    expect(url.queryParameters['amount'], '250000');
    expect(url.queryParameters['note'], 'بابتِ ناهار');
  });

  test('مبلغِ صفر یا منفی اصلاً فرستاده نمی‌شود', () async {
    final api = _api();
    await api.walletQrPayload(amountMinor: 0);
    expect(_seen.single.url.query, isEmpty);
  });

  test('SVG به‌صورتِ UTF-8 خوانده می‌شود (نه latin-1)', () async {
    final api = _api();
    final svg = await api.walletQrSvg();
    expect(svg, contains('کدِ آزمایشی'));
    expect(svg, startsWith('<svg'));
  });

  test('پاسخِ resolve به مقصدِ پرداخت نگاشت می‌شود', () async {
    final api = _api(resolveBody: {
      'earth_id': 'DLX-SHOP1',
      'display_name': 'کافه دیلیکس',
      'avatar_url': null,
      'amount': 250000,
      'note': 'بابتِ ناهار',
      'is_self': false,
    });
    final target = await api.resolveWalletQr('https://dilix.ir/pay/DLX-SHOP1?a=250000');
    expect(target.earthId, 'DLX-SHOP1');
    expect(target.displayName, 'کافه دیلیکس');
    expect(target.amountMinor, 250000);
    expect(target.isSelf, isFalse);
    expect(jsonDecode(_seen.single.body)['payload'],
        'https://dilix.ir/pay/DLX-SHOP1?a=250000');
  });

  test('کدِ QRِ خودی با پرچمِ is_self برمی‌گردد تا UI پیش از ارسال جلویش را بگیرد',
      () async {
    final api = _api(resolveBody: {
      'earth_id': 'DLX-ME',
      'display_name': 'من',
      'avatar_url': null,
      'amount': null,
      'note': null,
      'is_self': true,
    });
    final target = await api.resolveWalletQr('DLX-ME');
    expect(target.isSelf, isTrue);
    // بدونِ مبلغ در کد، UI باید فیلد را باز بگذارد.
    expect(target.amountMinor, isNull);
  });

  test('ردِ کدِ دامنه‌ی غریبه به‌صورتِ ApiException بالا می‌آید', () async {
    final api = _api(resolveStatus: 400);
    await expectLater(
      api.resolveWalletQr('https://evil.example/pay/DLX-SHOP1'),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('کیفِ پول هر دو ورودیِ QR (اسکن و دریافت) را نشان می‌دهد',
      (tester) async {
    await tester.pumpWidget(_wrap(const WalletScreen(), _api()));
    await tester.pumpAndSettle();

    expect(find.text('اسکن و پرداخت'), findsOneWidget);
    expect(find.text('دریافت با QR'), findsOneWidget);
  });
}
