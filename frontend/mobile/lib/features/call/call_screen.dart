import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../app.dart';
import 'call_service.dart';

/// شروعِ یک تماسِ خروجی روی نمونهٔ سراسریِ [CallService] (از `CallScope`).
/// UIِ تماس را overlayِ سراسری در `app.dart` نمایش می‌دهد؛ اینجا فقط آفر
/// فرستاده می‌شود.
Future<void> startOutgoingCall(
  BuildContext context, {
  required String peerId,
  required String peerName,
  required CallMedia media,
}) async {
  final service = CallScope.of(context);
  await service.startCall(peerId: peerId, peerName: peerName, media: media);
}

/// صفحهٔ تماسِ صوتی/تصویری. یک view بدونِ حالت است که وضعیت را از
/// [CallService] می‌خواند؛ بازساختنِ آن با overlayِ سراسری (ListenableBuilder)
/// مدیریت می‌شود و با فازِ idle دیگر نمایش داده نمی‌شود.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key, required this.service});

  final CallService service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final isVideo = s.media == CallMedia.video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo && s.phase == CallPhase.active)
              RTCVideoView(s.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              _audioBackdrop(s),

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
        _roundBtn(Icons.call_end, Colors.red, s.reject, 'رد'),
        _roundBtn(Icons.call, Colors.green, s.accept, 'پاسخ'),
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
          s.toggleMute,
          'میوت',
        ),
        if (isVideo)
          _roundBtn(
            s.camOff ? Icons.videocam_off : Icons.videocam,
            Colors.white24,
            s.toggleCamera,
            'دوربین',
          ),
        if (isVideo)
          _roundBtn(Icons.cameraswitch, Colors.white24, s.switchCamera, 'تعویض'),
        _roundBtn(Icons.call_end, Colors.red, s.hangup, 'قطع'),
      ],
    );
  }

  Widget _roundBtn(
      IconData icon, Color bg, VoidCallback onTap, String tooltip) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: Colors.white, size: 28, semanticLabel: tooltip),
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
