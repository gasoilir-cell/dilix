import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../models/models.dart';
import '../call/call_service.dart';

/// نمای بومیِ گفتگو (سند ۷ §۴).
///
/// پیام‌ها را از `GET /messages/rooms/{id}/messages` می‌گیرد و هر ۵ث پول می‌کند
/// (هم‌راستا با وبِ زنده که realtime را با polling می‌سازد، نه WebSocket). ارسالِ
/// متن با `POST .../messages`. دکمه‌های تماسِ صوتی/تصویری از سرویسِ WebRTCِ موجودِ
/// اپ استفاده می‌کنند.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.room});

  final ChatRoom room;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _messages = <ChatMessage>[];
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  ApiClient get _api => ApiScope.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load(initial: true);
      _markRead();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final list = await _api.roomMessages(widget.room.id, limit: 50);
      if (!mounted) return;
      final wasAtBottom = _isNearBottom();
      final hadNew = list.length != _messages.length ||
          (list.isNotEmpty &&
              _messages.isNotEmpty &&
              list.last.id != _messages.last.id);
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _loading = false;
        _error = null;
      });
      if (initial || (hadNew && wasAtBottom)) _scrollToBottom();
      if (hadNew && !initial) _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (initial) _error = '$e';
      });
    }
  }

  Future<void> _markRead() async {
    try {
      await _api.markRoomRead(widget.room.id);
    } catch (_) {}
  }

  bool _isNearBottom() {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return pos.maxScrollExtent - pos.pixels < 120;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await _api.sendMessage(widget.room.id, text);
      _inputCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ارسال ناموفق بود: $e')));
    }
  }

  void _startCall(CallMedia media) {
    final peerId = widget.room.partnerEarthId;
    if (peerId == null || peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تماس فقط در گفتگویِ مستقیم ممکن است.')),
      );
      return;
    }
    CallScope.of(context).startCall(
      peerId: peerId,
      peerName: widget.room.displayTitle,
      media: media,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final isDirect = room.partnerEarthId != null && room.partnerEarthId!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  room.partnerOnline ? const Color(0xFF22C55E) : Colors.grey,
              backgroundImage: (room.partnerAvatar != null &&
                      room.partnerAvatar!.isNotEmpty)
                  ? NetworkImage(room.partnerAvatar!)
                  : null,
              child: (room.partnerAvatar == null || room.partnerAvatar!.isEmpty)
                  ? Text(
                      room.displayTitle.isNotEmpty
                          ? room.displayTitle.characters.first
                          : '؟',
                      style: const TextStyle(color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(room.displayTitle,
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    room.partnerOnline ? 'آنلاین' : 'آفلاین',
                    style: TextStyle(
                        fontSize: 12,
                        color: room.partnerOnline
                            ? const Color(0xFF22C55E)
                            : Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (isDirect) ...[
            IconButton(
              tooltip: 'تماسِ صوتی',
              icon: const Icon(Icons.call),
              onPressed: () => _startCall(CallMedia.audio),
            ),
            IconButton(
              tooltip: 'تماسِ تصویری',
              icon: const Icon(Icons.videocam),
              onPressed: () => _startCall(CallMedia.video),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _composer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 8),
              Text('بارگذاریِ گفتگو ناموفق بود.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () => _load(initial: true),
                  child: const Text('تلاشِ دوباره')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('هنوز پیامی نیست. اولین پیام را بفرست.'));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.isMine;
    final theme = Theme.of(context);
    final bg = mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final text = m.deleted ? 'این پیام حذف شد' : m.content;
    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 2 : 14),
            bottomRight: Radius.circular(mine ? 14 : 2),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (m.mediaUrl != null &&
                m.mediaUrl!.isNotEmpty &&
                m.mediaType == 'image')
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(m.mediaUrl!,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image)),
                ),
              ),
            Text(
              text,
              style: TextStyle(
                  color: fg,
                  fontStyle:
                      m.deleted ? FontStyle.italic : FontStyle.normal),
            ),
            const SizedBox(height: 2),
            Text(
              _time(m.sentAt) + (m.edited ? ' • ویرایش' : ''),
              style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime t) {
    final l = t.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'پیام…',
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
