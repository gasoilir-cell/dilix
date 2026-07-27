import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/l10n.dart';
import 'color_matrix.dart';

/// ویرایشگرِ تصویر پیش از ارسال — معادلِ موبایلیِ `MediaEditor.tsx` در وب.
///
/// همه‌چیز با `dart:ui` و `CustomPainter` انجام می‌شود و **هیچ وابستگیِ تازه‌ای**
/// اضافه نمی‌کند: `pub.dev` از محیطِ بیلد در دسترس نیست، پس هر پکیجِ جدید یعنی
/// ریسکِ شکستنِ CI. رمزگذاریِ خروجی PNG است چون Flutter رمزگذارِ JPEG در
/// دسترس نمی‌گذارد؛ با پریست‌های اندازه، خروجی خیلی زیرِ سقفِ ۲۵MBِ سرور می‌ماند.
///
/// خروجی: `File` ویرایش‌شده از طریقِ `Navigator.pop`، یا `null` اگر لغو شود.
class MediaEditorScreen extends StatefulWidget {
  const MediaEditorScreen({super.key, required this.source});

  /// فایلِ تصویرِ ورودی (از گالری یا دوربین).
  final File source;

  @override
  State<MediaEditorScreen> createState() => _MediaEditorScreenState();
}

// ─────────────────────────── مدلِ داده ───────────────────────────

/// یک ضربهٔ قلم. مختصات **نرمال** (۰..۱) نسبت به کادرِ برش‌خورده ذخیره می‌شود
/// تا تغییرِ اندازهٔ پیش‌نمایش یا رزولوشنِ خروجی نقاشی را جابه‌جا نکند.
class _Stroke {
  _Stroke(this.color, this.width);
  final Color color;
  final double width; // نسبت به عرضِ خروجی
  final List<Offset> points = [];
}

enum _TextEffect { stroke, shadow, neon, label, plain }

/// یک لایهٔ متنی. `center` نرمال است و `size` نسبتی از عرضِ خروجی.
class _TextLayer {
  _TextLayer({
    required this.text,
    required this.color,
    required this.effect,
    required this.center,
    required this.size,
    required this.bold,
  });

  String text;
  Color color;
  _TextEffect effect;
  Offset center;
  double size;
  bool bold;
}

class _Adjust {
  double brightness = 1.0;
  double contrast = 1.0;
  double saturate = 1.0;
  double warmth = 0.0; // ‎-1..1
  double blur = 0.0; // ۰..۱ → حداکثر ~۶px

  bool get isDefault =>
      brightness == 1.0 &&
      contrast == 1.0 &&
      saturate == 1.0 &&
      warmth == 0.0 &&
      blur == 0.0;

  void reset() {
    brightness = 1.0;
    contrast = 1.0;
    saturate = 1.0;
    warmth = 0.0;
    blur = 0.0;
  }
}


// ───────────────────────── پریست‌های دیگر ─────────────────────────

class _Ratio {
  const _Ratio(this.label, this.value);
  final String label;
  final double? value; // null = آزاد
}

const List<_Ratio> _ratios = <_Ratio>[
  _Ratio('آزاد', null),
  _Ratio('۱:۱', 1),
  _Ratio('۴:۵', 4 / 5),
  _Ratio('۳:۴', 3 / 4),
  _Ratio('۴:۳', 4 / 3),
  _Ratio('۱۶:۹', 16 / 9),
  _Ratio('۹:۱۶', 9 / 16),
];

class _Preset {
  const _Preset(this.label, this.maxDim);
  final String label;
  final int maxDim; // ۰ = اندازهٔ اصلی
}

const List<_Preset> _presets = <_Preset>[
  _Preset('اصل', 0),
  _Preset('بالا', 1600),
  _Preset('متوسط', 1080),
  _Preset('کوچک', 720),
];

const List<int> _pixelLevels = <int>[0, 64, 28]; // ۰ = خاموش
const List<String> _pixelLabels = <String>['بدون شطرنجی', 'ملایم', 'درشت'];

const List<String> _frames = <String>[
  'none',
  'white',
  'black',
  'gold',
  'polaroid',
  'film',
  'neon'
];
const List<String> _frameLabels = <String>[
  'بدون قاب',
  'سفید',
  'مشکی',
  'طلایی',
  'پولاروید',
  'فیلم',
  'نئون'
];

