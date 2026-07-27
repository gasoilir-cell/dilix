import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/l10n.dart';
import 'color_matrix.dart';

/// استودیوی استیکر — معادلِ موبایلیِ `StickerStudio.tsx` در وب.
///
/// چهار حالتِ وب همگی پیاده شده‌اند: **استیکرِ ثابت**، **متحرک**، **صوتی** و
/// **ادغام** (ایموجی‌ساز). مثلِ ویرایشگرِ تصویر، هیچ وابستگیِ تازه‌ای اضافه
/// نمی‌شود؛ فقط `dart:ui` به‌علاوهٔ پکیج‌هایی که از قبل در `pubspec.yaml`
/// هستند (`image_picker`, `record`, `path_provider`).
///
/// تفاوتِ آگاهانه با وب: در حالتِ **متحرک**، وب فیلتر را فریم‌به‌فریم روی
/// `MediaRecorder` می‌پزد. موبایل رمزگذارِ ویدیو در دسترس ندارد (و افزودنِ
/// ffmpeg یعنی وابستگیِ بومیِ سنگین)، پس ویدیو خام ضبط و ارسال می‌شود و این
/// موضوع در خودِ UI به کاربر گفته می‌شود — به‌جای اینکه فیلترِ بی‌اثر نشان
/// دهیم و کاربر بعدِ ارسال بفهمد اعمال نشده.
class StickerStudioScreen extends StatefulWidget {
  const StickerStudioScreen({super.key});

  @override
  State<StickerStudioScreen> createState() => _StickerStudioScreenState();
}

/// خروجیِ استودیو: فایلِ ساخته‌شده به‌همراهِ نوعش.
class StudioResult {
  const StudioResult(this.file, this.kind);

  final File file;

  /// `image` | `video` | `voice` — گیرنده بر اساسِ آن پیام را می‌سازد.
  final String kind;
}

// ───────────────────────────── ثابت‌ها ─────────────────────────────

class _Highlight {
  const _Highlight(this.label, this.color);
  final String label;
  final Color? color; // null = بدون رنگ
}

/// همان ۶ هایلایتِ وب با همان آلفا (۰٫۲۸ و بنفشِ ۰٫۳۰).
const List<_Highlight> _highlights = <_Highlight>[
  _Highlight('بدون', null),
  _Highlight('زرد', Color(0x47FACC15)),
  _Highlight('صورتی', Color(0x47EC4899)),
  _Highlight('آبی', Color(0x4738BDF8)),
  _Highlight('سبز', Color(0x4734D399)),
  _Highlight('بنفش', Color(0x4DA78BFA)),
];

const List<Color> _textColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFFACC15),
  Color(0xFFEC4899),
  Color(0xFF38BDF8),
  Color(0xFF34D399),
  Color(0xFFF87171),
];

/// اندازهٔ خروجیِ استیکر. وب هم ۵۱۲ است؛ سقفِ سرور برای استیکر ۱۲MB است و
/// PNGِ ۵۱۲ خیلی زیرِ آن می‌ماند.
const int _stickerSize = 512;

const List<String> _audioEmojis = <String>[
  '😀', '😂', '😍', '🥳', '😎', '😭', '😱', '🥰', //
  '🤩', '😴', '🔥', '❤️', '👏', '🎉', '🙏', '💯',
];

/// ۶۴ ایموجیِ ادغام — عیناً همان فهرستِ `FUSION_EMOJIS` در وب.
const List<String> _fusionEmojis = <String>[
  '😀', '😂', '🥹', '😍', '🥰', '😎', '🤩', '😭', //
  '😱', '🤔', '😴', '🤯', '🥳', '😇', '🤠', '🥶',
  '🔥', '❤️', '💥', '⭐', '🌟', '✨', '💫', '🌈',
  '☀️', '🌙', '🪐', '⚡', '❄️', '💧', '🍀', '🌸',
  '🦷', '👁️', '🧠', '👑', '🎩', '🕶️', '💎', '🎈',
  '🎉', '🍕', '🍔', '🍩', '🍦', '☕', '🍺', '🎸',
  '⚽', '🏀', '🚀', '✈️', '🚗', '🐶', '🐱', '🦊',
  '🐼', '🦁', '🐸', '🐢', '🦄', '🐝', '🦋', '🐙',
];

enum _Layout { overlay, side, stack, badge }

