import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dilix_mobile/core/app_lock.dart';
import 'package:dilix_mobile/features/auth/lock_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLock.instance.resetForTest();
  });

  group('AppLock', () {
    test('اپ با تنظیمِ روشن، قفل‌شده بالا می‌آید', () async {
      SharedPreferences.setMockInitialValues({'dilix.app_lock': true});
      await AppLock.instance.load();
      expect(AppLock.instance.enabled, isTrue);
      // مهم‌ترین ادعای این قابلیت: اولین فریم نباید محتوای حساب را نشان بدهد.
      expect(AppLock.instance.locked, isTrue);
    });

    test('بدونِ تنظیمِ ذخیره‌شده، هیچ قفلی اعمال نمی‌شود', () async {
      await AppLock.instance.load();
      expect(AppLock.instance.enabled, isFalse);
      expect(AppLock.instance.locked, isFalse);
    });

    test('روشن‌کردنِ قفل بدونِ احرازِ موفق انجام نمی‌شود', () async {
      AppLock.instance.authenticator = (_) async => false;
      final ok = await AppLock.instance.setEnabled(true);
      expect(ok, isFalse);
      expect(AppLock.instance.enabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dilix.app_lock'), isNull);
    });

    test('روشن‌کردن پس از احرازِ موفق پایدار می‌شود', () async {
      AppLock.instance.authenticator = (_) async => true;
      expect(await AppLock.instance.setEnabled(true), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dilix.app_lock'), isTrue);
      expect(AppLock.instance.locked, isFalse);
    });

    test('خاموش‌کردنِ قفل هم احراز می‌خواهد', () async {
      AppLock.instance.authenticator = (_) async => true;
      await AppLock.instance.setEnabled(true);
      // هرکسی که گوشیِ بازِ کاربر را در دست دارد نباید بتواند قفل را بردارد.
      AppLock.instance.authenticator = (_) async => false;
      expect(await AppLock.instance.setEnabled(false), isFalse);
      expect(AppLock.instance.enabled, isTrue);
    });

    test('unlock فقط با احرازِ موفق قفل را برمی‌دارد', () async {
      SharedPreferences.setMockInitialValues({'dilix.app_lock': true});
      await AppLock.instance.load();
      AppLock.instance.authenticator = (_) async => false;
      expect(await AppLock.instance.unlock(), isFalse);
      expect(AppLock.instance.locked, isTrue);

      AppLock.instance.authenticator = (_) async => true;
      expect(await AppLock.instance.unlock(), isTrue);
      expect(AppLock.instance.locked, isFalse);
    });

    test('خروج از حساب قفل را کاملاً برمی‌دارد (راهِ فرار)', () async {
      SharedPreferences.setMockInitialValues({'dilix.app_lock': true});
      await AppLock.instance.load();
      await AppLock.instance.clearForLogout();
      expect(AppLock.instance.enabled, isFalse);
      expect(AppLock.instance.locked, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dilix.app_lock'), isNull);
    });

    test('بازگشتِ سریع از پس‌زمینه قفل نمی‌کند', () async {
      AppLock.instance.authenticator = (_) async => true;
      await AppLock.instance.setEnabled(true);
      AppLock.instance.onPaused();
      AppLock.instance.onResumed(); // خیلی کمتر از grace
      expect(AppLock.instance.locked, isFalse);
    });

    test('بدونِ pause، resume تنها قفل نمی‌کند', () async {
      AppLock.instance.authenticator = (_) async => true;
      await AppLock.instance.setEnabled(true);
      AppLock.instance.onResumed();
      expect(AppLock.instance.locked, isFalse);
    });
  });

  group('LockScreen', () {
    testWidgets('به‌محضِ باز شدن یک‌بار خودکار احراز می‌خواهد', (tester) async {
      SharedPreferences.setMockInitialValues({'dilix.app_lock': true});
      await AppLock.instance.load();
      var calls = 0;
      AppLock.instance.authenticator = (_) async {
        calls++;
        return true;
      };

      await tester.pumpWidget(MaterialApp(
        home: LockScreen(onLogout: () async {}),
      ));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(AppLock.instance.locked, isFalse);
    });

    testWidgets('احرازِ ناموفق پیامِ خطا و دکمهٔ تلاشِ دوباره می‌دهد',
        (tester) async {
      SharedPreferences.setMockInitialValues({'dilix.app_lock': true});
      await AppLock.instance.load();
      var calls = 0;
      AppLock.instance.authenticator = (_) async {
        calls++;
        return false;
      };

      await tester.pumpWidget(MaterialApp(
        home: LockScreen(onLogout: () async {}),
      ));
      await tester.pumpAndSettle();

      expect(find.text('هویت تأیید نشد. دوباره تلاش کنید.'), findsOneWidget);
      expect(AppLock.instance.locked, isTrue);

      await tester.tap(find.text('باز کردن'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });

    testWidgets('خروج از حساب فقط پس از تأییدِ کاربر انجام می‌شود',
        (tester) async {
      SharedPreferences.setMockInitialValues({'dilix.app_lock': true});
      await AppLock.instance.load();
      AppLock.instance.authenticator = (_) async => false;
      var loggedOut = false;

      await tester.pumpWidget(MaterialApp(
        home: LockScreen(onLogout: () async => loggedOut = true),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'خروج از حساب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('انصراف'));
      await tester.pumpAndSettle();
      expect(loggedOut, isFalse);

      await tester.tap(find.widgetWithText(TextButton, 'خروج از حساب'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'خروج'));
      await tester.pumpAndSettle();
      expect(loggedOut, isTrue);
    });
  });
}
