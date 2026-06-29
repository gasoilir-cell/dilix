import 'package:flutter/material.dart';

/// لیستِ گفتگوها (سند ۷ §۴). پیام‌ها E2EE هستند؛ زنده از طریقِ WebSocket می‌آید.
/// این صفحه ساختارِ پایه را فراهم می‌کند؛ اتصالِ realtime در فازِ بعد افزوده می‌شود.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پیام‌ها')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                'گفتگوهای رمزنگاری‌شده (E2EE).\nهنوز گفتگویی ندارید.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