const Map<_Layout, String> _layoutLabels = <_Layout, String>{
  _Layout.overlay: 'روی‌هم',
  _Layout.side: 'کنارِهم',
  _Layout.stack: 'بالا‌پایین',
  _Layout.badge: 'نشان',
};

// ──────────────────────── کمکی‌های مشترکِ UI ────────────────────────

/// نوارِ افقیِ تراشه‌های انتخابی. همان الگوی وب: انتخاب‌شده صورتیِ پررنگ.
Widget _chipRow({
  required List<String> labels,
  required int selected,
  required ValueChanged<int> onTap,
}) {
  return SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: labels.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final on = i == selected;
        return GestureDetector(
          onTap: () => onTap(i),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? const Color(0x33D946EF) : Colors.white10,
              border: Border.all(
                  color: on ? const Color(0x80E879F9) : Colors.white24),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(tr(labels[i]),
                style: TextStyle(
                    fontSize: 12,
                    color: on ? Colors.white : Colors.white70)),
          ),
        );
      },
    ),
  );
}

Widget _primaryButton({
  required IconData icon,
  required String label,
  required VoidCallback? onPressed,
  bool busy = false,
}) {
  return SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFC026D3),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 18),
      label: Text(label),
    ),
  );
}

/// نوشتنِ تصویرِ ساخته‌شده در فایلِ موقت. PNG است چون Flutter رمزگذارِ دیگری
/// در دسترس نمی‌گذارد و شفافیتِ استیکر هم فقط با PNG حفظ می‌شود.
Future<File> _writePng(ui.Image image, String prefix) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError(tr('رمزگذاریِ تصویر ناموفق بود'));
  final dir = await getTemporaryDirectory();
  final f = File(
      '${dir.path}/$prefix${DateTime.now().millisecondsSinceEpoch}.png');
  await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return f;
}

// ════════════════════════════ صفحهٔ اصلی ════════════════════════════

class _StickerStudioScreenState extends State<StickerStudioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _finish(StudioResult r) => Navigator.of(context).pop(r);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('استودیوی استیکر')),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFFD946EF),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 13),
          tabs: [
            Tab(text: tr('استیکر')),
            Tab(text: tr('متحرک')),
            Tab(text: tr('صوتی')),
            Tab(text: tr('ادغام')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _StillEditor(onDone: _finish),
          _AnimatedEditor(onDone: _finish),
          _AudioEditor(onDone: _finish),
          _FusionEditor(onDone: _finish),
        ],
      ),
    );
  }
}

// ═══════════════════════ ۱) استیکرِ ثابت ═══════════════════════

class _StillEditor extends StatefulWidget {
  const _StillEditor({required this.onDone});
  final ValueChanged<StudioResult> onDone;

  @override
  State<_StillEditor> createState() => _StillEditorState();
}

