import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../app.dart';
import 'call_service.dart';

/// شروعِ یک تماسِ خروجی: سرویس را می‌سازد، به سیگنالینگ وصل می‌شود، آفر را
/// می‌فرستد و صفحهٔ تماس را باز می‌کند. سرویس با بستنِ صفحه dispose می‌شود.
Future<void> startOutgoingCall(
  BuildContext context, {
  required String peerId,
  required String peerName,
  required CallMedia media,
}) async {
  final service = CallService(ApiScope.of(context));
  await service.init();
  await service.startCall(peerId: peerId, peerName: peerName, media: media);
  if (!context.mounted) {
    service.dispose();
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CallScreen(service: service, owned: true),
    ),
  );
}

/// صفحهٔ تماسِ صوتی/تصویری. با تغییرِ فاز به idle خودکار بسته می‌شود.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.service, this.owned = false});

  final CallService service;

  /// اگر true، این صفحه مالکِ سرویس است و هنگامِ بسته‌شدن آن را dispose می‌کند.
  final bool owned;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onChange);
    if (widget.owned) widget.service.dispose();
    super.dispose();
  }

  void _onChange() {
    if (widget.service.phase == CallPhase.idle && !_popped && mounted) {
      _popped = true;
      Navigator.of(context).maybePop();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final isVideo = s.media == CallMedia.video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ویدیوی طرفِ مقابل (تمام‌صفحه) یا آواتارِ صوتی
            if (isVideo && s.phase == CallPhase.active)
              RTCVideoView(s.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              _audioBackdrop(s),

            // ویدیوی خودم (PiP)
            if (isVideo)
              Positioned(
                top: 16,
                right: 16,
                width: 110,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(s.localRenderer, mirror: true),
                ),
              ),

            // عنوان/وضعیت
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    s.peerName.isNotEmpty ? s.peerName : 'تماس',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(_statusLabel(s.phase),
                      style: const TextStyle(color: Colors.white70)),
                  if (s.error != null) ...[
                    const SizedBox(height: 6),
                    Text(s.error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),

            // کنترل‌ها
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: s.phase == CallPhase.incoming
                  ? _incomingControls(s)
                  : _activeControls(s, isVideo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioBackdrop(CallService s) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: CircleAvatar(
        radius: 56,
        backgroundColor: Colors.white12,
        child: Icon(
          s.media == CallMedia.video ? Icons.videocam : Icons.person,
          size: 56,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _incomingControls(CallService s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(Icons.call_end, Colors.red, () => s.reject()),
        _roundBtn(Icons.call, Colors.green, () => s.accept()),
      ],
    );
  }

  Widget _activeControls(CallService s, bool isVideo) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(
          s.muted ? Icons.mic_off : Icons.mic,
          Colors.white24,
          () => s.toggleMute(),
        ),
        if (isVideo)
          _roundBtn(
            s.camOff ? Icons.videocam_off : Icons.videocam,
            Colors.white24,
            () => s.toggleCamera(),
          ),
        if (isVideo)
          _roundBtn(Icons.cameraswitch, Colors.white24, () => s.switchCamera()),
        _roundBtn(Icons.call_end, Colors.red, () => s.hangup()),
      ],
    );
  }

  Widget _roundBtn(IconData icon, Color bg, VoidCallback onTap) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  String _statusLabel(CallPhase phase) {
    switch (phase) {
      case CallPhase.outgoing:
        return 'در حالِ تماس…';
      case CallPhase.incoming:
        return 'تماسِ ورودی';
      case CallPhase.connecting:
        return 'در حالِ اتصال…';
      case CallPhase.active:
        return 'برقرار';
      case CallPhase.idle:
        return 'پایان';
    }
  }
}
