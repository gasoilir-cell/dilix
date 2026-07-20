import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'api_client.dart';
import 'config.dart';

/// WebViewِ احرازشدهٔ اپِ وبِ Dilix.
///
/// همان اپِ وبِ تولیدی (dilix.ir) را داخلِ اپلیکیشن بارگذاری می‌کند و توکنِ نشستِ
/// موبایل را پیش از بارگذاری در `localStorage` تزریق می‌کند تا کاربر دوباره وارد
/// نشود (اپِ وب با کلیدهایِ `dilix.access_token`/`dilix.refresh_token` احراز
/// می‌کند — همان کلیدهایی که موبایل استفاده می‌کند). این «نمایشی» نیست: تمامِ
/// امکاناتِ واقعیِ وب (پیام‌رسان، کره) از همین مسیر در دسترس می‌شود.
///
/// روی اندروید مجوزهایِ دوربین/میکروفن (تماس تصویری/صوتی)، موقعیتِ مکانی (کره) و
/// انتخابِ فایل (ارسالِ تصویر در چت) به WebView داده می‌شود.
class DilixWebView extends StatefulWidget {
  const DilixWebView({
    super.key,
    required this.api,
    required this.path,
    this.fallbackBuilder,
  });

  /// کلاینتِ API که توکنِ نشست را تأمین می‌کند.
  final ApiClient api;

  /// مسیرِ نسبیِ اپِ وب، مثلِ `/earth` یا `/messages`.
  final String path;

  /// نمایِ جایگزین وقتی WebView در دسترس نیست یا بارگذاری شکست می‌خورد
  /// (مثلاً در محیطِ تست یا بدونِ شبکه).
  final Widget Function(BuildContext context)? fallbackBuilder;

  @override
  State<DilixWebView> createState() => _DilixWebViewState();
}

class _DilixWebViewState extends State<DilixWebView> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;
  // آیا reloadِ یک‌بارهٔ «بوت با توکن» انجام شده است؟ جلوگیری از حلقهٔ reload.
  bool _sessionApplied = false;

  String get _url => '${AppConfig.webBaseUrl}${widget.path}';

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    try {
      final params = WebViewPlatform.instance is AndroidWebViewPlatform
          ? AndroidWebViewControllerCreationParams()
          : const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B1026))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => _injectSession(),
            onPageFinished: (_) => _onFinished(),
            onWebResourceError: (err) {
              // فقط خطایِ فریمِ اصلی نمایِ جایگزین را روشن می‌کند.
              if (err.isForMainFrame ?? true) {
                if (mounted) setState(() => _failed = true);
              }
            },
          ),
        );
      _configureAndroid(controller);
      controller.loadRequest(Uri.parse(_url));
      _controller = controller;
    } catch (_) {
      _controller = null;
      _failed = true;
    }
  }

  /// پس از پایانِ بارگذاری: توکن حالا قطعاً در `localStorage` هست (در
  /// `onPageStarted` نشانده شد و ماندگار است). یک‌بار reload می‌کنیم تا اپِ وب
  /// از همان بوتِ اول با نشستِ معتبر بالا بیاید و فرمِ ورود نشان ندهد (رفعِ ریسِ
  /// زمان‌بندی که باعث می‌شد SPA توکنِ null بخواند).
  void _onFinished() {
    final c = _controller;
    if (!_sessionApplied && c != null && widget.api.accessToken != null) {
      _sessionApplied = true;
      _injectSession();
      c.reload();
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// تزریقِ توکنِ نشستِ موبایل به `localStorage`ِ اپِ وب پیش از بوت‌شدنِ آن.
  void _injectSession() {
    final c = _controller;
    if (c == null) return;
    final access = widget.api.accessToken;
    if (access == null) return;
    final refresh = widget.api.refreshToken;
    final buf = StringBuffer('try{')
      ..write("localStorage.setItem('dilix.access_token',${jsonEncode(access)});");
    if (refresh != null) {
      buf.write("localStorage.setItem('dilix.refresh_token',${jsonEncode(refresh)});");
    }
    buf.write('}catch(e){}');
    c.runJavaScript(buf.toString());
  }

  /// مجوزهایِ پلتفرمِ اندروید: پخشِ خودکارِ رسانه، دوربین/میکروفن، موقعیت و
  /// انتخابِ فایل. روی سایرِ پلتفرم‌ها بی‌اثر است.
  void _configureAndroid(WebViewController controller) {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return;
    platform.setMediaPlaybackRequiresUserGesture(false);
    platform.setOnPlatformPermissionRequest((request) => request.grant());
    platform.setGeolocationPermissionsPromptCallbacks(
      onShowPrompt: (request) async =>
          GeolocationPermissionsResponse(allow: true, retain: true),
    );
    platform.setOnShowFileSelector(_pickFiles);
  }

  /// دیالوگِ انتخابِ فایلِ WebView را به image_picker گوشی وصل می‌کند تا کاربر
  /// بتواند از گالری تصویر پیوست کند.
  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return const [];
      return [Uri.file(image.path).toString()];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null) {
      return widget.fallbackBuilder?.call(context) ?? _defaultFallback();
    }
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: c)),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF0B1026),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _defaultFallback() {
    return const ColoredBox(
      color: Color(0xFF0B1026),
      child: Center(
        child: Text('اتصال به سرور برقرار نشد.',
            style: TextStyle(color: Color(0xB3FFFFFF))),
      ),
    );
  }
}
