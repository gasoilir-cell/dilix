import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';
import '../../core/l10n.dart';
/// فازِ تماس.
enum CallPhase { idle, outgoing, incoming, connecting, active }

/// نوعِ رسانه.
enum CallMedia { audio, video }

/// سرویسِ WebRTC تماسِ صوتی/تصویری، هم‌پروتکل با `CallManager.tsx`ِ وب.
///
/// ⚠ سیگنالینگ **WebSocket نیست**. سرور برای هر Earth ID یک صفِ Redis دارد و
/// کلاینت با `GET /api/v1/calls/poll` هم سیگنال‌ها را برمی‌دارد و هم حضورش را
/// تازه می‌کند (کلیدِ حضور TTL=۱۵ث دارد). پس حلقهٔ poll باید تا وقتی کاربر
/// واردِ حساب است بچرخد، وگرنه دیگران او را «آفلاین» می‌بینند و `invite`
/// بی‌آنکه زنگ بخورد `status=offline` می‌گیرد.
///
/// قرارداد سیگنال‌ها (دقیقاً مثلِ وب):
///   * `sdp` همیشه **رشتهٔ JSON** است، نه شیء: `jsonEncode({type, sdp})`.
///   * کاندیدای ICE هم با `type:'ice'` و همان فیلدِ `sdp` می‌رود (فیلدِ
///     `candidate`ِ سرور استفاده نمی‌شود) — تغییرش سازگاری با وب را می‌شکند.
class CallService extends ChangeNotifier {
  CallService(this._api);

  final ApiClient _api;

