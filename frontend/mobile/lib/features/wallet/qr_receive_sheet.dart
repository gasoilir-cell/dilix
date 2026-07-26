import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app.dart';
import '../../core/l10n.dart';

/// کدِ QRِ «به من پرداخت کن».
///
/// کاربر می‌تواند مبلغ را از پیش داخلِ کد بگذارد (حالتِ صندوقِ فروشگاه) یا خالی
/// بگذارد تا پرداخت‌کننده خودش بنویسد.
Future<void> showReceiveQr(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _ReceiveQrSheet(),
  );
}

class _ReceiveQrSheet extends StatefulWidget {
  const _ReceiveQrSheet();

  @override
  State<_ReceiveQrSheet> createState() => _ReceiveQrSheetState();
}

class _ReceiveQrSheetState extends State<_ReceiveQrSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _web = WebViewController()..setBackgroundColor(Colors.white);

  String? _payload;
  bool _loading = true;
  String? _error;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // نه در `initState`: `ApiScope.of` به وابستگیِ inherited نیاز دارد و آنجا
    // هنوز مجاز نیست.
    if (!_started) {
      _started = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    final toman = int.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    // مبلغ در کد به ریال است؛ ورودیِ کاربر تومان — همان قراردادِ بقیهٔ کیف.
    final minor = (toman != null && toman > 0) ? toman * 10 : null;
    final note = _noteCtrl.text.trim();
    try {
      final svg = await api.walletQrSvg(amountMinor: minor, note: note);
      final payload = await api.walletQrPayload(amountMinor: minor, note: note);
      if (!mounted) return;
      // SVG داخلِ `<img>` با data-URI می‌نشیند، نه inline در DOM: تصویر نمی‌تواند
      // اسکریپت اجرا کند، پس حتی اگر روزی پاسخِ سرور دست‌کاری شود، به یک
      // تصویرِ خراب ختم می‌شود نه اجرای کد داخلِ WebView.
      final src = 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
      await _web.loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" '
        'content="width=device-width,initial-scale=1"></head>'
        '<body style="margin:0;display:flex;align-items:center;'
        'justify-content:center;background:#fff;height:100vh">'
        '<img src="$src" style="width:100%;height:auto;max-width:100vmin" alt="QR">'
        '</body></html>',
      );
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('ساختِ کدِ QR ممکن نشد: {0}', [e]);
        _loading = false;
      });
    }
  }

  Future<void> _copyPayload() async {
    final payload = _payload;
    if (payload == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(tr('لینکِ پرداخت کپی شد.'))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('دریافت با کدِ QR'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              tr('این کد یک لینکِ معمولی است، پس با دوربینِ هر گوشی هم خوانده می‌شود.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Colors.white,
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black54)),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            WebViewWidget(controller: _web),
                            if (_loading)
                              const ColoredBox(
                                color: Colors.white,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('مبلغ (تومان) — اختیاری'),
                hintText: tr('خالی بگذارید تا پرداخت‌کننده خودش وارد کند'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLength: 60,
              decoration: InputDecoration(labelText: tr('بابتِ (اختیاری)')),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _payload == null ? null : _copyPayload,
                    icon: const Icon(Icons.link),
                    label: Text(tr('کپیِ لینک')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    // کد پس از تغییرِ مبلغ/بابت باید دوباره ساخته شود؛ تولیدِ
                    // خودکار روی هر کاراکتر یعنی یک درخواستِ سرور به‌ازای هر
                    // ضربهٔ کیبورد.
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(tr('ساختِ کد')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
