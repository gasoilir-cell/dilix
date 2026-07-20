import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';

/// اطلاعاتِ کاربرِ کره که هنگامِ لمسِ مارکر از صفحهٔ globe.gl به Flutter می‌رسد.
class EarthTap {
  const EarthTap({required this.earthId, required this.name, this.role, this.online});

  final String earthId;
  final String name;
  final String? role;
  final bool? online;
}

/// کره‌ی سه‌بعدیِ زندهٔ Dilix به‌صورتِ بومی در اپلیکیشن.
///
/// صفحهٔ استاتیکِ خودبسندهٔ `globe-native.html` (همان globe.gl و کاشیِ ماهواره‌ایِ
/// زندهٔ گوگل که وبِ dilix.ir استفاده می‌کند) داخلِ WebView لود می‌شود؛ این صفحه
/// **احراز/فرمِ ورود ندارد** و فقط کره را رندر می‌کند. داده‌ی کاربرانِ روی کره از
/// API (با توکنِ بومی) گرفته و از طریقِ `window.setUsers` به صفحه تزریق می‌شود؛
/// لمسِ مارکر از پُلِ `EarthChannel` به [onTap] برمی‌گردد. کاشی‌های گوگل پس از
/// اولین لود در کشِ WebView روی دستگاه می‌مانند.
class EarthGlobeView extends StatefulWidget {
  const EarthGlobeView({
    super.key,
    required this.api,
    this.onTap,
    this.fallbackBuilder,
  });

  final ApiClient api;
  final void Function(EarthTap tap)? onTap;
  final Widget Function(BuildContext context)? fallbackBuilder;

  @override
  State<EarthGlobeView> createState() => _EarthGlobeViewState();
}

class _EarthGlobeViewState extends State<EarthGlobeView> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;
  bool _ready = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _init() {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF080F22))
        ..addJavaScriptChannel('EarthChannel', onMessageReceived: _onChannel)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (err) {
              if ((err.isForMainFrame ?? true) && mounted) {
                setState(() => _failed = true);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(AppConfig.globeUrl));
      _controller = controller;
    } catch (_) {
      _controller = null;
      _failed = true;
    }
  }

  /// پیام‌های صفحهٔ globe.gl: `ready` (کره آماده شد → کاربران را بارگذاری کن) و
  /// `user`/`cluster` (لمسِ مارکر).
  void _onChannel(JavaScriptMessage message) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['type']) {
      case 'ready':
        _ready = true;
        _loadUsers();
        _startPolling();
        break;
      case 'user':
        widget.onTap?.call(EarthTap(
          earthId: (data['earth_id'] ?? '') as String,
          name: (data['name'] ?? '') as String,
          role: data['role'] as String?,
          online: data['online'] as bool?,
        ));
        break;
      case 'cluster':
        // خوشه: فعلاً بدونِ کنشِ اختصاصی (زوم دستی کاربر آن را باز می‌کند).
        break;
    }
  }

  /// پولِ کاربران هر ۱۵ث تا آنلاین/آفلاین‌شدن بدونِ رفرشِ دستی روی کره به‌روز شود
  /// (هم‌راستا با وبِ زنده).
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    final c = _controller;
    if (c == null || !_ready) return;
    try {
      final users = await widget.api.earthUsersRaw(limit: 500);
      final json = jsonEncode(users);
      await c.runJavaScript('window.setUsers(${jsonEncode(json)});');
    } catch (_) {
      // شکستِ گذرا نادیده گرفته می‌شود؛ پولِ بعدی دوباره تلاش می‌کند.
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
              color: Color(0xFF080F22),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _defaultFallback() {
    return const ColoredBox(
      color: Color(0xFF080F22),
      child: Center(
        child: Text('کره‌ی سه‌بعدی بارگذاری نشد.',
            style: TextStyle(color: Color(0xB3FFFFFF))),
      ),
    );
  }
}
