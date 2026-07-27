import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/l10n.dart';
import '../../models/models.dart';

/// میزبانِ اجرای یک برنامهٔ کوچک.
///
/// نشانی از `launchMiniApp` می‌آید و کدِ یک‌بارمصرف را همراه دارد؛ همین‌جا
/// بارگذاری می‌شود چون کد کوتاه‌عمر است و اگر کاربر بین گرفتن و باز کردن مکث
/// کند، منقضی می‌شود. توکنِ خودِ کاربر هرگز داخلِ WebView نمی‌رود — برنامه
/// فقط کد را با کلیدِ خودش به توکنِ نشستِ مستعار تبدیل می‌کند.
class MiniAppHostScreen extends StatefulWidget {
  const MiniAppHostScreen({
    super.key,
    required this.app,
    required this.launch,
  });

  final MiniApp app;
  final MiniAppLaunch launch;

  @override
  State<MiniAppHostScreen> createState() => _MiniAppHostScreenState();
}

class _MiniAppHostScreenState extends State<MiniAppHostScreen> {
  late final WebViewController _web;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if ((err.isForMainFrame ?? true) && mounted) {
              setState(() {
                _loading = false;
                _error = tr('بارگذاریِ برنامه ناموفق بود');
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.launch.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.app.name),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _web),
    );
  }
}