class _StillEditorState extends State<_StillEditor> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();

  ui.Image? _image;
  int _filter = 0;
  int _highlight = 0;
  int _textColor = 0;
  bool _square = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 95);
      if (x == null) return;
      final bytes = await File(x.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
      });
    } catch (e) {
      if (mounted) setState(() => _error = tr('بازکردنِ تصویر ناموفق بود: {0}', [e]));
    }
  }

  /// رسمِ صحنه — تنها منبعِ حقیقت برای پیش‌نمایش و خروجی، تا «چیزی که می‌بینی
  /// همان است که ارسال می‌شود».
  void _paint(Canvas canvas, Size out) {
    final im = _image;
    if (im == null) return;
    final iw = im.width.toDouble(), ih = im.height.toDouble();

    Rect src;
    if (_square) {
      final m = math.min(iw, ih);
      src = Rect.fromLTWH((iw - m) / 2, (ih - m) / 2, m, m);
    } else {
      src = Rect.fromLTWH(0, 0, iw, ih);
    }

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter =
          ColorFilter.matrix(kFilterPresets[_filter].matrix);
    canvas.drawImageRect(im, src, Offset.zero & out, paint);

    final hl = _highlights[_highlight].color;
    if (hl != null) {
      canvas.drawRect(Offset.zero & out, Paint()..color = hl);
    }

    final cap = _caption.text.trim();
    if (cap.isEmpty) return;

    // اندازهٔ قلم نسبت به عرضِ خروجی است تا پیش‌نمایش و فایلِ ۵۱۲ یکی باشند.
    final fs = out.width * 0.09;
    final color = _textColors[_textColor];
    final strokeColor =
        color == const Color(0xFF000000) ? Colors.white : const Color(0xD9000000);

    TextPainter layoutText(TextStyle style) => TextPainter(
          text: TextSpan(text: cap, style: style),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
        )..layout(maxWidth: out.width * 0.92);

    final strokeStyle = TextStyle(
      fontSize: fs,
      fontWeight: FontWeight.bold,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(3.0, fs * 0.14)
        ..color = strokeColor,
    );
    final fillStyle =
        TextStyle(fontSize: fs, fontWeight: FontWeight.bold, color: color);

    final tpStroke = layoutText(strokeStyle);
    final tpFill = layoutText(fillStyle);
    final dx = (out.width - tpFill.width) / 2;
    final dy = out.height - tpFill.height - fs * 0.25;
    tpStroke.paint(canvas, Offset(dx, dy));
    tpFill.paint(canvas, Offset(dx, dy));
  }

  Future<void> _build() async {
    final im = _image;
    if (im == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final double w = _stickerSize.toDouble();
      final double h = _square
          ? w
          : math.max(1.0, (w * im.height / im.width).roundToDouble());
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
      _paint(canvas, Size(w, h));
      final pic = rec.endRecording();
      final out = await pic.toImage(w.round(), h.round());
      pic.dispose();
      final file = await _writePng(out, 'sticker-');
      out.dispose();
      if (!mounted) return;
      widget.onDone(StudioResult(file, 'image'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('ساختِ استیکر ناموفق بود: {0}', [e]);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) return _sourcePicker();

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AspectRatio(
                aspectRatio: _square ? 1.0 : _image!.width / _image!.height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CustomPaint(
                    painter: _StillPainter(this),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
        _controls(),
      ],
    );
  }

  Widget _sourcePicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('یک منبع انتخاب کن'),
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 20),
            _sourceTile(Icons.add_photo_alternate_outlined,
                tr('وارد کردنِ تصویر'), () => _pick(ImageSource.gallery)),
            const SizedBox(height: 12),
            _sourceTile(Icons.photo_camera_outlined,
                tr('گرفتنِ عکس با دوربین'), () => _pick(ImageSource.camera)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sourceTile(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF7DD3FC)),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0C),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chipRow(
            labels: [for (final f in kFilterPresets) f.label],
            selected: _filter,
            onTap: (i) => setState(() => _filter = i),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                  width: 34,
                  child: Text(tr('رنگ'),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11))),
              for (var i = 0; i < _highlights.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _highlight = i),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _highlights[i].color ?? Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _highlight == i
                                ? Colors.white
                                : Colors.white24),
                      ),
                      child: _highlights[i].color == null
                          ? const Icon(Icons.close,
                              size: 12, color: Colors.white54)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.title, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _caption,
                  maxLength: 40,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white10,
                    hintText: tr('متن (اختیاری)'),
                    hintStyle: const TextStyle(color: Colors.white30),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              for (var i = 0; i < _textColors.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _textColor = i),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _textColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                            width: 2,
                            color: _textColor == i
                                ? Colors.white
                                : Colors.white24),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 11)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _square = !_square),
                icon: Icon(_square ? Icons.crop_square : Icons.crop_free,
                    size: 16),
                label: Text(_square ? tr('مربع') : tr('کامل')),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _image?.dispose();
                  _image = null;
                }),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(tr('تعویضِ تصویر')),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _primaryButton(
            icon: Icons.send,
            label: tr('ارسالِ استیکر'),
            busy: _busy,
            onPressed: _build,
          ),
        ],
      ),
    );
  }
}

class _StillPainter extends CustomPainter {
  _StillPainter(this.state);
  final _StillEditorState state;

  @override
  void paint(Canvas canvas, Size size) => state._paint(canvas, size);

  // صحنه به وضعیتِ قابلِ‌تغییرِ ویرایشگر وابسته است، پس همیشه دوباره رسم می‌شود.
  @override
  bool shouldRepaint(covariant _StillPainter old) => true;
}

// ═══════════════════════ ۲) استیکرِ متحرک ═══════════════════════

class _AnimatedEditor extends StatefulWidget {
  const _AnimatedEditor({required this.onDone});
  final ValueChanged<StudioResult> onDone;

