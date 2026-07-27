import 'dart:math' as math;

/// ریاضیِ ماتریسِ رنگِ ۵×۴ و پریست‌های فیلتر.
///
/// این فایل از `media_editor_screen.dart` بیرون کشیده شد تا استودیوی استیکر
/// همان فیلترها را داشته باشد. اگر کپی می‌شد، دو نسخه به‌مرور از هم فاصله
/// می‌گرفتند و «گرمِ» ویرایشگر با «گرمِ» استیکر یکی نبود.
///
/// مقادیر عمداً با `filter` در CSS وب یکسان‌اند تا خروجیِ وب و موبایل یک شکل
/// باشد (`MediaEditor.tsx` و `StickerStudio.tsx`).

const List<double> kIdentityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// ترکیبِ دو ماتریسِ ۵×۴ رنگ: اول `b` اعمال می‌شود بعد `a`.
List<double> mulMatrix(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      if (col == 4) sum += a[row * 5 + 4];
      out[row * 5 + col] = sum;
    }
  }
  return out;
}

List<double> saturateMatrix(double s) => <double>[
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

List<double> brightnessMatrix(double b) => <double>[
      b, 0, 0, 0, 0, //
      0, b, 0, 0, 0, //
      0, 0, b, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

/// کنتراست حولِ خاکستریِ میانی (۱۲۸) می‌چرخد، نه حولِ سیاه.
List<double> contrastMatrix(double c) {
  final t = 128.0 * (1 - c);
  return <double>[
    c, 0, 0, 0, t, //
    0, c, 0, 0, t, //
    0, 0, c, 0, t, //
    0, 0, 0, 1, 0, //
  ];
}

/// گرمی: قرمز را بالا و آبی را پایین می‌برد (یا برعکس برای مقدارِ منفی).
List<double> warmthMatrix(double w) {
  final d = 28.0 * w;
  return <double>[
    1, 0, 0, 0, d, //
    0, 1, 0, 0, d * 0.25, //
    0, 0, 1, 0, -d, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> sepiaMatrix(double a) {
  final i = 1 - a;
  return <double>[
    0.393 + 0.607 * i, 0.769 - 0.769 * i, 0.189 - 0.189 * i, 0, 0, //
    0.349 - 0.349 * i, 0.686 + 0.314 * i, 0.168 - 0.168 * i, 0, 0, //
    0.272 - 0.272 * i, 0.534 - 0.534 * i, 0.131 + 0.869 * i, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> hueRotateMatrix(double deg) {
  final r = deg * math.pi / 180.0;
  final c = math.cos(r), s = math.sin(r);
  return <double>[
    0.213 + c * 0.787 - s * 0.213,
    0.715 - c * 0.715 - s * 0.715,
    0.072 - c * 0.072 + s * 0.928,
    0, 0, //
    0.213 - c * 0.213 + s * 0.143,
    0.715 + c * 0.285 + s * 0.140,
    0.072 - c * 0.072 - s * 0.283,
    0, 0, //
    0.213 - c * 0.213 - s * 0.787,
    0.715 - c * 0.715 + s * 0.715,
    0.072 + c * 0.928 + s * 0.072,
    0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

class FilterPreset {
  const FilterPreset(this.id, this.label, this.matrix);
  final String id;

  /// برچسبِ خام (فارسی). صداکردنِ `tr()` اینجا انجام نمی‌شود چون این فهرست
  /// `final` سطحِ‌بالا است و پیش از آماده‌شدنِ کاتالوگِ ترجمه ساخته می‌شود.
  final String label;
  final List<double> matrix;
}

/// همان ۷ فیلترِ وب، به همان ترتیب.
final List<FilterPreset> kFilterPresets = <FilterPreset>[
  const FilterPreset('none', 'عادی', kIdentityMatrix),
  FilterPreset('mono', 'سیاه‌سفید', saturateMatrix(0)),
  FilterPreset('warm', 'گرم', mulMatrix(saturateMatrix(1.5), sepiaMatrix(0.4))),
  FilterPreset(
      'cool', 'سرد', mulMatrix(saturateMatrix(1.2), hueRotateMatrix(180))),
  FilterPreset(
    'vintage',
    'قدیمی',
    mulMatrix(brightnessMatrix(1.1),
        mulMatrix(contrastMatrix(0.9), sepiaMatrix(0.6))),
  ),
  FilterPreset(
      'bright', 'روشن', mulMatrix(saturateMatrix(1.2), brightnessMatrix(1.3))),
  FilterPreset(
      'punch', 'کنتراست', mulMatrix(saturateMatrix(1.3), contrastMatrix(1.4))),
];
