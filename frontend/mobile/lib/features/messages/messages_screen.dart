import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../call/call_screen.dart';
import '../call/call_service.dart';

/// پیام‌ها (سند ۷ §۴). Core هنوز endpointِ «لیستِ گفتگوها» ندارد، پس این صفحه
/// گفتگویِ مستقیم را با Earth ID طرفِ مقابل باز می‌کند (ساختِ اتاق + چتِ زنده)
/// روی endpointهایِ واقعیِ `/v1/messaging/...`.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _peerCtrl = TextEditingController();
  String? _myEarthId;
  String? _error;
  bool _busy = false;
  bool _loaded = false;
  List<ChatRoom> _rooms = const [];
  bool _roomsLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void dispose() {
    _peerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated || _loaded) return;
    _loaded = true;
    try {
      final me = await api.me();
      if (mounted) setState(() => _myEarthId = me.earthId);
    } catch (_) {}
    await _loadRooms();
  }

  Future<void> _loadRooms() async {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) return;
    try {
      final rooms = await api.listRooms();
      if (mounted) setState(() {
        _rooms = rooms;
        _roomsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _roomsLoading = false;
        _error = 'بارگذاریِ گفتگوها ممکن نشد: $e';
      });
    }
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatView(
          room: room,
          peerLabel: room.title ?? room.id,
          myEarthId: _myEarthId,
        ),
      ),
    );
    await _loadRooms();
  }

  Future<void> _openChat() async {
    final peer = _peerCtrl.text.trim();
    if (peer.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      final room = await api.createDirectRoom(peer);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            room: room,
            peerLabel: peer,
            myEarthId: _myEarthId,
            peerEarthId: peer,
          ),
        ),
      );
      _peerCtrl.clear();
      await _loadRooms();
    } catch (e) {
      setState(() => _error = 'بازکردنِ گفتگو ممکن نشد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('پیام‌ها')),
      body: !api.isAuthenticated ? _loginPrompt() : _newChatForm(),
    );
  }

  Widget _loginPrompt() {
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

  Widget _roomsSection() {
    if (_roomsLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_rooms.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.forum_outlined),
            title: Text('گفتگوهای شما', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ..._rooms.map(
            (r) => ListTile(
              leading: Icon(r.isE2ee ? Icons.lock_outline : Icons.chat_bubble_outline),
              title: Text(
                r.title ?? '${r.id.substring(0, 8)}…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(r.roomType),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _openRoom(r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _newChatForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _roomsSection(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('گفتگویِ جدید', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Earth ID طرفِ مقابل را وارد کنید تا گفتگوی مستقیم باز شود.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _peerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Earth ID مخاطب',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  onSubmitted: (_) => _busy ? null : _openChat(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openChat,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('بازکردنِ گفتگو'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'نکته: لیستِ گفتگوهای گذشته وقتی در دسترس می‌شود که سرویسِ Core '
            'endpointِ فهرستِ اتاق‌ها را ارائه دهد.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// نمایِ چتِ یک اتاق: بارگذاریِ پیام‌ها + پولِ دوره‌ای + ارسال.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.room,
    required this.peerLabel,
    required this.myEarthId,
    this.peerEarthId,
  });

  final ChatRoom room;
  final String peerLabel;
  final String? myEarthId;

  /// Earth ID طرفِ مقابل برای شروعِ تماس (اگر مشخص باشد).
  final String? peerEarthId;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  String? _error;
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    // پولِ دوره‌ای برای دیدنِ پیامِ جدیدِ طرفِ مقابل بدونِ WebSocket.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final msgs = await ApiScope.of(context).roomMessages(widget.room.id);
      msgs.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      if (initial) _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'بارگذاریِ پیام‌ها ممکن نشد: $e';
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final sent = await ApiScope.of(context).sendMessage(widget.room.id, text);
      _msgCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _error = null;
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => _error = 'ارسالِ پیام ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Earth ID طرفِ مقابل: از پارامترِ صریح یا از فرستندهٔ پیامی که خودم نیستم.
  String? _effectivePeerId() {
    if (widget.peerEarthId != null && widget.peerEarthId!.isNotEmpty) {
      return widget.peerEarthId;
    }
    for (final m in _messages) {
      if (m.senderEarthId.isNotEmpty && m.senderEarthId != widget.myEarthId) {
        return m.senderEarthId;
      }
    }
    return null;
  }

  Future<void> _startCall(String peerId, String peerName, CallMedia media) =>
      startOutgoingCall(context,
          peerId: peerId, peerName: peerName, media: media);

  @override
  Widget build(BuildContext context) {
    final title = widget.room.title ??
        (widget.peerLabel.length > 12
            ? '${widget.peerLabel.substring(0, 12)}…'
            : widget.peerLabel);
    final peerId = _effectivePeerId();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (peerId != null) ...[
            IconButton(
              tooltip: 'تماسِ صوتی',
              icon: const Icon(Icons.call),
              onPressed: () => _startCall(peerId, title, CallMedia.audio),
            ),
            IconButton(
              tooltip: 'تماسِ تصویری',
              icon: const Icon(Icons.videocam),
              onPressed: () => _startCall(peerId, title, CallMedia.video),
            ),
          ],
          if (widget.room.isE2ee)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.lock, size: 18),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
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
    if (_messages.isEmpty) {
      return const Center(child: Text('هنوز پیامی رد و بدل نشده.'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final mine = widget.myEarthId != null && m.senderEarthId == widget.myEarthId;
        return Align(
          alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: mine
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(m.deleted ? '(پیام حذف شد)' : m.content),
          ),
        );
      },
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'پیام…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _sending ? null : _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