  @override
  State<_AnimatedEditor> createState() => _AnimatedEditorState();
}

class _AnimatedEditorState extends State<_AnimatedEditor> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;

  Future<void> _record(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final x = await _picker.pickVideo(
        source: source,
        // وب هم سقفِ ۶ ثانیه دارد؛ استیکرِ متحرک باید کوتاه باشد.
        maxDuration: const Duration(seconds: 6),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (x == null) return;
      widget.onDone(StudioResult(File(x.path), 'video'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('ضبطِ ویدیو ناموفق بود: {0}', [e]);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_creation_outlined,
                size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(tr('استیکرِ متحرک — حداکثر ۶ ثانیه'),
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            _primaryButton(
              icon: Icons.videocam,
              label: tr('ضبط با دوربین'),
              busy: _busy,
              onPressed: () => _record(ImageSource.camera),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _record(ImageSource.gallery),
                icon: const Icon(Icons.video_library_outlined, size: 18),
                label: Text(tr('انتخاب از گالری')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('فیلترِ رنگ روی ویدیو در موبایل اعمال نمی‌شود؛ برای استیکرِ فیلتردار از زبانهٔ «استیکر» استفاده کن.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════ ۳) استیکرِ صوتی ═══════════════════════

class _AudioEditor extends StatefulWidget {
  const _AudioEditor({required this.onDone});
  final ValueChanged<StudioResult> onDone;

  @override
  State<_AudioEditor> createState() => _AudioEditorState();
}

class _AudioEditorState extends State<_AudioEditor> {
  final _recorder = AudioRecorder();
  Timer? _timer;
  bool _recording = false;
  int _secs = 0;
  String? _path;
  String _emoji = _audioEmojis.first;
  String? _error;

  /// سقفِ وب. صدای بلندتر دیگر «استیکر» نیست، پیامِ صوتی است.
  static const int _maxSecs = 15;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() => _error = tr('برای ضبطِ صدا به اجازهٔ میکروفن نیاز است.'));
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice-sticker-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _secs = 0;
        _path = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secs++);
        if (_secs >= _maxSecs) _stop();
      });
    } catch (e) {
      if (mounted) setState(() => _error = tr('شروعِ ضبط ناموفق بود: {0}', [e]));
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    String? p;
    try {
      p = await _recorder.stop();
    } catch (_) {
      p = null;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _path = p;
    });
  }

  void _discard() {
    setState(() {
      _path = null;
      _secs = 0;
    });
  }

  void _send() {
    final p = _path;
    if (p == null) return;
    widget.onDone(StudioResult(File(p), 'voice'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_emoji, style: const TextStyle(fontSize: 84)),
                const SizedBox(height: 12),
                Text(
                  _recording
                      ? tr('در حالِ ضبط — {0} از {1} ثانیه', [_secs, _maxSecs])
                      : _path != null
                          ? tr('{0} ثانیه ضبط شد', [_secs])
                          : tr('یک صدای کوتاه ضبط کن'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C0C),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _audioEmojis.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final e = _audioEmojis[i];
                    return GestureDetector(
                      onTap: () => setState(() => _emoji = e),
                      child: Container(
                        width: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _emoji == e
                              ? const Color(0x33D946EF)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
                ),
              const SizedBox(height: 12),
              if (_path == null)
                _primaryButton(
                  icon: _recording ? Icons.stop : Icons.mic,
                  label: _recording ? tr('توقفِ ضبط') : tr('شروعِ ضبط'),
                  onPressed: _recording ? _stop : _start,
                )
              else
                Row(
                  children: [
                    IconButton(
                      onPressed: _discard,
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white54),
                      tooltip: tr('حذف و ضبطِ دوباره'),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _primaryButton(
                        icon: Icons.send,
                        label: tr('ارسالِ استیکرِ صوتی'),
                        onPressed: _send,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════ ۴) ادغام (ایموجی‌ساز) ═══════════════════

class _FusionEditor extends StatefulWidget {
  const _FusionEditor({required this.onDone});
  final ValueChanged<StudioResult> onDone;

  @override
  State<_FusionEditor> createState() => _FusionEditorState();
}

class _FusionEditorState extends State<_FusionEditor> {
  String _a = '🦷';
  String _b = '🪐';
  bool _slotA = true;
  _Layout _layout = _Layout.overlay;
  bool _busy = false;
  String? _error;

  /// رسمِ یک ایموجی به‌صورتِ متن روی بوم. `TextPainter` قلمِ رنگیِ سیستم را
  /// انتخاب می‌کند، پس ایموجی همان‌طور که در کیبورد است رسم می‌شود.
  void _drawEmoji(Canvas canvas, String emoji, Offset center, double px) {
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: px)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// چیدمان‌ها عیناً همان نسبت‌های `FusionEditor` در وب‌اند.
  void _paint(Canvas canvas, double size) {
    switch (_layout) {
      case _Layout.overlay:
        _drawEmoji(canvas, _a, Offset(size / 2, size / 2), size * 0.72);
        _drawEmoji(canvas, _b, Offset(size * 0.68, size * 0.68), size * 0.42);
      case _Layout.side:
        _drawEmoji(canvas, _a, Offset(size * 0.30, size / 2), size * 0.52);
        _drawEmoji(canvas, _b, Offset(size * 0.70, size / 2), size * 0.52);
      case _Layout.stack:
        _drawEmoji(canvas, _a, Offset(size / 2, size * 0.32), size * 0.50);
        _drawEmoji(canvas, _b, Offset(size / 2, size * 0.70), size * 0.50);
      case _Layout.badge:
        _drawEmoji(canvas, _a, Offset(size / 2, size / 2), size * 0.78);
        canvas.drawCircle(
          Offset(size * 0.74, size * 0.26),
          size * 0.21,
          Paint()..color = const Color(0xEBFFFFFF),
        );
        _drawEmoji(canvas, _b, Offset(size * 0.74, size * 0.26), size * 0.32);
    }
  }

  Future<void> _build() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final double s = _stickerSize.toDouble();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, s, s));
      _paint(canvas, s);
      final pic = rec.endRecording();
      final out = await pic.toImage(s.round(), s.round());
      pic.dispose();
      final file = await _writePng(out, 'emoji-fusion-');
      out.dispose();
      if (!mounted) return;
      widget.onDone(StudioResult(file, 'image'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('ساختِ ایموجی ناموفق بود: {0}', [e]);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: CustomPaint(painter: _FusionPainter(this)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _slotButton(_a, isA: true),
                    IconButton(
                      tooltip: tr('جابه‌جایی'),
                      onPressed: () => setState(() {
                        final t = _a;
                        _a = _b;
                        _b = t;
                      }),
                      icon: const Icon(Icons.swap_horiz, color: Colors.white54),
                    ),
                    _slotButton(_b, isA: false),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _slotA
                      ? tr('ایموجیِ اول را از پایین انتخاب کن')
                      : tr('ایموجیِ دوم را از پایین انتخاب کن'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF0C0C0C),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chipRow(
                labels: [for (final l in _Layout.values) _layoutLabels[l]!],
                selected: _Layout.values.indexOf(_layout),
                onTap: (i) => setState(() => _layout = _Layout.values[i]),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 140,
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _fusionEmojis.length,
                  itemBuilder: (_, i) {
                    final e = _fusionEmojis[i];
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (_slotA) {
                          _a = e;
                        } else {
                          _b = e;
                        }
                      }),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white10,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 18)),
                      ),
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11)),
                ),
              const SizedBox(height: 10),
              _primaryButton(
                icon: Icons.send,
                label: tr('ارسالِ ایموجیِ ترکیبی'),
                busy: _busy,
                onPressed: _build,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slotButton(String emoji, {required bool isA}) {
    final active = _slotA == isA;
    return GestureDetector(
      onTap: () => setState(() => _slotA = isA),
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0x33D946EF) : Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? const Color(0xFFE879F9) : Colors.white24),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

class _FusionPainter extends CustomPainter {
  _FusionPainter(this.state);
  final _FusionEditorState state;

  @override
  void paint(Canvas canvas, Size size) => state._paint(canvas, size.width);

  @override
  bool shouldRepaint(covariant _FusionPainter old) => true;
}

/// کمکیِ بازکردنِ استودیو. `null` یعنی کاربر بست.
Future<StudioResult?> openStickerStudio(BuildContext context) {
  return Navigator.of(context).push<StudioResult>(
    MaterialPageRoute(builder: (_) => const StickerStudioScreen()),
  );
}
