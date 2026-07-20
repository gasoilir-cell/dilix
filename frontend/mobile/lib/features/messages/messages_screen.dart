import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/dilix_webview.dart';

/// پیام‌ها (سند ۷ §۴). پیام‌رسانِ کاملِ اپِ وب (dilix.ir/messages) را داخلِ
/// اپلیکیشن بارگذاری می‌کند — تمامِ امکاناتِ واقعیِ پیام‌رسان (گفتگوها،
/// رسانه، تماسِ صوتی/تصویری، E2EE، گروه‌ها) به‌صورتِ واقعی و نه نمایشی. توکنِ
/// نشستِ موبایل به WebView تزریق می‌شود تا کاربر دوباره وارد نشود.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('پیام‌ها')),
        body: _loginPrompt(context),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: DilixWebView(api: api, path: '/messages'),
      ),
    );
  }

  Widget _loginPrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'گفتگوهای رمزنگاری‌شده (E2EE).\nبرای شروع، از تبِ «من» وارد شوید.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
