import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../app.dart';
import '../../core/config.dart';
import 'call_service.dart';

import '../../core/l10n.dart';
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
            // در تماسِ گروهی ممکن است نفرِ اول رفته باشد ولی بقیه بمانند؛ آن‌وقت
            // رندررِ اصلی خالی است و نباید یک مستطیلِ سیاه را به‌جای تصویر نشان داد.
            if (isVideo && s.phase == CallPhase.active && s.primaryActive)
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
                  child: RTCVideoView(s.localRenderer, mirror: !s.screenSharing),
                ),
              ),

            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    _title(s),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(_statusLabel(s.phase),
                      style: const TextStyle(color: Colors.white70)),
                  if (s.peerSharingScreen) ...[
                    const SizedBox(height: 6),
                    Text(tr('در حالِ اشتراکِ صفحه'),
                        style: const TextStyle(color: Colors.lightBlueAccent)),
                  ],
                  if (s.error != null) ...[
                    const SizedBox(height: 6),
                    Text(s.error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),

            if (s.participants.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 200,
                height: 110,
                child: _participantStrip(s),
              ),

            if (s.captions && (s.peerCaption ?? '').isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 140,
                child: _captionBar(s.peerCaption!),
              ),

            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: s.phase == CallPhase.incoming
                  ? _incomingControls(s)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (s.phase == CallPhase.active)
                          _secondaryControls(context, s, isVideo),
                        if (s.phase == CallPhase.active)
                          const SizedBox(height: 14),
                        _activeControls(s, isVideo),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// در تماسِ دونفره نامِ طرف، در گروه نام + شمارِ بقیه.
  String _title(CallService s) {
    final base = s.peerName.isNotEmpty ? s.peerName : tr('تماس');
    if (s.participants.isEmpty) return base;
    return tr('{0} و {1} نفرِ دیگر', [base, s.participants.length]);
  }

  Widget _audioBackdrop(CallService s) {
    final avatar = AppConfig.absoluteMedia(s.peerAvatar);
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: CircleAvatar(
        radius: 56,
        backgroundColor: Colors.white12,
        backgroundImage: avatar != null ? NetworkImage(avatar) : null,
        child: avatar != null
            ? null
            : Icon(
                s.media == CallMedia.video ? Icons.videocam : Icons.person,
                size: 56,
                color: Colors.white70,
              ),
      ),
    );
  }

  /// نوارِ زیرنویس. متن ترجمه‌شده می‌رسد، پس جهتِ متن باید از خودِ متن استنتاج
  /// شود و نه از جهتِ اپ — وگرنه زیرنویسِ انگلیسی در چیدمانِ RTL می‌شکند.
  Widget _captionBar(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }

  /// ردیفِ افقیِ شرکت‌کنندگانِ اضافه (تماسِ گروهی، شبکهٔ mesh).
  Widget _participantStrip(CallService s) {
    final items = s.participants;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final p = items[i];
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 90,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (p.rendererReady && p.remoteSet)
                  RTCVideoView(p.renderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                else
                  Container(
                    color: Colors.white10,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person,
                        color: Colors.white54, size: 30),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: Text(
                      p.name.isNotEmpty ? p.name : p.earthId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _incomingControls(CallService s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(Icons.call_end, Colors.red, s.reject, tr('رد')),
        _roundBtn(Icons.call, Colors.green, s.accept, tr('پاسخ')),
      ],
    );
  }

  /// ردیفِ بالا: قابلیت‌هایی که تماس را قطع نمی‌کنند.
  ///
  /// عمداً هیچ‌کدام از آیکون‌های `mic`/`call`/`call_end` اینجا تکرار نمی‌شوند تا
  /// ردیفِ اصلی همچنان تک‌مرجعِ آن کنش‌ها بماند.
  Widget _secondaryControls(BuildContext context, CallService s, bool isVideo) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _smallBtn(
          isVideo ? Icons.volume_up : Icons.video_call,
          s.switching
              ? null
              : () => s.switchMedia(
                  isVideo ? CallMedia.audio : CallMedia.video),
          isVideo ? tr('فقط صدا') : tr('تصویری'),
          active: false,
        ),
        _smallBtn(
          s.captions ? Icons.closed_caption : Icons.closed_caption_off,
          s.toggleCaptions,
          tr('زیرنویس'),
          active: s.captions,
        ),
        _smallBtn(
          s.screenSharing ? Icons.stop_screen_share : Icons.screen_share,
          s.toggleScreenShare,
          tr('اشتراکِ صفحه'),
          active: s.screenSharing,
        ),
        _smallBtn(
          Icons.person_add,
          s.canInvite ? () => _promptInvite(context, s) : null,
          tr('افزودنِ نفر'),
          active: false,
        ),
      ],
    );
  }

  /// دعوتِ نفرِ بعدی به همین تماس با Earth IDِ او.
  Future<void> _promptInvite(BuildContext context, CallService s) async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr('افزودنِ نفر به تماس')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          // «Earth ID» در کلِ اپ ترجمه نمی‌شود (داشبورد و جستجوی کره هم همین
          // را نشان می‌دهند)؛ اسمِ فیلدِ محصول است، نه یک واژهٔ عمومی.
          decoration: const InputDecoration(hintText: 'Earth ID'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(tr('انصراف')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text.trim()),
            child: Text(tr('دعوت')),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;
    await s.addParticipant(id, id);
  }

  Widget _activeControls(CallService s, bool isVideo) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(
          s.muted ? Icons.mic_off : Icons.mic,
          Colors.white24,
          s.toggleMute,
          tr('میوت'),
        ),
        if (isVideo)
          _roundBtn(
            s.camOff ? Icons.videocam_off : Icons.videocam,
            Colors.white24,
            s.toggleCamera,
            tr('دوربین'),
          ),
        if (isVideo)
          _roundBtn(Icons.cameraswitch, Colors.white24, s.switchCamera, tr('تعویض')),
        _roundBtn(Icons.call_end, Colors.red, s.hangup, tr('قطع')),
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

  /// دکمهٔ کوچکِ ردیفِ بالا. `onTap == null` یعنی در این لحظه در دسترس نیست
  /// (مثلاً وسطِ renegotiation یا پرشدنِ سقفِ شرکت‌کنندگان).
  Widget _smallBtn(IconData icon, VoidCallback? onTap, String tooltip,
      {required bool active}) {
    final color = onTap == null
        ? Colors.white24
        : (active ? Colors.lightBlueAccent : Colors.white);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: active ? Colors.white24 : Colors.white10,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Icon(icon, color: color, size: 22, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }

  String _statusLabel(CallPhase phase) {
    switch (phase) {
      case CallPhase.outgoing:
        return tr('در حالِ تماس…');
      case CallPhase.incoming:
        return tr('تماسِ ورودی');
      case CallPhase.connecting:
        return tr('در حالِ اتصال…');
      case CallPhase.active:
        return tr('برقرار');
      case CallPhase.idle:
        return tr('پایان');
    }
  }
}
