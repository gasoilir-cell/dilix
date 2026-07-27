import 'package:flutter_test/flutter_test.dart';

import 'package:dilix_mobile/core/deep_links.dart';

void main() {
  group('بازگشاییِ لینکِ عمیق', () {
    test('لینکِ دعوت کدِ معرف را بزرگ‌حرف برمی‌گرداند', () {
      final a = DeepLinks.parse(Uri.parse('https://dilix.ir/join?ref=ab12cd'));
      expect(a, isNotNull);
      expect(a!.kind, DeepLinkKind.referral);
      expect(a.code, 'AB12CD');
    });

    test('لینکِ دعوتِ بدونِ کد نادیده گرفته می‌شود', () {
      expect(DeepLinks.parse(Uri.parse('https://dilix.ir/join')), isNull);
    });

    test('لینکِ پرداخت با دامنهٔ رسمی بازسازی می‌شود', () {
      final a = DeepLinks.parse(
          Uri.parse('https://www.dilix.ir/pay/DLX-123?a=50000&n=test'));
      expect(a!.kind, DeepLinkKind.pay);
      // سرور میزبانِ بارِ QR را بررسی می‌کند؛ باید dilix.ir باشد نه www.
      expect(a.payUrl, startsWith('https://dilix.ir/pay/DLX-123'));
      expect(a.payUrl, contains('a=50000'));
    });

    test('طرحِ اختصاصی هم به همان نشانیِ کانونی می‌رسد', () {
      final a = DeepLinks.parse(Uri.parse('dilix://pay/DLX-9?a=100'));
      expect(a!.kind, DeepLinkKind.pay);
      expect(a.payUrl, 'https://dilix.ir/pay/DLX-9?a=100');
    });

    test('تمرکزِ کره مختصات را می‌خواند', () {
      final a =
          DeepLinks.parse(Uri.parse('https://dilix.ir/earth?focus=35.7,51.4'));
      expect(a!.kind, DeepLinkKind.earthFocus);
      expect(a.lat, closeTo(35.7, 1e-9));
      expect(a.lng, closeTo(51.4, 1e-9));
    });

    test('مختصاتِ خارج از بازه رد می‌شود', () {
      expect(DeepLinks.parse(Uri.parse('https://dilix.ir/earth?focus=95,51')),
          isNull);
      expect(DeepLinks.parse(Uri.parse('https://dilix.ir/earth?focus=abc')),
          isNull);
    });

    test('دامنهٔ بیگانه و مسیرِ ناشناخته به اپ نمی‌آید', () {
      expect(DeepLinks.parse(Uri.parse('https://evil.example/join?ref=X')),
          isNull);
      expect(DeepLinks.parse(Uri.parse('https://dilix.ir/wallet')), isNull);
    });
  });
}
