import 'package:flutter/material.dart';

import '../assistant/assistant_sheet.dart';
import '../earth/earth_screen.dart';
import '../feed/feed_screen.dart';
import '../me/me_screen.dart';
import '../messages/messages_screen.dart';
import '../services/services_screen.dart';

import '../../core/l10n.dart';
import '../../core/preferences.dart';

/// پوسته‌ی Super-App با ناوبریِ پایین ۵تایی + دکمه‌ی شناورِ دستیار (سند ۷ §۲).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    FeedScreen(),
    EarthScreen(),
    MessagesScreen(),
    ServicesScreen(),
    MeScreen(),
  ];

  void _openAssistant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AssistantSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // خواندنِ زبان از [PreferencesScope] این پوسته را «وابسته» می‌کند؛ وگرنه
    // `RootGate` پوسته را با نمونهٔ `const` می‌سازد و Flutter بازسازیِ زیردرخت را
    // رد می‌کند، پس برچسب‌های نوارِ پایین با تعویضِ زبان فارسی می‌مانند.
    final lang = PreferencesScope.of(context).locale?.languageCode ?? 'fa';
    return Scaffold(
      // صفحه‌های تب‌ها یک‌بار ساخته و در IndexedStack زنده نگه داشته می‌شوند؛
      // کلیدِ زبان آن‌ها را با تعویضِ زبان از نو می‌سازد (تبِ فعال حفظ می‌شود).
      body: KeyedSubtree(
        key: ValueKey(lang),
        child: IndexedStack(index: _index, children: _screens),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAssistant,
        tooltip: tr('دستیار هوشمند'),
        child: const Icon(Icons.auto_awesome),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('خانه')),
          NavigationDestination(icon: const Icon(Icons.public_outlined), selectedIcon: const Icon(Icons.public), label: tr('کره')),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), selectedIcon: const Icon(Icons.chat_bubble), label: tr('پیام‌ها')),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view), label: tr('خدمات')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('من')),
        ],
      ),
    );
  }
}