  /// وقتی سرور ICE نداد (یا کاربر واردِ حساب نیست) همین‌ها استفاده می‌شوند.
  static const _fallbackIce = <Map<String, dynamic>>[
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  static const _pollInterval = Duration(milliseconds: 1500);
  static const _ringTimeout = Duration(seconds: 35);

  Timer? _pollTimer;
  bool _polling = false;
  List<Map<String, dynamic>>? _iceCache;

  RTCPeerConnection? _pc;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  MediaStream? _localStream;
  final List<Map<String, dynamic>> _pendingLocalIce = [];
  final List<RTCIceCandidate> _pendingRemoteIce = [];
  bool _remoteSet = false;

  CallPhase _phase = CallPhase.idle;
  CallMedia _media = CallMedia.audio;
  String _peerId = '';
  String _peerName = '';
  String? _peerAvatar;
  String _callId = '';
  bool _outgoing = false;
  bool _muted = false;
  bool _camOff = false;
  bool _initialized = false;
  bool _renderersReady = false;
  String? _error;
  String? _pendingOfferSdp;
  Timer? _ringTimer;
  DateTime? _activeSince;
  bool _switching = false;
  bool _captions = false;
  String? _peerCaption;
  Timer? _captionTimer;

  CallPhase get phase => _phase;
  CallMedia get media => _media;
  String get peerId => _peerId;
  String get peerName => _peerName;
  String? get peerAvatar => _peerAvatar;
  bool get muted => _muted;
  bool get camOff => _camOff;
  String? get error => _error;
  bool get isBusy => _phase != CallPhase.idle;

  /// در میانهٔ تعویضِ صوتی↔تصویری (renegotiation) — تا پایان دکمه غیرفعال است.
  bool get switching => _switching;

  /// نمایشِ زیرنویسِ ترجمه‌شدهٔ گفتارِ طرفِ مقابل روشن است؟
  bool get captions => _captions;

  /// آخرین زیرنویسِ دریافتی از طرفِ مقابل، ترجمه‌شده به زبانِ فعالِ اپ.
  String? get peerCaption => _peerCaption;

  /// آماده‌سازیِ رندررها و روشن‌کردنِ حلقهٔ poll. idempotent است و پس از احرازِ
  /// هویت یک‌بار به‌صورتِ سراسری صدا زده می‌شود تا تماسِ ورودی شنیده شود.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // در محیطِ تست پلاگینِ WebRTC وجود ندارد؛ خطای مقداردهیِ رندرر را می‌بلعیم.
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersReady = true;
    } catch (_) {}
    startPolling();
  }

  /// روشن‌کردنِ حلقهٔ حضور/سیگنال. بعد از ورود صدا زده می‌شود.
  void startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
    _tick();
  }

  /// خاموش‌کردنِ حلقه (خروج از حساب) تا درخواستِ ۴۰۱ پشتِ سرِ هم نرود.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// فقط برای تست: تنظیمِ مستقیمِ فاز/طرف بدونِ درگیرکردنِ WebRTC واقعی.
  @visibleForTesting
  void debugSetPhase(
    CallPhase phase, {
    // پیش‌فرضِ پارامتر باید ثابتِ زمانِ کامپایل باشد و `tr()` نیست
    String? peerName,
    CallMedia media = CallMedia.audio,
  }) {
    _phase = phase;
    _peerName = peerName ?? tr('آزمون');
    _media = media;
    notifyListeners();
  }

  Future<void> _tick() async {
    if (_polling || !_api.isAuthenticated) return;
    _polling = true;
    try {
      final signals = await _api.callPoll();
      for (final s in signals) {
        await _handleSignal(s);
      }
    } catch (_) {
      // شبکه/۴۰۱ — حلقه باید زنده بماند تا با برگشتِ اتصال ادامه دهد.
    } finally {
      _polling = false;
    }
  }

  // ─────────── ارسالِ سیگنال ───────────
  Future<void> _signal(String type, {String? sdp, String? text, String? lang}) async {
    if (_callId.isEmpty || _peerId.isEmpty) return;
    try {
      await _api.callSignal(
        callId: _callId,
        toEarthId: _peerId,
        type: type,
        sdp: sdp,
        text: text,
        lang: lang,
      );
    } catch (_) {}
  }

  void _sendIce(Map<String, dynamic> cand) {
    // پیش از گرفتنِ call_id مقصدی نداریم؛ صف می‌کنیم و بعد می‌فرستیم.
    if (_callId.isEmpty || _peerId.isEmpty) {
      _pendingLocalIce.add(cand);
      return;
    }
    _signal('ice', sdp: jsonEncode(cand));
  }

  void _flushLocalIce() {
    final queued = List<Map<String, dynamic>>.from(_pendingLocalIce);
    _pendingLocalIce.clear();
    for (final c in queued) {
      _signal('ice', sdp: jsonEncode(c));
    }
  }

  Future<void> _flushRemoteIce() async {
    final queued = List<RTCIceCandidate>.from(_pendingRemoteIce);
    _pendingRemoteIce.clear();
    for (final c in queued) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
  }

  // ─────────── ساختِ اتصال ───────────
  Future<List<Map<String, dynamic>>> _ice() async {
    if (_iceCache != null) return _iceCache!;
    try {
      final servers = await _api.callIceServers();
      _iceCache = servers.isEmpty ? _fallbackIce : servers;
    } catch (_) {
      _iceCache = _fallbackIce;
    }
    return _iceCache!;
  }

  Future<RTCPeerConnection> _newPeerConnection() async {
    final pc = await createPeerConnection({
      'iceServers': await _ice(),
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _sendIce({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        if (_renderersReady) remoteRenderer.srcObject = event.streams[0];
        notifyListeners();
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (_phase != CallPhase.idle) _finish('failed');
      }
    };
    return pc;
  }

  /// انتظار برای کاملِ‌شدنِ جمع‌آوریِ ICE با سقفِ ۳ثانیه (مثلِ وب).
  /// نیمه‌trickle: offer/answer کامل‌تر می‌رود ولی کاندیداهای بعدی هم می‌روند.
  Future<void> _waitIce(RTCPeerConnection pc) async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    if (await pc.getIceGatheringState() ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) finish();
    };
    Timer(const Duration(seconds: 3), finish);
    await done.future;
  }

  Future<void> _attachLocal() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _media == CallMedia.video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    });
    _localStream = stream;
    if (_renderersReady) localRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      await _pc!.addTrack(track, stream);
    }
    notifyListeners();
  }

  /// SDP روی سیم همیشه **رشتهٔ JSON** است. برای reoffer/reanswer فیلدِ اضافیِ
  /// `media` هم داخلِ همین شیء می‌رود (قراردادِ مشترک با وب).
  String _localDesc(RTCSessionDescription d, {CallMedia? media}) => jsonEncode({
        'type': d.type,
        'sdp': d.sdp,
        if (media != null) 'media': media == CallMedia.video ? 'video' : 'audio',
      });

  // ─────────── تماسِ خروجی ───────────
  Future<void> startCall({
    required String peerId,
    required String peerName,
    required CallMedia media,
  }) async {
    if (_phase != CallPhase.idle) return;
    _error = null;
    _outgoing = true;
    _remoteSet = false;
    _peerId = peerId.toUpperCase();
    _peerName = peerName;
    _peerAvatar = null;
    _media = media;
    _callId = '';
    _phase = CallPhase.outgoing;
    notifyListeners();
    try {
      _pc = await _newPeerConnection();
      await _attachLocal();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _waitIce(_pc!);
      final local = await _pc!.getLocalDescription() ?? offer;
      final (callId, status) = await _api.callInvite(
        toEarthId: _peerId,
        media: media == CallMedia.video ? 'video' : 'audio',
        sdp: _localDesc(local),
      );
      if (status == 'offline') {
        _error = tr('مخاطب در دسترس نیست.');
        _peerId = peerId.toUpperCase();
        await _logCall('no_answer', 0);
        _teardown();
        return;
      }
      _callId = callId;
      _flushLocalIce();
      _ringTimer = Timer(_ringTimeout, () async {
        if (_phase != CallPhase.outgoing) return;
        await _signal('cancel');
        _error = tr('پاسخی داده نشد.');
        await _logCall('no_answer', 0);
        _teardown();
      });
    } catch (_) {
      _error = tr('برقراریِ تماس ناموفق بود.');
      _teardown();
    }
  }

  // ─────────── تماسِ ورودی ───────────
  Future<void> accept() async {
    if (_pendingOfferSdp == null) return;
    _phase = CallPhase.connecting;
    notifyListeners();
    _ringTimer?.cancel();
    try {
      _pc = await _newPeerConnection();
      await _attachLocal();
      final offer = jsonDecode(_pendingOfferSdp!) as Map<String, dynamic>;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
      );
      _remoteSet = true;
      await _flushRemoteIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _waitIce(_pc!);
      final local = await _pc!.getLocalDescription() ?? answer;
      await _signal('answer', sdp: _localDesc(local));
      _flushLocalIce();
      _pendingOfferSdp = null;
      _phase = CallPhase.active;
      _activeSince = DateTime.now();
      notifyListeners();
    } catch (_) {
      _error = tr('پاسخ به تماس ناموفق بود.');
      await _signal('reject');
      _teardown();
    }
  }

  /// ردِ تماسِ ورودی.
  Future<void> reject() async {
    if (_phase == CallPhase.incoming) await _signal('reject');
    _teardown();
  }

  /// قطعِ تماس از سمتِ کاربر.
  Future<void> hangup() async {
    switch (_phase) {
      case CallPhase.outgoing:
        await _signal('cancel');
        await _logCall('no_answer', 0);
        break;
      case CallPhase.incoming:
        await _signal('reject');
        break;
      case CallPhase.connecting:
      case CallPhase.active:
        await _signal('end');
        final d = _durationSeconds();
        await _logCall(d > 0 ? 'answered' : 'no_answer', d);
        break;
      case CallPhase.idle:
        return;
    }
    _teardown();
  }

  // ─────────── دریافتِ سیگنال ───────────
  Future<void> _handleSignal(Map<String, dynamic> s) async {
    final type = s['type'] as String?;
    final callId = (s['call_id'] ?? '') as String;
    switch (type) {
      case 'incoming':
        if (_phase != CallPhase.idle) {
          // مشغولم: به تماس‌گیرنده «busy» می‌گویم بدونِ به‌هم‌ریختنِ تماسِ جاری.
          try {
            await _api.callSignal(
              callId: callId,
              toEarthId: ((s['from'] ?? '') as String).toUpperCase(),
              type: 'busy',
            );
          } catch (_) {}
          return;
        }
        _outgoing = false;
        _remoteSet = false;
        _peerId = ((s['from'] ?? '') as String).toUpperCase();
        _peerName = (s['from_name'] as String?) ?? (s['from'] as String?) ?? tr('تماس');
        _peerAvatar = s['from_avatar'] as String?;
        _callId = callId;
        _pendingOfferSdp = s['sdp'] as String?;
        _media = s['media'] == 'video' ? CallMedia.video : CallMedia.audio;
        _phase = CallPhase.incoming;
        notifyListeners();
        _ringTimer = Timer(_ringTimeout + const Duration(seconds: 5), () {
          if (_phase == CallPhase.incoming) _teardown(); // بی‌پاسخ
        });
        break;

      case 'answer':
        if (!_outgoing || _phase != CallPhase.outgoing || callId != _callId) return;
        _ringTimer?.cancel();
        try {
          final desc = jsonDecode((s['sdp'] ?? '{}') as String) as Map<String, dynamic>;
          await _pc!.setRemoteDescription(
            RTCSessionDescription(desc['sdp'] as String?, desc['type'] as String?),
          );
          _remoteSet = true;
          await _flushRemoteIce();
          _phase = CallPhase.active;
          _activeSince = DateTime.now();
          notifyListeners();
        } catch (_) {
          _error = tr('اتصال ناموفق بود.');
          await _logCall('failed', 0);
          _teardown();
        }
        break;

      case 'reject':
        if (_outgoing && _phase == CallPhase.outgoing && callId == _callId) {
          _error = tr('تماس رد شد.');
          await _logCall('rejected', 0);
          _teardown();
        }
        break;

      case 'busy':
        if (_outgoing && _phase == CallPhase.outgoing && callId == _callId) {
          _error = tr('مخاطب مشغول است.');
          await _logCall('no_answer', 0);
          _teardown();
        }
        break;

      case 'cancel':
        if (!_outgoing && _phase == CallPhase.incoming && callId == _callId) {
          _teardown(); // تماس‌گیرنده منصرف شد؛ لاگ را خودش می‌زند.
        }
        break;

      case 'end':
        if ((_phase == CallPhase.active || _phase == CallPhase.connecting) &&
            callId == _callId) {
          final d = _durationSeconds();
          if (_outgoing) await _logCall(d > 0 ? 'answered' : 'no_answer', d);
          _teardown();
        }
        break;

      // طرفِ مقابل نوعِ تماس را عوض کرده: پیشنهادِ تازه‌اش را می‌پذیریم، رسانهٔ
      // محلی را با آن هم‌تراز می‌کنیم و `reanswer` برمی‌گردانیم.
      case 'reoffer':
        if (!_inCall(callId) || _pc == null) return;
        try {
          final desc = jsonDecode((s['sdp'] ?? '{}') as String)
              as Map<String, dynamic>;
          final target =
              desc['media'] == 'video' ? CallMedia.video : CallMedia.audio;
          await _pc!.setRemoteDescription(
            RTCSessionDescription(desc['sdp'] as String?, desc['type'] as String?),
          );
          _remoteSet = true;
          await _flushRemoteIce();
          if (target != _media) {
            try {
              await _applyLocalMedia(target);
            } catch (_) {
              // دوربین در دسترس نبود؛ تماس نباید بیفتد — صدا برقرار می‌مانَد.
            }
          }
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          await _waitIce(_pc!);
          final local = await _pc!.getLocalDescription() ?? answer;
          await _signal('reanswer', sdp: _localDesc(local, media: _media));
        } catch (_) {}
        break;

      case 'reanswer':
        if (!_inCall(callId) || _pc == null) return;
        try {
          final desc = jsonDecode((s['sdp'] ?? '{}') as String)
              as Map<String, dynamic>;
          await _pc!.setRemoteDescription(
            RTCSessionDescription(desc['sdp'] as String?, desc['type'] as String?),
          );
          _remoteSet = true;
          await _flushRemoteIce();
        } catch (_) {}
        break;

      // زیرنویسِ گفتارِ طرفِ مقابل. متن به زبانِ **او**ست؛ به زبانِ فعالِ اپ
      // ترجمه و چند ثانیه نمایش داده می‌شود.
      case 'caption':
        if (!_captions || !_inCall(callId)) return;
        final text = (s['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        var shown = text;
        try {
          final res = await _api.translateText(text, L10n.language);
          if (res.translatedText.trim().isNotEmpty) shown = res.translatedText;
        } catch (_) {
          // ترجمه نشد؛ متنِ خام بهتر از هیچ است.
        }
        if (!_inCall(callId)) return; // تماس در فاصلهٔ ترجمه تمام شد
        _peerCaption = shown;
        notifyListeners();
        _captionTimer?.cancel();
        _captionTimer = Timer(const Duration(seconds: 8), () {
          _peerCaption = null;
          notifyListeners();
        });
        break;

      case 'ice':
        if (callId != _callId || s['sdp'] == null) return;
        try {
          final c = jsonDecode(s['sdp'] as String) as Map<String, dynamic>;
          final cand = RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            (c['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (_pc != null && _remoteSet) {
            await _pc!.addCandidate(cand);
          } else {
            _pendingRemoteIce.add(cand);
          }
        } catch (_) {}
        break;
    }
  }

  // ─────────── کنترل‌ها ───────────
  void toggleMute() {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    _camOff = !_camOff;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_camOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  /// روشن/خاموش‌کردنِ زیرنویسِ ترجمهٔ همزمان (سمتِ **دریافت**).
  ///
  /// گفتارِ طرفِ مقابل را او خودش با سیگنالِ `caption` می‌فرستد؛ اینجا فقط به
  /// زبانِ فعالِ اپ ترجمه و نمایش داده می‌شود.
  void toggleCaptions() {
    _captions = !_captions;
    if (!_captions) {
      _captionTimer?.cancel();
      _peerCaption = null;
    }
    notifyListeners();
  }

  // ─────────── تعویضِ صوتی ↔ تصویری (renegotiation) ───────────

  /// تغییرِ نوعِ رسانه در میانهٔ تماسِ برقرار.
  ///
  /// هم‌پروتکل با `CallManager.tsx`: پیشنهادِ تازه با سیگنالِ `reoffer` می‌رود و
  /// **نوعِ مقصد داخلِ خودِ JSONِ SDP** (فیلدِ `media`) حمل می‌شود، چون سرور
  /// فیلدِ جداگانه‌ای برای آن ندارد. تغییرِ این قرارداد سازگاری با وب را می‌شکند.
  Future<void> switchMedia(CallMedia target) async {
    if (_pc == null ||
        _phase != CallPhase.active ||
        _media == target ||
        _switching) {
      return;
    }
    _switching = true;
    notifyListeners();
    try {
      await _applyLocalMedia(target);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _waitIce(_pc!);
      final local = await _pc!.getLocalDescription() ?? offer;
      await _signal('reoffer', sdp: _localDesc(local, media: target));
    } catch (_) {
      _error = tr('تغییرِ حالتِ تماس ناموفق بود.');
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// افزودن/برداشتنِ مسیرِ ویدیو روی اتصالِ فعلی، بدونِ دست‌زدن به صدا.
  ///
  /// صدا عمداً دست‌نخورده می‌مانَد: گرفتنِ دوبارهٔ میکروفن وسطِ تماس باعثِ پرشِ
  /// صوتی و از‌دست‌رفتنِ وضعیتِ میوت می‌شود.
  Future<void> _applyLocalMedia(CallMedia target) async {
    if (target == CallMedia.video) {
      final has = (_localStream?.getVideoTracks().length ?? 0) > 0;
      if (!has) {
        final cam = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {'facingMode': 'user', 'width': 640, 'height': 480},
        });
        final track = cam.getVideoTracks().first;
        // خودِ `cam` عمداً dispose نمی‌شود: مسیرش هنوز زنده و در حالِ ارسال است.
        _localStream ??= cam;
        if (!identical(_localStream, cam)) {
          await _localStream!.addTrack(track);
        }
        await _pc!.addTrack(track, _localStream!);
      }
    } else {
      final senders = await _pc!.getSenders();
      for (final s in senders) {
        if (s.track?.kind != 'video') continue;
        try {
          await _pc!.removeTrack(s);
        } catch (_) {}
      }
      for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        try {
          await t.stop();
          await _localStream!.removeTrack(t);
        } catch (_) {}
      }
    }
    _media = target;
    _camOff = false;
    // بازتخصیصِ srcObject لازم است: افزودنِ مسیر به استریمِ موجود به‌تنهایی
    // رندررِ محلی را تازه نمی‌کند و پیش‌نمایش سیاه می‌مانَد.
    if (_renderersReady) localRenderer.srcObject = _localStream;
    notifyListeners();
  }

  /// سیگنال متعلق به همین تماسِ در جریان است؟ (برای reoffer/reanswer/caption)
  bool _inCall(String callId) =>
      callId == _callId &&
      _callId.isNotEmpty &&
      (_phase == CallPhase.active || _phase == CallPhase.connecting);

  int _durationSeconds() {
    final since = _activeSince;
    if (since == null) return 0;
    return DateTime.now().difference(since).inSeconds;
  }

  Future<void> _logCall(String status, int seconds) async {
    if (!_outgoing || _peerId.isEmpty) return; // فقط تماس‌گیرنده لاگ می‌زند.
    try {
      await _api.callLog(
        toEarthId: _peerId,
        media: _media == CallMedia.video ? 'video' : 'audio',
        status: status,
        durationSeconds: seconds,
      );
    } catch (_) {}
  }

  /// پایانِ ناخواسته (خطای اتصال): به طرفِ مقابل خبر می‌دهد و پاک می‌کند.
  Future<void> _finish(String reason) async {
    await _signal('end');
    final d = _durationSeconds();
    if (_outgoing) await _logCall(d > 0 ? 'answered' : reason, d);
    _teardown();
  }

  void _teardown() {
    _ringTimer?.cancel();
    _ringTimer = null;
    _captionTimer?.cancel();
    _captionTimer = null;
    _peerCaption = null;
    _switching = false;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    _localStream = null;
    // رندررها فقط پس از initialize() موفق اجازهٔ تنظیمِ srcObject دارند؛
    // وگرنه (مثلاً پلاگینِ WebRTC در محیطِ تست/دستگاه در دسترس نبود) استثنا می‌دهند.
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    _pendingLocalIce.clear();
    _pendingRemoteIce.clear();
    _remoteSet = false;
    _pendingOfferSdp = null;
    _peerId = '';
    _peerName = '';
    _peerAvatar = null;
    _callId = '';
    _outgoing = false;
    _muted = false;
    _camOff = false;
    _activeSince = null;
    _phase = CallPhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    _teardown();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
