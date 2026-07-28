import 'dart:convert';
import 'dart:math' as math;

import 'package:dilix_mobile/core/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// نسبتِ کنتراستِ WCAG 2.1 بینِ دو رنگِ مات.
///
/// عمداً دوباره پیاده شده و از `Color.computeLuminance` استفاده نمی‌کند: هدفِ
/// این تست *قفل‌کردنِ خودِ فرمولِ استاندارد* روی مقادیرِ پالت است، نه بازتابِ
/// هر تغییری که ممکن است در پیاده‌سازیِ فریم‌ورک بیفتد.
double _contrast(Color a, Color b) {
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  final l1 = luminance(a);
  final l2 = luminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('فونتِ Vazirmatn واقعاً در بستهٔ اپ ثبت شده است', () async {
    // ⚠ این تست برای یک باگِ *بی‌صدا* نوشته شده: تم `fontFamily: 'Vazirmatn'`
    // را اعلام می‌کرد ولی `pubspec.yaml` هیچ بلوکِ `fonts:` نداشت، پس Flutter
    // بی‌هیچ خطایی به فونتِ سیستم برمی‌گشت. تنها راهِ گرفتنش، خواندنِ خودِ
    // مانیفستِ ساخته‌شده است — نه خواندنِ رشتهٔ داخلِ تم.
    final manifest = await rootBundle.loadString('FontManifest.json');
    final families = (jsonDecode(manifest) as List)
        .map((e) => (e as Map)['family'] as String)
        .toSet();
    expect(families, contains('Vazirmatn'));

    final entry = (jsonDecode(manifest) as List)
        .firstWhere((e) => (e as Map)['family'] == 'Vazirmatn') as Map;
    final weights = (entry['fonts'] as List)
        .map((f) => (f as Map)['weight'] as int)
        .toSet();
    expect(weights, containsAll(<int>[400, 500, 600, 700]));
  });

  test('تمِ روشن و تیره هر دو از Vazirmatn استفاده می‌کنند', () {
    for (final theme in [DilixTheme.light(), DilixTheme.dark()]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Vazirmatn');
      expect(theme.textTheme.titleLarge?.fontFamily, 'Vazirmatn');
    }
  });

  test('مقیاسِ تایپ برای فارسی فاصلهٔ حرفیِ صفر دارد', () {
    // فاصلهٔ حرفیِ مثبت اتصالِ حروفِ فارسی را می‌شکند.
    final text = DilixTheme.light().textTheme;
    for (final style in [
      text.displaySmall,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
    ]) {
      expect(style?.letterSpacing, 0);
    }
  });

  test('جفت‌های رنگِ متن/زمینه کفِ ۴.۵:۱ را در هر دو تم رد می‌کنند', () {
    for (final theme in [DilixTheme.light(), DilixTheme.dark()]) {
      final s = theme.colorScheme;
      final semantic = DilixSemanticColors.of(s.brightness);
      final pairs = <String, (Color, Color)>{
        'onSurface/surface': (s.onSurface, s.surface),
        'onSurface/scaffold': (s.onSurface, theme.scaffoldBackgroundColor),
        'onSurfaceVariant/scaffold': (
          s.onSurfaceVariant,
          theme.scaffoldBackgroundColor,
        ),
        'onSurfaceVariant/containerHigh': (
          s.onSurfaceVariant,
          s.surfaceContainerHigh,
        ),
        'primary/surface': (s.primary, s.surface),
        'onPrimary/primary': (s.onPrimary, s.primary),
        'onPrimaryContainer/primaryContainer': (
          s.onPrimaryContainer,
          s.primaryContainer,
        ),
        'onSecondaryContainer/secondaryContainer': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
        'onTertiaryContainer/tertiaryContainer': (
          s.onTertiaryContainer,
          s.tertiaryContainer,
        ),
        'error/surface': (s.error, s.surface),
        'onErrorContainer/errorContainer': (
          s.onErrorContainer,
          s.errorContainer,
        ),
        'onInverseSurface/inverseSurface': (
          s.onInverseSurface,
          s.inverseSurface,
        ),
        'success/surface': (semantic.success, s.surface),
        'warning/surface': (semantic.warning, s.surface),
        'onSuccessContainer/successContainer': (
          semantic.onSuccessContainer,
          semantic.successContainer,
        ),
        'onWarningContainer/warningContainer': (
          semantic.onWarningContainer,
          semantic.warningContainer,
        ),
        'onInfoContainer/infoContainer': (
          semantic.onInfoContainer,
          semantic.infoContainer,
        ),
      };
      pairs.forEach((name, pair) {
        expect(
          _contrast(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '$name در تمِ ${s.brightness.name} زیرِ ۴.۵:۱ است',
        );
      });

      // خط/مرز متن نیست، پس کفش ۳:۱ است.
      expect(
        _contrast(s.outline, s.surface),
        greaterThanOrEqualTo(3.0),
        reason: 'outline در تمِ ${s.brightness.name} زیرِ ۳:۱ است',
      );
    }
  });

  test('افزونهٔ رنگ‌های معنایی روی هر دو تم سوار است', () {
    for (final theme in [DilixTheme.light(), DilixTheme.dark()]) {
      expect(theme.extension<DilixSemanticColors>(), isNotNull);
    }
  });
}
