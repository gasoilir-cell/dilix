import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/earth/earth_screen.dart';

/// کلاینتِ ساختگی: `GET /api/v1/earth/users` یک لیستِ خالیِ کاربران برمی‌گرداند
/// (شکلِ `{"users": []}` که `earthUsers` انتظار دارد).
ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async {
    return http.Response('{"users": []}', 200,
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
  testWidgets('کره بدونِ کرش رندر می‌شود و نوارِ جستجو را دارد', (tester) async {
    await tester.pumpWidget(_wrap(const EarthScreen(), _fakeApi()));
    // فراخوانیِ اولیهٔ جستجو (postFrameCallback) و بازگشتِ پاسخ.
    await tester.pump();
    await tester.pump();

    // در محیطِ تست WebView در دسترس نیست؛ مسیرِ fallbackِ گرادیانی نمایان است.
    expect(find.text('🌍'), findsOneWidget);

    // نوارِ جستجوی شناور با فیلدِ متنیِ جستجو.
    expect(
      find.widgetWithText(TextField, 'جستجوی نام یا Earth ID…'),
      findsOneWidget,
    );
  });

  testWidgets('آیکونِ کره و FABِ دستیار حاضرند', (tester) async {
    await tester.pumpWidget(_wrap(const EarthScreen(), _fakeApi()));
    await tester.pump();
    await tester.pump();

    // آیکونِ کره در نوارِ جستجو + FABِ دستیارِ هوشمند.
    expect(find.byIcon(Icons.public), findsOneWidget);
    expect(find.widgetWithIcon(FloatingActionButton, Icons.smart_toy),
        findsOneWidget);

    // شیتِ کشویی حذف شده است — نباید DraggableScrollableSheet وجود داشته باشد.
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });
}
