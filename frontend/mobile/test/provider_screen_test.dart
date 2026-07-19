import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/provider/provider_screen.dart';

/// کلاینتِ ساختگی: مسیرهای پرووایدر و هویت را با JSON حداقلی و بقیه را با
/// آرایه‌ی خالی پاسخ می‌دهد (بدونِ شبکه). صفحهٔ ProviderScreen در رندرِ اولیه
/// هیچ درخواستی نمی‌زند؛ این کلاینت برای امنیت است تا هیچ فراخوانی به شبکهٔ
/// واقعی نرود.
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
  testWidgets('رندرِ اولیه فرمِ KYB و گزینه‌های نوعِ ارائه‌دهنده را نشان می‌دهد',
      (tester) async {
    await tester.pumpWidget(_wrap(const ProviderScreen(), _fakeApi()));
    await tester.pump();

    // عنوان و کارتِ ثبت‌نام
    expect(find.text('پورتالِ ارائه‌دهنده'), findsOneWidget);
    expect(find.text('ثبت‌نامِ ارائه‌دهنده (KYB)'), findsOneWidget);
    expect(find.text('نامِ حقوقی'), findsOneWidget);

    // مقدارِ پیش‌فرضِ نوع (psp) در دراپ‌داون نمایش داده می‌شود
    expect(find.text('شرکتِ پرداخت (PSP)'), findsWidgets);

    // بازکردنِ دراپ‌داون → سایرِ گزینه‌های نوعِ مجازِ dilix-api باید ظاهر شوند
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('شرکتِ بیمه'), findsOneWidget);
    expect(find.text('بانک'), findsOneWidget);
    expect(find.text('کارگزاری'), findsOneWidget);
    expect(find.text('سایرِ خدمات‌دهنده'), findsOneWidget);
  });

  testWidgets('دکمهٔ ثبت‌نام و فیلدِ ورودی و دراپ‌داون وجود دارند',
      (tester) async {
    await tester.pumpWidget(_wrap(const ProviderScreen(), _fakeApi()));
    await tester.pump();

    // دکمهٔ ثبت‌نام
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('ثبت‌نام'), findsOneWidget);

    // دو فیلدِ متنی (نامِ حقوقی + کدِ مجوز) + یک دراپ‌داونِ نوع
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });
}
