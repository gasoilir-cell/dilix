import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/notifications/notifications_screen.dart';

/// کلاینتِ ساختگی: فهرستِ اعلان‌ها را با JSON حداقلی (یک خوانده‌نشده) پاسخ
/// می‌دهد و مسیرِ علامت‌گذاری را ۲۰۴ برمی‌گرداند (بدونِ شبکه).
ApiClient _fakeApi() {
  final items = jsonEncode([
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'channel': 'system',
      'title': 'سفارشِ جدید',
      'body': 'یک سفارشِ تازه ثبت شد',
      'read': false,
      'created_at': '2026-07-18T10:00:00Z',
    },
  ]);

  final mock = MockClient((http.Request req) async {
    final path = req.url.path;
    if (path.contains('/read')) {
      return http.Response('', 204);
    }
    if (path.contains('/v1/notifications')) {
      return http.Response(items, 200,
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
  testWidgets('عنوانِ اعلان‌ها و آیتمِ موکِ API نمایش داده می‌شوند',
      (tester) async {
    await tester.pumpWidget(_wrap(const NotificationsScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('اعلان‌ها'), findsOneWidget);
    expect(find.text('سفارشِ جدید'), findsOneWidget);
    expect(find.text('یک سفارشِ تازه ثبت شد'), findsOneWidget);
    // چیپِ «جدید» برای اعلانِ خوانده‌نشده + دکمهٔ «خواندنِ همه»
    expect(find.text('جدید'), findsOneWidget);
    expect(find.textContaining('خواندنِ همه'), findsOneWidget);
  });

  testWidgets('لمسِ اعلان خوانده‌نشده آن را خوانده می‌کند (چیپِ جدید حذف می‌شود)',
      (tester) async {
    await tester.pumpWidget(_wrap(const NotificationsScreen(), _fakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('جدید'), findsOneWidget);
    await tester.tap(find.text('سفارشِ جدید'));
    await tester.pumpAndSettle();
    expect(find.text('جدید'), findsNothing);
  });
}
