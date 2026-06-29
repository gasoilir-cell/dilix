import 'package:flutter/material.dart';

import '../assistant/assistant_sheet.dart';
import '../earth/earth_screen.dart';
import '../feed/feed_screen.dart';
import '../me/me_screen.dart';
import '../messages/messages_screen.dart';
import '../services/services_screen.dart';

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
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAssistant,
        tooltip: 'دستیار هوشمند',
        child: const Icon(Icons.auto_awesome),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'کره'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'پیام‌ها'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'خدمات'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'من'),
        ],
      ),
    );
  }
}