const List<Color> _palette = <Color>[
  Colors.white,
  Colors.black,
  Color(0xFFF87171),
  Color(0xFF34D399),
  Color(0xFF38BDF8),
  Color(0xFFEC4899),
  Color(0xFFFACC15),
  Color(0xFFA855F7),
  Color(0xFFFB923C),
];

const List<double> _brushWidths = <double>[0.006, 0.013, 0.024];
const List<String> _brushLabels = <String>['نازک', 'متوسط', 'ضخیم'];

// ─────────────────────────── نقاش ───────────────────────────

/// وضعیتی که هم پیش‌نمایش و هم خروجی از آن رندر می‌شود. یک منبعِ حقیقت داشتن
/// تنها راهی است که تضمین می‌کند «چیزی که می‌بینی همان است که ارسال می‌شود».
class _Scene {
  _Scene({
    required this.image,
    required this.crop,
    required this.matrix,
    required this.blurSigma,
    required this.pixelBlocks,
    required this.strokes,
    required this.texts,
    required this.frame,
  });

  final ui.Image image;
  final Rect crop; // نرمال (۰..۱) روی تصویرِ اصلی
  final List<double> matrix;
  final double blurSigma;
  final int pixelBlocks;
  final List<_Stroke> strokes;
  final List<_TextLayer> texts;
  final String frame;
}

void _paintScene(Canvas canvas, Size out, _Scene s) {
  final src = Rect.fromLTWH(
    s.crop.left * s.image.width,
    s.crop.top * s.image.height,
    s.crop.width * s.image.width,
    s.crop.height * s.image.height,
  );
  final dst = Offset.zero & out;

  final paint = Paint()
    ..filterQuality = FilterQuality.high
    ..colorFilter = ColorFilter.matrix(s.matrix);
  if (s.blurSigma > 0) {
    paint.imageFilter = ui.ImageFilter.blur(
      sigmaX: s.blurSigma,
      sigmaY: s.blurSigma,
      tileMode: TileMode.decal,
    );
  }

  if (s.pixelBlocks > 0) {
    // شطرنجی‌سازی: تصویر را در یک لایهٔ کوچک می‌کشیم و بدونِ نرم‌سازی بزرگ
    // می‌کنیم. `FilterQuality.none` همان چیزی است که بلوک‌های تیز می‌سازد.
    final small = math.max(8, s.pixelBlocks).toDouble();
    final ratio = out.height / out.width;
    final sw = small, sh = math.max(4.0, small * ratio);
    canvas.saveLayer(dst, Paint());
    canvas.save();
    canvas.scale(out.width / sw, out.height / sh);
    canvas.drawImageRect(
      s.image,
      src,
      Rect.fromLTWH(0, 0, sw, sh),
      Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = ColorFilter.matrix(s.matrix),
    );
    canvas.restore();
    canvas.restore();
  } else {
    canvas.drawImageRect(s.image, src, dst, paint);
  }

  // ── نقاشی ──
  for (final st in s.strokes) {
    if (st.points.isEmpty) continue;
    final p = Paint()
      ..color = st.color
      ..strokeWidth = st.width * out.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (st.points.length == 1) {
      canvas.drawPoints(
        ui.PointMode.points,
        [Offset(st.points.first.dx * out.width, st.points.first.dy * out.height)],
        p,
      );
      continue;
    }
    final path = Path();
    path.moveTo(st.points.first.dx * out.width, st.points.first.dy * out.height);
    for (var i = 1; i < st.points.length; i++) {
      path.lineTo(st.points[i].dx * out.width, st.points[i].dy * out.height);
    }
    canvas.drawPath(path, p);
  }

  // ── متن ──
  for (final tl in s.texts) {
    _paintText(canvas, out, tl);
  }

  // ── قاب ──
  _paintFrame(canvas, out, s.frame);
}

TextPainter _textPainter(_TextLayer t, double fontSize, {Paint? fg}) {
  final style = TextStyle(
    fontSize: fontSize,
    height: 1.2,
    fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
    color: fg == null ? t.color : null,
    foreground: fg,
  );
  return TextPainter(
    text: TextSpan(text: t.text, style: style),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
  )..layout();
}

