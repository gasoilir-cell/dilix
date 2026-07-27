import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';

/// اسکنِ کدِ QR و پرداخت از کیف به کیف.
///
/// جریان عمداً سه‌گامی است: **اسکن → تأیید → ارسال**. پرداختِ خودکار بلافاصله پس
/// از اسکن، کلاسیک‌ترین راهِ کلاهبرداریِ QR است (چسباندنِ برچسبِ جعلی روی کدِ
/// فروشنده)؛ به همین دلیل بارِ اسکن‌شده اول به `wallet/qr/resolve` می‌رود تا
/// سرور دامنه و شناسه را اعتبارسنجی کند و نام و آواتارِ گیرنده را برگردانَد، و
/// کاربر پیش از کسرِ پول ببیند پول به چه کسی می‌رود.
///
/// خروجی: `true` اگر انتقالی انجام شده باشد (تا کیفِ پول خودش را تازه کند).
///
/// گامِ «تأیید» ([showConfirmPaySheet]) عمداً از اسکنر جدا و عمومی است، چون
/// لینکِ عمیقِ `dilix.ir/pay/…` بدونِ دوربین به همان گام می‌رسد و نباید نسخهٔ
/// دومی از منطقِ پرداخت داشته باشد.
class QrScanPayScreen extends StatefulWidget {
  const QrScanPayScreen({super.key});

  @override
  State<QrScanPayScreen> createState() => _QrScanPayScreenState();
}

