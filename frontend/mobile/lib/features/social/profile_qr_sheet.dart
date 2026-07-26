import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config.dart';

/// کارتِ QR پروفایل.
///
/// سرور خودش کدِ QR را به شکلِ **SVG** رندر می‌کند
/// (`GET /api/v1/social/qr/{earth_id}`) و لینکِ `{web}/u/{earthId}` را در آن
/// کد می‌گذارد. این اندپوینت **عمومی است** (هیچ `get_current_user` ندارد)، پس
/// WebView می‌تواند بدونِ هدرِ Authorization آن را بارگذاری کند و لازم نیست
/// توکنِ نشست را به لایهٔ رندر بدهیم.
///
/// چرا WebView و نه یک بستهٔ QR؟ خروجیِ سرور از قبل SVG است؛ افزودنِ
/// `flutter_svg`/`qr_flutter` فقط یک وابستگیِ تازه به بیلد اضافه می‌کرد بدونِ
/// اینکه چیزی به نتیجه بیفزاید.
Future<void> showProfileQr(
  BuildContext context, {
  required String earthId,
  String? displayName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ProfileQrSheet(earthId: earthId, displayName: displayName),
  );
}

class _ProfileQrSheet extends StatefulWidget {
  const _ProfileQrSheet({required this.earthId, this.displayName});

  final String earthId;
  final String? displayName;

  @override
  State<_ProfileQrSheet> createState() => _ProfileQrSheetState();
}

class _ProfileQrSheetState extends State<_ProfileQrSheet> {
  late final WebViewController _web;
  bool _failed = false;

  String get _profileUrl => '${AppConfig.webBaseUrl}/u/${widget.earthId}';

  String get _qrUrl =>
      '${AppConfig.apiBaseUrl}/api/v1/social/qr/${Uri.encodeComponent(widget.earthId)}';

  @override
  void initState() {
    super.initState();
    // SVG را داخلِ یک صفحهٔ کوچک قاب می‌کنیم تا مستقل از ابعادِ ذاتیِ فایل،
    // مربعی و تمام‌عرض دیده شود. زمینه سفید می‌ماند چون کدِ QR تیره روی روشن
    // است و در پوستهٔ تیره هم باید اسکن‌پذیر بماند.
    _web = WebViewController()
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (err) {
            if ((err.isForMainFrame ?? true) && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" '
        'content="width=device-width,initial-scale=1"></head>'
        '<body style="margin:0;display:flex;align-items:center;'
        'justify-content:center;background:#fff;height:100vh">'
        '<img src="$_qrUrl" style="width:100%;height:auto;max-width:100vmin" '
        'alt="QR"></body></html>',
        baseUrl: AppConfig.apiBaseUrl,
      );
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _profileUrl));
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('لینکِ پروفایل کپی شد.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.displayName?.trim().isNotEmpty == true
              ? widget.displayName!
              : widget.earthId,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('این کد را اسکن کنید تا پروفایل باز شود.',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.white,
                child: _failed
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'ساختِ کدِ QR ممکن نشد.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      )
                    : WebViewWidget(controller: _web),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(widget.earthId,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontFamily: 'monospace')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.link),
                  label: const Text('کپیِ لینک'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('بستن'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
