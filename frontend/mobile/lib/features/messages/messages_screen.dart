import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../models/models.dart';
import 'chat_screen.dart';

/// پیام‌ها (سند ۷ §۴) — فهرستِ **بومیِ** گفتگوها.
///
/// گفتگوها را از `GET /messages/rooms` می‌گیرد و هر ۱۰ث پول می‌کند تا پیامِ نو و
/// شمارندهٔ نخوانده به‌روز بماند. لمسِ هر گفتگو نمای بومیِ [ChatScreen] را باز
/// می‌کند. در حالتِ ناواردشده پرامپتِ ورود نشان داده می‌شود.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _rooms = <ChatRoom>[];
  Timer? _poll;
  bool _loading = true;
  String? _error;
  bool _started = false;

  ApiClient get _api => ApiScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && _api.isAuthenticated) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _load();
        _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _api.listRooms();
      if (!mounted) return;
      setState(() {
        _rooms
          ..clear()
          ..addAll(list);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)),
    );
    _load(); // بازگشت از چت: شمارندهٔ نخوانده به‌روز شود.
  }

  @override
  Widget build(BuildContext context) {
    if (!_api.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('پیام‌ها')),
        body: _loginPrompt(context),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('پیام‌ها')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rooms.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 8),
          Center(child: Text('بارگذاریِ گفتگوها ناموفق بود.\n$_error',
              textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('تلاشِ دوباره')),
          ),
        ],
      );
    }
    if (_rooms.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 140),
          Icon(Icons.forum_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Center(child: Text('هنوز گفتگویی نداری.\nاز کره یک نفر را انتخاب کن.',
              textAlign: TextAlign.center)),
        ],
      );
    }
    return ListView.separated(
      itemCount: _rooms.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (ctx, i) => _roomTile(_rooms[i]),
    );
  }

  Widget _roomTile(ChatRoom room) {
    final hasAvatar = room.partnerAvatar != null && room.partnerAvatar!.isNotEmpty;
    return ListTile(
      onTap: () => _openRoom(room),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: hasAvatar ? NetworkImage(room.partnerAvatar!) : null,
            child: !hasAvatar
                ? Text(room.displayTitle.isNotEmpty
                    ? room.displayTitle.characters.first
                    : '؟')
                : null,
          ),
          if (room.partnerOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(room.displayTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(room.lastMessage ?? 'بدون پیام',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (room.lastMessageAt != null)
            Text(_time(room.lastMessageAt!),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          if (room.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${room.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  String _time(DateTime t) {
    final l = t.toLocal();
    final now = DateTime.now();
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }
    return '${l.year}/${l.month}/${l.day}';
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
