import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/features/call/call_screen.dart';
import 'package:dilix_mobile/features/call/call_service.dart';

/// کلاینتِ ساختگی و احرازنشده تا `CallService.init()` تلاشی برای اتصالِ
/// WebSocket نکند (accessToken == null → _ensureSocket زود برمی‌گردد).
ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async {
    return http.Response('[]', 200,
        headers: {'content-type': 'application/json'});
  });
  return ApiClient(client: mock, baseUrl: 'http://test.local');
}

/// overlayِ سراسریِ تماس را همانندِ `app.dart` بازسازی می‌کند: وقتی فازِ تماس
/// از idle خارج شود، `CallScreen` روی محتوای اپ نمایش داده می‌شود.
Widget _wrap(CallService call) {
  return CallScope(
    call: call,
    child: MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return ListenableBuilder(
          listenable: call,
          builder: (context, _) {
            return Stack(
              children: [
                if (child != null) child,
                if (call.phase != CallPhase.idle)
                  Positioned.fill(child: CallScreen(service: call)),
              ],
            );
          },
        );
      },
      home: const Scaffold(body: Center(child: Text('خانه'))),
    ),
  );
}

void main() {
  testWidgets('در فازِ idle هیچ overlayِ تماسی نمایش داده نمی‌شود',
      (tester) async {
    final call = CallService(_fakeApi());
    await tester.pumpWidget(_wrap(call));
    await tester.pump();

    expect(find.text('خانه'), findsOneWidget);
    expect(find.byType(CallScreen), findsNothing);

  });

  testWidgets('تماسِ ورودی overlay با دکمه‌های پاسخ و رد را نشان می‌دهد',
      (tester) async {
    final call = CallService(_fakeApi());
    await tester.pumpWidget(_wrap(call));

    call.debugSetPhase(CallPhase.incoming, peerName: 'کاربرِ نمونه');
    await tester.pump();

    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('کاربرِ نمونه'), findsOneWidget);
    expect(find.text('تماسِ ورودی'), findsOneWidget);
    // دکمه‌های پذیرش (call) و رد (call_end).
    expect(find.byIcon(Icons.call), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);

  });

  testWidgets('ردِ تماسِ ورودی، overlay را می‌بندد و به فازِ idle برمی‌گردد',
      (tester) async {
    final call = CallService(_fakeApi());
    await tester.pumpWidget(_wrap(call));

    call.debugSetPhase(CallPhase.incoming, peerName: 'کاربرِ نمونه');
    await tester.pump();
    expect(find.byType(CallScreen), findsOneWidget);

    // لمسِ دکمهٔ رد (call_end) → _teardown → فاز idle → overlay محو می‌شود.
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();

    expect(call.phase, CallPhase.idle);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('خانه'), findsOneWidget);

  });

  testWidgets('تماسِ برقرار وضعیتِ «برقرار» و کنترل‌های فعال را نشان می‌دهد',
      (tester) async {
    final call = CallService(_fakeApi());
    await tester.pumpWidget(_wrap(call));

    call.debugSetPhase(CallPhase.active,
        peerName: 'کاربرِ نمونه', media: CallMedia.audio);
    await tester.pump();

    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.text('برقرار'), findsOneWidget);
    // کنترل‌های فعال: میوت (mic) و قطع (call_end)؛ پذیرش (call) نباید باشد.
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
    expect(find.byIcon(Icons.call), findsNothing);

  });
}
