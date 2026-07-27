import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dilix_mobile/features/assistant/mini_markdown.dart';

/// متنِ یک span به‌همراه اینکه پررنگ است یا نه.
List<(String, bool)> _parts(String src) => boldSpans(src)
    .cast<TextSpan>()
    .map((s) => (s.text ?? '', s.style?.fontWeight == FontWeight.bold))
    .toList();

void main() {
  test('تأکیدِ مارک‌داونی پررنگ می‌شود و ستاره‌ها حذف می‌شوند', () {
    expect(_parts('نرخ **۱۲۰٬۰۰۰** تومان'), [
      ('نرخ ', false),
      ('۱۲۰٬۰۰۰', true),
      (' تومان', false),
    ]);
  });

  test('چند تأکید در یک متن', () {
    expect(_parts('**الف** و **ب**'), [
      ('الف', true),
      (' و ', false),
      ('ب', true),
    ]);
  });

  test('متنِ بدونِ تأکید دست‌نخورده می‌مانَد', () {
    expect(_parts('سلام دنیا'), [('سلام دنیا', false)]);
  });

  test('ستارهٔ باز‌نشده متن را خراب نمی‌کند', () {
    expect(_parts('۲ ** ۳'), [('۲ ** ۳', false)]);
  });
}
