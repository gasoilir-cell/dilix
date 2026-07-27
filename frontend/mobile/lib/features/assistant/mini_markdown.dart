import 'package:flutter/widgets.dart';

/// مدلِ دستیار پاسخ‌ها را با تأکیدِ مارک‌داونی (`**…**`) برمی‌گرداند و وب همان
/// را پررنگ رندر می‌کند. موبایل تا پیش از این متنِ خام را نشان می‌داد و ستاره‌ها
/// وسطِ جمله دیده می‌شدند.
///
/// عمداً فقط **همین یک قاعده** پیاده شده است؛ آوردنِ یک موتورِ کاملِ مارک‌داون
/// برای چیزی که سرور تولید می‌کند بیش از نیاز است.
final _boldPattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);

/// شکستنِ متن به بخش‌های ساده و پررنگ.
List<InlineSpan> boldSpans(String text) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final m in _boldPattern.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    spans.add(TextSpan(
      text: m.group(1),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

/// متنی که `**…**` را پررنگ نشان می‌دهد و بقیه را دست‌نخورده می‌گذارد.
class MiniMarkdownText extends StatelessWidget {
  const MiniMarkdownText(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(style: style, children: boldSpans(data)));
  }
}
