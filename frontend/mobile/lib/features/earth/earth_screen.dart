import 'package:flutter/material.dart';

import '../../app.dart';
import '../assistant/assistant_sheet.dart';
import '../messages/chat_screen.dart';
import 'earth_globe_view.dart';

/// کشفِ افراد/کسب‌وکار روی کره (امضای محصول، سند ۷ §۳).
///
/// کره‌ی سه‌بعدیِ **بومی** است: صفحهٔ خودبسندهٔ globe.gl (همان کاشیِ ماهواره‌ایِ
/// زندهٔ گوگل که وبِ dilix.ir دارد) داخلِ [EarthGlobeView] لود می‌شود و داده‌ی
/// کاربران از API با توکنِ بومی تزریق می‌گردد — نه اپِ وبِ احرازشده. نوارِ جستجو و
/// دکمه‌های بومی روی کره باقی می‌مانند.
class EarthScreen extends StatefulWidget {
  const EarthScreen({super.key});

  @override
  State<EarthScreen> createState() => _EarthScreenState();
}

class _EarthScreenState extends State<EarthScreen> {
  final _queryCtrl = TextEditingController();

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: EarthGlobeView(
              api: api,
              onTap: _onUserTap,
              fallbackBuilder: _fallbackGlobe,
            ),
          ),
          // نوارِ جستجوی شناور روی کره.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _searchBar(),
          ),
          // FABِ دستیارِ هوشمند در پایین‌چپ (مثلِ نمای وب).
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            child: FloatingActionButton(
              heroTag: 'earth-assistant',
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              onPressed: _openAssistant,
              child: const Icon(Icons.smart_toy),
            ),
          ),
        ],
      ),
    );
  }

  /// لمسِ مارکرِ یک کاربر روی کره → شیتِ کنشِ سریع (پیام/پروفایل).
  void _onUserTap(EarthTap tap) {
    if (tap.earthId.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    (tap.online ?? false) ? const Color(0xFF22C55E) : Colors.grey,
                child: Text(tap.name.isNotEmpty ? tap.name.characters.first : '؟',
                    style: const TextStyle(color: Colors.white)),
              ),
              title: Text(tap.name.isEmpty ? tap.earthId : tap.name),
              subtitle: Text(tap.earthId),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('گفتگو'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openChat(tap);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// بازکردنِ (یا ساختِ) گفتگویِ مستقیم با کاربرِ انتخاب‌شده و رفتن به صفحهٔ چت.
  Future<void> _openChat(EarthTap tap) async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room = await api.createDirectRoom(tap.earthId, title: tap.name);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('باز کردنِ گفتگو ناموفق بود: $e')));
    }
  }

  /// گشودنِ دستیارِ هوشمندِ سراسری به‌صورتِ شیتِ پایین.
  void _openAssistant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AssistantSheet(),
    );
  }

  /// نمایِ جایگزین وقتی WebView در دسترس نیست (تست یا بدونِ شبکه).
  Widget _fallbackGlobe(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [Color(0xFF1B3A6B), Color(0xFF070B1A)],
        ),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🌍', style: TextStyle(fontSize: 96)),
          SizedBox(height: 8),
          Text('کره‌ی سه‌بعدی روی دستگاه بارگذاری می‌شود',
              style: TextStyle(color: Color(0xB3FFFFFF))),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.search),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _queryCtrl,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'جستجوی نام یا Earth ID…',
                  border: InputBorder.none,
                ),
              ),
            ),
            const Icon(Icons.public, color: Color(0xFF7C3AED)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
