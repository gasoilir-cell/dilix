import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/discovery/discovery_screen.dart';

/// کلاینتِ ساختگی: کشفِ اطراف در شروع درخواستی نمی‌زند (فقط هنگامِ جستجو).
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
  testWidgets('کشفِ اطراف بدونِ خطا رندر می‌شود و فرمِ جستجو را دارد',
      (tester) async {
    await tester.pumpWidget(_wrap(const DiscoveryScreen(), _fakeApi()));
    await tester.pump();

    expect(find.text('کشفِ اطراف'), findsOneWidget);
    expect(find.textContaining('یافتنِ افراد و کسب‌وکارهای نزدیک'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'جستجو'), findsOneWidget);
  });
}
