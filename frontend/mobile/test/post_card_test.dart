import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:dilix_mobile/app.dart';
import 'package:dilix_mobile/core/api_client.dart';
import 'package:dilix_mobile/core/earth_focus.dart';
import 'package:dilix_mobile/features/feed/post_card.dart';
import 'package:dilix_mobile/models/models.dart';

ApiClient _fakeApi() {
  final mock = MockClient((http.Request req) async =>
      http.Response('{}', 200, headers: {'content-type': 'application/json'}));
  return ApiClient(client: mock, baseUrl: 'http://test.local');
}

Widget _wrap(Widget child) => ApiScope(
      api: _fakeApi(),
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

Post _post({double? lat, double? lng, String? placeName}) => Post(
      id: 'p1',
      authorEarthId: 'EID-1',
      authorName: 'سارا',
      postType: 'text',
      content: 'سلام از تهران',
      media: const [],
      reactionCounts: const {'like': 2},
      commentCount: 1,
      placeName: placeName,
      lat: lat,
      lng: lng,
    );

void main() {
  setUp(() {
    EarthFocus.request.value = null;
    EarthFocus.openEarthTab = null;
  });

  testWidgets('پستِ بدونِ موقعیت چیپِ کره ندارد', (tester) async {
    await tester.pumpWidget(_wrap(PostCard(post: _post())));
    await tester.pump();

    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('چیپِ موقعیت نامِ مکان را نشان می‌دهد و کره را متمرکز می‌کند',
      (tester) async {
    var openedEarth = false;
    EarthFocus.openEarthTab = () => openedEarth = true;

    await tester.pumpWidget(_wrap(PostCard(
      post: _post(lat: 35.7, lng: 51.4, placeName: 'برجِ آزادی'),
    )));
    await tester.pump();

    expect(find.widgetWithText(ActionChip, 'برجِ آزادی'), findsOneWidget);

    await tester.tap(find.byType(ActionChip));
    await tester.pump();

    expect(openedEarth, isTrue);
    expect(EarthFocus.request.value?.lat, 35.7);
    expect(EarthFocus.request.value?.lng, 51.4);
  });

  testWidgets('بدونِ نامِ مکان، چیپ برچسبِ پیش‌فرض دارد', (tester) async {
    await tester.pumpWidget(_wrap(PostCard(post: _post(lat: 1, lng: 2))));
    await tester.pump();

    expect(find.widgetWithText(ActionChip, 'دیدن روی کره'), findsOneWidget);
  });
}
