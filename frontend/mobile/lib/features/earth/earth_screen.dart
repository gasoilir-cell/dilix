import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
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
  final _globe = EarthGlobeController();

  /// نتایجِ جستجو (روی کره تمرکز می‌دهند) و وضعیتِ آن.
  List<NearbyPerson>? _results;
  bool _searching = false;
  String? _searchError;

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
              controller: _globe,
              onTap: _onUserTap,
              fallbackBuilder: _fallbackGlobe,
            ),
          ),
          // نوارِ جستجوی شناور روی کره + فهرستِ نتایج.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                _searchBar(),
                if (_searching || _searchError != null || _results != null)
                  _resultsPanel(),
              ],
            ),
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

  /// جستجو در کاربرانِ کره (نام، Earth ID، شهر/حرفه) و نمایشِ نتایج.
  Future<void> _search() async {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final all = await ApiScope.of(context).earthUsers(limit: 500);
      final needle = q.toLowerCase();
      final hits = all
          .where((u) =>
              (u.displayName ?? '').toLowerCase().contains(needle) ||
              u.earthId.toLowerCase().contains(needle) ||
              (u.profession ?? '').toLowerCase().contains(needle))
          .take(20)
          .toList();
      if (!mounted) return;
      setState(() {
        _results = hits;
        _searching = false;
      });
      // اگر تنها یک نتیجه بود، مستقیم روی همان تمرکز کن.
      if (hits.length == 1) _focusOn(hits.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = '$e';
      });
    }
  }

  void _focusOn(NearbyPerson u) {
    FocusScope.of(context).unfocus();
    _globe.focusOn(u.lat, u.lon);
    setState(() => _results = null);
  }

  void _clearSearch() {
    _queryCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _results = null;
      _searchError = null;
    });
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
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  hintText: 'جستجوی نام یا Earth ID…',
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_queryCtrl.text.isNotEmpty || _results != null)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: _clearSearch,
              )
            else
              const Icon(Icons.public, color: Color(0xFF7C3AED)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _resultsPanel() {
    final results = _results;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 280),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: _searching
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : _searchError != null
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('جستجو ناموفق بود: $_searchError',
                        style: const TextStyle(fontSize: 12)),
                  )
                : (results == null || results.isEmpty)
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('نتیجه‌ای پیدا نشد.'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (ctx, i) => _resultTile(results[i]),
                      ),
      ),
    );
  }

  Widget _resultTile(NearbyPerson u) {
    final name = (u.displayName ?? '').isEmpty ? u.earthId : u.displayName!;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(name.isEmpty ? '؟' : name.characters.first),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [u.earthId, if ((u.profession ?? '').isNotEmpty) u.profession!].join(' • '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        tooltip: 'گفتگو',
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
        onPressed: () {
          FocusScope.of(context).unfocus();
          setState(() => _results = null);
          _openChat(EarthTap(earthId: u.earthId, name: name));
        },
      ),
      onTap: () => _focusOn(u),
    );
  }
}
