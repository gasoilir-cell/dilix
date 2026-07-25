import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import 'live_service.dart';

/// فهرستِ پخش‌های زنده + ورود به پخش (میزبان یا بیننده).
/// معادلِ صفحهٔ وبِ `app/(main)/live/page.tsx`.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  List<LiveItem> _items = const [];
  bool _loading = true;
  String? _error;
  Timer? _refresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refresh == null) {
      _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _load());
      _load();
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).liveList(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'بارگذاریِ پخش‌ها ممکن نشد: $e';
      });
    }
  }

  Future<void> _open(Widget page) async {
    // حلقهٔ تازه‌سازی حین پخش لازم نیست و درخواستِ بی‌مورد می‌سازد.
    _refresh?.cancel();
    _refresh = null;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پخشِ زنده')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const LiveRoomScreen.broadcast()),
        icon: const Icon(Icons.videocam),
        label: const Text('شروعِ پخش'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _error ?? 'الان کسی پخشِ زنده ندارد.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _tile(_items[i]),
                    ),
            ),
    );
  }

  Widget _tile(LiveItem it) {
    final avatar = AppConfig.absoluteMedia(it.host.avatarUrl);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null ? const Icon(Icons.person_outline) : null,
            ),
            Positioned(
              bottom: -6,
              left: 0,
              right: 0,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('LIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        title: Text(it.title?.isNotEmpty == true ? it.title! : it.host.name),
        subtitle: Text('${it.host.name} • ${it.viewerCount} بیننده'),
        trailing: it.isMine
            ? const Chip(label: Text('پخشِ من'))
            : const Icon(Icons.play_circle_outline),
        onTap: it.isMine
            ? null
            : () => _open(LiveRoomScreen.watch(sessionId: it.sessionId)),
      ),
    );
  }
}

/// اتاقِ پخش — هم برای میزبان و هم بیننده. یک `LiveService` مستقل به‌ازای هر
/// اتاق ساخته می‌شود و با خروج از صفحه آزاد می‌گردد.
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen.broadcast({super.key})
      : sessionId = null,
        isHost = true;

  const LiveRoomScreen.watch({super.key, required String this.sessionId})
      : isHost = false;

  final String? sessionId;
  final bool isHost;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  LiveService? _service;
  final _titleCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  bool _starting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    final s = LiveService(ApiScope.of(context));
    _service = s;
    s.addListener(_onChange);
    s.init().then((_) {
      if (!mounted) return;
      if (!widget.isHost && widget.sessionId != null) s.watch(widget.sessionId!);
      setState(() {});
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final s = _service;
    _titleCtrl.dispose();
    _chatCtrl.dispose();
    if (s != null) {
      s.removeListener(_onChange);
      // خروج از اتاق باید به سرور هم اعلام شود وگرنه پخش «زنده» می‌ماند.
      if (s.role == LiveRole.host) {
        s.stopBroadcast().whenComplete(s.dispose);
      } else if (s.role == LiveRole.viewer) {
        s.leaveWatch().whenComplete(s.dispose);
      } else {
        s.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _start() async {
    final s = _service;
    if (s == null || _starting) return;
    setState(() => _starting = true);
    await s.startBroadcast(title: _titleCtrl.text.trim());
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _send() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();
    await _service?.sendChat(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = _service;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.isHost && s.role == LiveRole.idle) return _setupView(s);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _video(s),
          _topBar(s),
          _chatOverlay(s),
          if (s.ended) _endedOverlay(),
        ],
      ),
    );
  }

  Widget _setupView(LiveService s) {
    return Scaffold(
      appBar: AppBar(title: const Text('شروعِ پخشِ زنده')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(s.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextField(
            controller: _titleCtrl,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'عنوانِ پخش (اختیاری)',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'با شروعِ پخش، دوربین و میکروفنِ شما برای بینندگان ارسال می‌شود. اگر پخشِ بازِ دیگری داشته باشید، بسته می‌شود.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon: _starting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.podcasts),
            label: const Text('شروع'),
          ),
        ],
      ),
    );
  }

  Widget _video(LiveService s) {
    if (s.role == LiveRole.host) {
      return RTCVideoView(
        s.localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    if (s.remoteReady) {
      return RTCVideoView(
        s.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('در حالِ اتصال به پخش…',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _topBar(LiveService s) {
    final title = s.role == LiveRole.host
        ? (_titleCtrl.text.trim().isEmpty ? 'پخشِ من' : _titleCtrl.text.trim())
        : (s.host?.name ?? 'پخشِ زنده');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('LIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Icon(Icons.remove_red_eye_outlined,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text('${s.viewerCount}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 10),
              const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
              const SizedBox(width: 4),
              Text('${s.hearts}',
                  style: const TextStyle(color: Colors.white70)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: s.role == LiveRole.host ? 'پایانِ پخش' : 'خروج',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatOverlay(LiveService s) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: s.chat.length,
                itemBuilder: (_, i) {
                  final m = s.chat[s.chat.length - 1 - i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13),
                        children: [
                          TextSpan(
                            text: '${m.fromName}: ',
                            style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: m.text,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  if (s.role == LiveRole.host) ...[
                    _roundButton(
                      icon: s.micOff ? Icons.mic_off : Icons.mic,
                      onTap: s.toggleMic,
                    ),
                    const SizedBox(width: 8),
                    _roundButton(
                      icon: s.camOff ? Icons.videocam_off : Icons.videocam,
                      onTap: s.toggleCam,
                    ),
                    const SizedBox(width: 8),
                    _roundButton(
                      icon: Icons.cameraswitch_outlined,
                      onTap: s.switchCamera,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _chatCtrl,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'پیام…',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _roundButton(icon: Icons.send, onTap: _send),
                  if (s.role == LiveRole.viewer) ...[
                    const SizedBox(width: 8),
                    _roundButton(
                      icon: Icons.favorite,
                      color: Colors.redAccent,
                      onTap: s.sendHeart,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: Colors.white12,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );

  Widget _endedOverlay() => Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.podcasts, color: Colors.white54, size: 56),
            const SizedBox(height: 12),
            const Text('این پخش پایان یافت.',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('بازگشت'),
            ),
          ],
        ),
      );
}