class _QrScanPayScreenState extends State<QrScanPayScreen> {
  // فقط QR: با محدودکردنِ فرمت‌ها بارکدهای خطیِ اطراف (روی بسته‌بندیِ فروشگاه)
  // اسکنر را مشغول نمی‌کنند. `noDuplicates` جلوی شلیکِ پیاپیِ یک کد را می‌گیرد،
  // ولی به‌تنهایی کافی نیست چون کدهای *متفاوت* هم پشتِ‌هم می‌آیند — قفلِ
  // `_busy` پایین همان را می‌بندد.
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// تا وقتی یک بار در حالِ بازگشایی/تأیید است، بارِ بعدی نادیده گرفته می‌شود؛
  /// وگرنه چند برگهٔ تأیید روی هم باز می‌شد.
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    // چون کنترلر را خودمان ساخته‌ایم، خودمان هم باید آزادش کنیم؛ ویجت فقط
    // کنترلرِ داخلیِ خودش را dispose می‌کند.
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;
    await _handlePayload(raw.trim());
  }

  Future<void> _handlePayload(String payload) async {
    // پیش از هر `await` گرفته می‌شود تا `context` بعد از فاصلهٔ async لمس نشود.
    final api = ApiScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    // دوربین در طولِ برگهٔ تأیید خاموش می‌شود: هم باتری/گرما، هم اینکه کاربر
    // نباید حین تصمیم‌گیری ناخواسته کدِ دیگری را اسکن کند.
    await _controller.stop();
    QrPayTarget target;
    try {
      target = await api.resolveWalletQr(payload);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('این کد خوانده نشد: {0}', [e]));
      await _resume();
      return;
    }
    if (!mounted) return;

    if (target.isSelf) {
      setState(() => _error = tr('این کدِ QRِ خودِ شماست؛ نمی‌توان به خود پرداخت کرد.'));
      await _resume();
      return;
    }

    final paid = await showConfirmPaySheet(context, target);
    if (!mounted) return;
    if (paid == true) {
      Navigator.of(context).pop(true);
      return;
    }
    await _resume();
  }

  /// بازگرداندنِ اسکنر پس از خطا یا انصرافِ کاربر.
  Future<void> _resume() async {
    try {
      await _controller.start();
    } on MobileScannerException {
      // اگر دوربین برنگشت، کاربر با دکمهٔ «بستن» بیرون می‌رود؛ کرش لازم نیست.
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('اسکنِ کدِ پرداخت')),
        actions: [
          // چراغِ قوه برای کدِ چاپ‌شده در نورِ کم (رسیدِ کاغذی، برچسبِ صندوق).
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (_, state, __) => IconButton(
              tooltip: tr('چراغ'),
              onPressed: () => _controller.toggleTorch(),
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flashlight_on
                    : Icons.flashlight_off,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (_, error, __) =>
                      _CameraError(message: error.errorDetails?.message),
                ),
                const IgnorePointer(child: _ScanFrame()),
                if (_busy)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  tr('کدِ QRِ گیرنده را داخلِ کادر بگیرید.'),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// کادرِ راهنمای اسکن. صرفاً تزئینی است — ناحیهٔ تشخیص کلِ فریم است تا کاربری
/// که کد را کمی بیرونِ کادر گرفته با شکستِ بی‌دلیل روبه‌رو نشود.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.7,
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                // فراگیرترین علت، ردِ مجوزِ دوربین است؛ متن به همان اشاره می‌کند
                // تا کاربر بداند کجا را درست کند.
                tr('دسترسی به دوربین ممکن نشد. اگر مجوزِ دوربین را رد کرده‌اید، از '
                    'تنظیماتِ گوشی آن را فعال کنید یا با Earth ID دستی پرداخت کنید.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// نمایشِ برگهٔ تأییدِ پرداخت برای گیرندهٔ از‌پیش‌بازگشایی‌شده.
///
/// خروجی `true` یعنی انتقال انجام شد.
Future<bool?> showConfirmPaySheet(BuildContext context, QrPayTarget target) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ConfirmPaySheet(target: target),
    );

/// تأییدِ پرداخت پس از بازگشاییِ کد.
class ConfirmPaySheet extends StatefulWidget {
  const ConfirmPaySheet({super.key, required this.target});

  final QrPayTarget target;

  @override
  State<ConfirmPaySheet> createState() => _ConfirmPaySheetState();
}

class _ConfirmPaySheetState extends State<ConfirmPaySheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  bool _sending = false;
  String? _error;

  /// مبلغِ داخلِ کد قفل است: اگر گیرنده مبلغ را در QR گذاشته، تغییرش یعنی
  /// پرداختِ ناقص و اختلافِ حساب سرِ صندوق.
  bool get _amountLocked => widget.target.amountMinor != null;

  @override
  void initState() {
    super.initState();
    final minor = widget.target.amountMinor;
    // ریالِ سرور به تومانِ ورودیِ کاربر؛ همان قراردادِ فرمِ انتقالِ دستی.
    _amountCtrl = TextEditingController(
      text: minor == null ? '' : (minor ~/ 10).toString(),
    );
    _noteCtrl = TextEditingController(text: widget.target.note ?? '');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final toman = int.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    if (toman == null || toman <= 0) {
      setState(() => _error = tr('مبلغِ معتبر (تومان) وارد کنید.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).walletTransfer(
        toEarthId: widget.target.earthId,
        amountMinor: toman * 10,
        description: _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('پرداخت ناموفق بود: {0}', [e]);
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.target;
    // آواتار از سرور می‌تواند مسیرِ نسبی باشد؛ `NetworkImage` مطلق می‌خواهد.
    final avatar = AppConfig.absoluteMedia(t.avatarUrl);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: avatar == null ? null : NetworkImage(avatar),
                child: avatar == null ? const Icon(Icons.person_outline) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('پرداخت به'), style: theme.textTheme.bodySmall),
                    Text(t.displayName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(t.earthId,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            readOnly: _amountLocked,
            decoration: InputDecoration(
              labelText: tr('مبلغ (تومان)'),
              helperText: _amountLocked
                  ? tr('مبلغ را گیرنده در کد تعیین کرده است.')
                  : null,
              suffixIcon: _amountLocked ? const Icon(Icons.lock_outline, size: 18) : null,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(labelText: tr('توضیح (اختیاری)')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                  child: Text(tr('انصراف')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: Text(_sending ? tr('در حالِ پرداخت…') : tr('پرداخت')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