void _paintText(Canvas canvas, Size out, _TextLayer t) {
  final fontSize = t.size * out.width;
  final cx = t.center.dx * out.width;
  final cy = t.center.dy * out.height;

  final base = _textPainter(t, fontSize);
  final w = base.width, h = base.height;
  final origin = Offset(cx - w / 2, cy - h / 2);

  switch (t.effect) {
    case _TextEffect.label:
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy), width: w + fontSize * 0.5, height: h + fontSize * 0.25),
        Radius.circular(fontSize * 0.25),
      );
      final lum = t.color.computeLuminance();
      canvas.drawRRect(r, Paint()..color = t.color);
      _textPainter(
        _TextLayer(
          text: t.text,
          color: lum > 0.5 ? Colors.black : Colors.white,
          effect: _TextEffect.plain,
          center: t.center,
          size: t.size,
          bold: t.bold,
        ),
        fontSize,
      ).paint(canvas, origin);
      return;
    case _TextEffect.shadow:
      _textPainter(
        _TextLayer(
          text: t.text,
          color: Colors.black54,
          effect: _TextEffect.plain,
          center: t.center,
          size: t.size,
          bold: t.bold,
        ),
        fontSize,
      ).paint(canvas, origin + Offset(fontSize * 0.06, fontSize * 0.06));
      break;
    case _TextEffect.neon:
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fontSize * 0.16
        ..color = t.color.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize * 0.12);
      _textPainter(t, fontSize, fg: glow).paint(canvas, origin);
      break;
    case _TextEffect.stroke:
      final lum = t.color.computeLuminance();
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fontSize * 0.09
        ..strokeJoin = StrokeJoin.round
        ..color = lum > 0.5 ? Colors.black87 : Colors.white;
      _textPainter(t, fontSize, fg: outline).paint(canvas, origin);
      break;
    case _TextEffect.plain:
      break;
  }
  base.paint(canvas, origin);
}

void _paintFrame(Canvas canvas, Size out, String id) {
  if (id == 'none') return;
  final rect = Offset.zero & out;
  final t = out.shortestSide * 0.03;
  switch (id) {
    case 'white':
    case 'black':
    case 'gold':
      canvas.drawRect(
        rect.deflate(t / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = t
          ..color = id == 'white'
              ? Colors.white
              : id == 'black'
                  ? Colors.black
                  : const Color(0xFFFACC15),
      );
      break;
    case 'polaroid':
      final p = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, out.width, t), p);
      canvas.drawRect(Rect.fromLTWH(0, 0, t, out.height), p);
      canvas.drawRect(Rect.fromLTWH(out.width - t, 0, t, out.height), p);
      canvas.drawRect(
          Rect.fromLTWH(0, out.height - t * 3.2, out.width, t * 3.2), p);
      break;
    case 'film':
      final p = Paint()..color = Colors.black;
      canvas.drawRect(Rect.fromLTWH(0, 0, out.width, t * 1.4), p);
      canvas.drawRect(
          Rect.fromLTWH(0, out.height - t * 1.4, out.width, t * 1.4), p);
      final hole = Paint()..color = Colors.white;
      final step = out.width / 12;
      for (var x = step * 0.35; x < out.width; x += step) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, t * 0.35, step * 0.35, t * 0.7),
              Radius.circular(t * 0.18)),
          hole,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, out.height - t * 1.05, step * 0.35, t * 0.7),
              Radius.circular(t * 0.18)),
          hole,
        );
      }
      break;
    case 'neon':
      canvas.drawRect(
        rect.deflate(t / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = t * 0.6
          ..color = const Color(0xFF38BDF8)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * 0.5),
      );
      canvas.drawRect(
        rect.deflate(t / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = t * 0.25
          ..color = Colors.white,
      );
      break;
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene);
  final _Scene scene;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintScene(canvas, size, scene);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}

// ─────────────────────────── صفحه ───────────────────────────

enum _Tool { move, draw, crop }

class _MediaEditorScreenState extends State<MediaEditorScreen> {
  ui.Image? _image;
  String? _error;
  bool _working = false;

  _Tool _tool = _Tool.move;
  int _filter = 0;
  int _pixel = 0;
  int _frame = 0;
  int _preset = 2; // متوسط
  int _brush = 1;
  Color _color = Colors.white;
  final _Adjust _adj = _Adjust();

  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  int _ratio = 0;

