import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/shell/home_shell.dart';

/// کلاینتِ ساختگی که همه‌ی درخواست‌ها را با آرایه‌ی خالی پاسخ می‌دهد (بدونِ شبکه).
ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async {
    return http.Response('[]', 200, headers: {'content-type': 'application/json'});
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
  testWidgets('پوسته‌ی اصلی ۵ مقصدِ ناوبری را نشان می‌دهد', (tester) async {
    await tester.pumpWidget(_wrap(const HomeShell(), _fakeApi()));
    await tester.pump();

    expect(find.text('خانه'), findsWidgets);
    expect(find.text('کره'), findsOneWidget);
    expect(find.text('پیام‌ها'), findsOneWidget);
    expect(find.text('خدمات'), findsOneWidget);
    expect(find.text('من'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('فیدِ خالی پیامِ مناسب نشان می‌دهد', (tester) async {
    await tester.pumpWidget(_wrap(const HomeShell(), _fakeApi()));
    await tester.pumpAndSettle();
    expect(find.text('هنوز پستی نیست.'), findsOneWidget);
  });
}
