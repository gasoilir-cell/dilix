import 'package:flutter/material.dart';

import 'theme.dart';

/// حال‌وهوایِ معناییِ یک وضعیت. صفحه‌ها به‌جای انتخابِ رنگ، *معنا* را اعلام
/// می‌کنند و ترجمهٔ معنا به رنگ یک‌جا اینجا انجام می‌شود.
enum StatusTone { neutral, success, warning, danger, info, accent }

/// نشانِ وضعیت (سفارش، کمپین، برنامهٔ کوچک، …).
///
/// ## چرا این ویجت ساخته شد؟
/// سه صفحه (فروشگاه، تبلیغات، برنامه‌های کوچک) هرکدام یک `_statusColor` جدا
/// داشتند که `Colors.amber`/`Colors.green`/`Colors.redAccent` را با شفافیتِ ۱۵٪
/// پشتِ متنِ عادی می‌گذاشت. دو مشکل داشت: (۱) این رنگ‌های ثابت با پالتِ برند
/// نمی‌خواندند و در تمِ تیره بی‌رمق می‌شدند، (۲) هر صفحه نگاشتِ خودش را داشت پس
/// «در انتظار» در فروشگاه و تبلیغات لزوماً یک رنگ نبود.
///
/// جفت‌های `container`/`onContainer` که اینجا استفاده می‌شوند همگی بالای ۸:۱
/// کنتراست دارند، پس برچسب در هر دو تم خواناست.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.tone = StatusTone.neutral});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = DilixSemanticColors.from(context);
    final (background, foreground) = switch (tone) {
      StatusTone.success => (semantic.successContainer, semantic.onSuccessContainer),
      StatusTone.warning => (semantic.warningContainer, semantic.onWarningContainer),
      StatusTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
      StatusTone.info => (semantic.infoContainer, semantic.onInfoContainer),
      StatusTone.accent => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      StatusTone.neutral => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DilixSpacing.sm,
        vertical: DilixSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DilixRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