  final List<_Stroke> _strokes = [];
  final List<_TextLayer> _texts = [];
  int? _selected; // اندیسِ لایهٔ متنیِ انتخاب‌شده

  int _tab = 0; // ۰ فیلتر · ۱ تنظیم · ۲ متن · ۳ قاب · ۴ کیفیت

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _image = frame.image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('بازکردنِ تصویر ممکن نشد: {0}', [e]));
    }
  }

  List<double> get _matrix {
    var m = kFilterPresets[_filter].matrix;
    if (_adj.saturate != 1.0) m = mulMatrix(saturateMatrix(_adj.saturate), m);
    if (_adj.contrast != 1.0) m = mulMatrix(contrastMatrix(_adj.contrast), m);
    if (_adj.brightness != 1.0) m = mulMatrix(brightnessMatrix(_adj.brightness), m);
    if (_adj.warmth != 0.0) m = mulMatrix(warmthMatrix(_adj.warmth), m);
    return m;
  }

  _Scene _scene() => _Scene(
        image: _image!,
        crop: _tool == _Tool.crop ? const Rect.fromLTWH(0, 0, 1, 1) : _crop,
        matrix: _matrix,
        blurSigma: _adj.blur * 6.0,
        pixelBlocks: _pixelLevels[_pixel],
        strokes: _strokes,
        texts: _texts,
        frame: _frames[_frame],
      );

  /// نسبتِ عرض به ارتفاعِ خروجی (پس از برش).
  double get _outAspect {
    final im = _image!;
    if (_tool == _Tool.crop) return im.width / im.height;
    return (_crop.width * im.width) / (_crop.height * im.height);
  }

  // ── خروجی ──
  Future<void> _export() async {
    if (_image == null || _working) return;
    setState(() => _working = true);
    try {
      final im = _image!;
      var w = _crop.width * im.width;
      var h = _crop.height * im.height;
      final maxDim = _presets[_preset].maxDim;
      if (maxDim > 0 && math.max(w, h) > maxDim) {
        final k = maxDim / math.max(w, h);
        w *= k;
        h *= k;
      }
      final size = Size(math.max(1.0, w.roundToDouble()), math.max(1.0, h.roundToDouble()));

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Offset.zero & size);
      _paintScene(canvas, size, _scene());
      final pic = rec.endRecording();
      final out = await pic.toImage(size.width.round(), size.height.round());
      pic.dispose();
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (data == null) throw StateError('encode failed');

      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/dilix_edit_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      Navigator.of(context).pop<File>(f);
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('ساختِ خروجی ناموفق بود: {0}', [e]))),
      );
    }
  }

  // ── ورودیِ اشاره ──
  Offset _norm(Offset local, Size box) => Offset(
        (local.dx / box.width).clamp(0.0, 1.0),
        (local.dy / box.height).clamp(0.0, 1.0),
      );

  void _onDown(Offset p, Size box) {
    final n = _norm(p, box);
    if (_tool == _Tool.draw) {
      setState(() => _strokes.add(_Stroke(_color, _brushWidths[_brush])..points.add(n)));
      return;
    }
    if (_tool == _Tool.move) {
      // نزدیک‌ترین لایهٔ متنی به نقطهٔ لمس (از آخر، چون بالاترین لایه اول است)
      for (var i = _texts.length - 1; i >= 0; i--) {
        final t = _texts[i];
        final d = (t.center - n);
        if (d.dx.abs() < 0.22 && d.dy.abs() < 0.10) {
          setState(() => _selected = i);
          return;
        }
      }
      setState(() => _selected = null);
    }
  }

  void _onMove(Offset p, Size box, Offset delta) {
    if (_tool == _Tool.draw) {
      if (_strokes.isEmpty) return;
      setState(() => _strokes.last.points.add(_norm(p, box)));
      return;
    }
    final i = _selected;
    if (i == null || i >= _texts.length) return;
    setState(() {
      final t = _texts[i];
      t.center = Offset(
        (t.center.dx + delta.dx / box.width).clamp(0.0, 1.0),
        (t.center.dy + delta.dy / box.height).clamp(0.0, 1.0),
      );
    });
  }

  // ── دیالوگِ متن ──
  Future<void> _addOrEditText([int? index]) async {
    final existing = index == null ? null : _texts[index];
    final ctrl = TextEditingController(text: existing?.text ?? '');
    var color = existing?.color ?? _color;
    var effect = existing?.effect ?? _TextEffect.stroke;
    var bold = existing?.bold ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? tr('افزودنِ متن') : tr('ویرایشِ متن')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(hintText: tr('متن…')),
                ),
                const SizedBox(height: 12),
                Text(tr('افکت'), style: const TextStyle(fontSize: 12)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final e in _TextEffect.values)
                      ChoiceChip(
                        label: Text(_effectLabel(e), style: const TextStyle(fontSize: 11)),
                        selected: effect == e,
                        onSelected: (_) => setLocal(() => effect = e),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(tr('رنگ'), style: const TextStyle(fontSize: 12)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in _palette)
                      GestureDetector(
                        onTap: () => setLocal(() => color = c),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == c ? Colors.blueAccent : Colors.black26,
                              width: color == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: bold,
                  onChanged: (v) => setLocal(() => bold = v),
                  title: Text(tr('ضخیم'), style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(tr('انصراف'))),
            if (existing != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _texts.removeAt(index);
                    _selected = null;
                  });
                  Navigator.pop(ctx, false);
                },
                child: Text(tr('حذف'), style: const TextStyle(color: Colors.redAccent)),
              ),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تأیید'))),
          ],
        ),
      ),
    );

    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || text.isEmpty) return;
    setState(() {
      if (existing != null) {
        existing
          ..text = text
          ..color = color
          ..effect = effect
          ..bold = bold;
      } else {
        _texts.add(_TextLayer(
          text: text,
          color: color,
          effect: effect,
          center: const Offset(0.5, 0.5),
          size: 0.09,
          bold: bold,
        ));
        _selected = _texts.length - 1;
        _tool = _Tool.move;
      }
    });
  }

  String _effectLabel(_TextEffect e) => switch (e) {
        _TextEffect.stroke => tr('دورخط'),
        _TextEffect.shadow => tr('سایه'),
        _TextEffect.neon => tr('نئون'),
        _TextEffect.label => tr('برچسب'),
        _TextEffect.plain => tr('ساده'),
      };

  // ─────────────────────── ساختِ رابط ───────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('ویرایشِ تصویر')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _working ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_image != null) ...[
            IconButton(
              tooltip: tr('جابه‌جایی'),
              icon: Icon(Icons.open_with,
                  color: _tool == _Tool.move ? Colors.lightBlueAccent : Colors.white70),
              onPressed: () => setState(() => _tool = _Tool.move),
            ),
            IconButton(
              tooltip: tr('قلم'),
              icon: Icon(Icons.brush,
                  color: _tool == _Tool.draw ? Colors.lightBlueAccent : Colors.white70),
              onPressed: () => setState(() {
                _tool = _Tool.draw;
                _selected = null;
              }),
            ),
            IconButton(
              tooltip: tr('برش'),
              icon: Icon(Icons.crop,
                  color: _tool == _Tool.crop ? Colors.lightBlueAccent : Colors.white70),
              onPressed: () => setState(() => _tool = _Tool.crop),
            ),
          ],
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ),
            )
          : _image == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(child: _preview()),
                    _toolPanel(),
                    _bottomBar(),
                  ],
                ),
    );
  }

  Widget _preview() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final aspect = _outAspect;
        var w = c.maxWidth - 16, h = w / aspect;
        if (h > c.maxHeight - 16) {
          h = c.maxHeight - 16;
          w = h * aspect;
        }
        final box = Size(w, h);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => _onDown(d.localPosition, box),
                    onPanUpdate: (d) => _onMove(d.localPosition, box, d.delta),
                    onDoubleTap: () {
                      final i = _selected;
                      if (i != null) _addOrEditText(i);
                    },
                    child: CustomPaint(
                      painter: _ScenePainter(_scene()),
                      size: box,
                    ),
                  ),
                ),
                if (_tool == _Tool.crop) _cropOverlay(box),
                if (_tool == _Tool.move && _selected != null) _selectionHint(box),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _selectionHint(Size box) {
    final t = _texts[_selected!];
    return Positioned(
      left: 0,
      right: 0,
      bottom: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _miniBtn(Icons.remove, () => setState(() => t.size = (t.size - 0.012).clamp(0.03, 0.4))),
          const SizedBox(width: 6),
          _miniBtn(Icons.edit, () => _addOrEditText(_selected)),
          const SizedBox(width: 6),
          _miniBtn(Icons.add, () => setState(() => t.size = (t.size + 0.012).clamp(0.03, 0.4))),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData i, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(i, size: 17, color: Colors.white),
        ),
      );

  /// کادرِ برش با دستگیره‌های چهارگوشه. مختصات نرمال است تا مستقل از اندازهٔ
  /// پیش‌نمایش بماند.
  Widget _cropOverlay(Size box) {
    Widget handle(Alignment a, void Function(Offset d) onDrag) => Align(
          alignment: a,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => setState(() => onDrag(d.delta)),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
          ),
        );

    void resize({double? dl, double? dt, double? dr, double? db}) {
      var l = _crop.left + (dl ?? 0) / box.width;
      var t = _crop.top + (dt ?? 0) / box.height;
      var r = _crop.right + (dr ?? 0) / box.width;
      var b = _crop.bottom + (db ?? 0) / box.height;
      l = l.clamp(0.0, 1.0);
      t = t.clamp(0.0, 1.0);
      r = r.clamp(0.0, 1.0);
      b = b.clamp(0.0, 1.0);
      if (r - l < 0.08 || b - t < 0.08) return;
      _crop = Rect.fromLTRB(l, t, r, b);
      _applyRatio(keepTopLeft: true);
    }

    return Positioned(
      left: _crop.left * box.width,
      top: _crop.top * box.height,
      width: _crop.width * box.width,
      height: _crop.height * box.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() {
                final dx = d.delta.dx / box.width, dy = d.delta.dy / box.height;
                var r = _crop.shift(Offset(dx, dy));
                if (r.left < 0) r = r.shift(Offset(-r.left, 0));
                if (r.top < 0) r = r.shift(Offset(0, -r.top));
                if (r.right > 1) r = r.shift(Offset(1 - r.right, 0));
                if (r.bottom > 1) r = r.shift(Offset(0, 1 - r.bottom));
                _crop = r;
              }),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: CustomPaint(painter: _ThirdsPainter()),
              ),
            ),
          ),
          handle(Alignment.topLeft, (d) => resize(dl: d.dx, dt: d.dy)),
          handle(Alignment.topRight, (d) => resize(dr: d.dx, dt: d.dy)),
          handle(Alignment.bottomLeft, (d) => resize(dl: d.dx, db: d.dy)),
          handle(Alignment.bottomRight, (d) => resize(dr: d.dx, db: d.dy)),
        ],
      ),
    );
  }

  /// نسبتِ انتخاب‌شده را روی کادرِ برش اعمال می‌کند (نسبت به ابعادِ **تصویر**،
  /// نه کادرِ نمایش — وگرنه «۱:۱» روی تصویرِ غیرمربع مربع نمی‌شد).
  void _applyRatio({bool keepTopLeft = false}) {
    final ratio = _ratios[_ratio].value;
    if (ratio == null) return;
    final im = _image!;
    // نسبتِ کادرِ نرمال که خروجیِ آن `ratio` شود
    final target = ratio * im.height / im.width; // w_norm / h_norm
    var w = _crop.width, h = _crop.height;
    if (w / h > target) {
      w = h * target;
    } else {
      h = w / target;
    }
    var l = keepTopLeft ? _crop.left : _crop.center.dx - w / 2;
    var t = keepTopLeft ? _crop.top : _crop.center.dy - h / 2;
    if (w > 1) {
      w = 1;
      h = w / target;
    }
    if (h > 1) {
      h = 1;
      w = h * target;
    }
    l = l.clamp(0.0, 1 - w);
    t = t.clamp(0.0, 1 - h);
    _crop = Rect.fromLTWH(l, t, w, h);
  }

  // ── پنلِ ابزار ──
  Widget _toolPanel() {
    if (_tool == _Tool.crop) return _cropPanel();
    if (_tool == _Tool.draw) return _drawPanel();
    return _movePanel();
  }

  Widget _panel(List<Widget> children) => Container(
        color: const Color(0xFF111114),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _chips(List<String> labels, int current, void Function(int) onPick) =>
      SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            label: Text(tr(labels[i]), style: const TextStyle(fontSize: 11)),
            selected: current == i,
            onSelected: (_) => onPick(i),
          ),
        ),
      );

  Widget _cropPanel() => _panel([
        _chips([for (final r in _ratios) r.label], _ratio, (i) {
          setState(() {
            _ratio = i;
            _applyRatio();
          });
        }),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => setState(() {
            _crop = const Rect.fromLTWH(0, 0, 1, 1);
            _ratio = 0;
          }),
          icon: const Icon(Icons.restart_alt, size: 16, color: Colors.white70),
          label: Text(tr('بازنشانیِ برش'),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      ]);

  Widget _drawPanel() => _panel([
        _chips(_brushLabels, _brush, (i) => setState(() => _brush = i)),
        const SizedBox(height: 6),
        _colorRow(),
        TextButton.icon(
          onPressed: _strokes.isEmpty
              ? null
              : () => setState(() => _strokes.removeLast()),
          icon: const Icon(Icons.undo, size: 16, color: Colors.white70),
          label: Text(tr('واگردِ آخرین خط'),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      ]);

  Widget _colorRow() => SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _palette.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _color = _palette[i]),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _palette[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: _color == _palette[i] ? Colors.lightBlueAccent : Colors.white24,
                  width: _color == _palette[i] ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _movePanel() {
    final tabs = [tr('فیلتر'), tr('تنظیم'), tr('متن'), tr('قاب'), tr('کیفیت')];
    return _panel([
      SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _tab == i ? Colors.blueAccent : Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tabs[i],
                  style: TextStyle(
                      fontSize: 12,
                      color: _tab == i ? Colors.white : Colors.white70)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      switch (_tab) {
        0 => Column(children: [
            _chips([for (final f in kFilterPresets) f.label], _filter,
                (i) => setState(() => _filter = i)),
            const SizedBox(height: 6),
            _chips(_pixelLabels, _pixel, (i) => setState(() => _pixel = i)),
          ]),
        1 => _adjustPanel(),
        2 => Column(children: [
            TextButton.icon(
              onPressed: () => _addOrEditText(),
              icon: const Icon(Icons.title, size: 18, color: Colors.white),
              label: Text(tr('افزودنِ متن'),
                  style: const TextStyle(color: Colors.white)),
            ),
            if (_texts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  tr('برای جابه‌جایی بکِش، برای ویرایش دوبار بزن.'),
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ),
          ]),
        3 => _chips(_frameLabels, _frame, (i) => setState(() => _frame = i)),
        _ => _chips([for (final p in _presets) p.label], _preset,
            (i) => setState(() => _preset = i)),
      },
    ]);
  }

  Widget _adjustPanel() {
    Widget row(String label, double value, double min, double max,
        void Function(double) onChanged) {
      return Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(tr(label),
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) => setState(() => onChanged(v)),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('روشنایی', _adj.brightness, 0.4, 1.8, (v) => _adj.brightness = v),
          row('کنتراست', _adj.contrast, 0.4, 2.0, (v) => _adj.contrast = v),
          row('اشباع', _adj.saturate, 0.0, 2.5, (v) => _adj.saturate = v),
          row('گرمی', _adj.warmth, -1.0, 1.0, (v) => _adj.warmth = v),
          row('محو', _adj.blur, 0.0, 1.0, (v) => _adj.blur = v),
          if (!_adj.isDefault)
            TextButton(
              onPressed: () => setState(_adj.reset),
              child: Text(tr('بازنشانی'),
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() => SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFF0A0A0C),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _presets[_preset].maxDim == 0
                      ? tr('اندازهٔ اصلی')
                      : tr('حداکثر {0} پیکسل', [_presets[_preset].maxDim]),
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ),
              FilledButton.icon(
                onPressed: _working ? null : _export,
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: Text(_working ? tr('در حالِ ساخت…') : tr('تأیید و ارسال')),
              ),
            ],
          ),
        ),
      );
}

/// خطوطِ قانونِ یک‌سوم داخلِ کادرِ برش.
class _ThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3, y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ThirdsPainter old) => false;
}

/// کمکیِ باز کردنِ ویرایشگر. `null` یعنی کاربر لغو کرد.
Future<File?> openMediaEditor(BuildContext context, File source) {
  return Navigator.of(context).push<File>(
    MaterialPageRoute(builder: (_) => MediaEditorScreen(source: source)),
  );
}
