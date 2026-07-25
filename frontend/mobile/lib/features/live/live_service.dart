import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';

/// نقشِ من در نشستِ زنده.
enum LiveRole { idle, host, viewer }

/// موتورِ پخشِ زنده روی همان سیگنالینگِ HTTP+Redisِ سرور.
///
/// معماری **mesh** است: میزبان به‌ازای هر بیننده یک `RTCPeerConnection` جدا
/// می‌سازد و همان استریمِ محلی را روی همه‌شان می‌فرستد. سرور SFU ندارد، پس
/// تعدادِ بینندهٔ هم‌زمان به پهنای‌باندِ آپلودِ میزبان محدود است.
///
/// ⚠ برخلافِ ماژولِ تماس، اینجا **trickle ICE استفاده نمی‌شود**: مرجعِ وب
/// کاندیداها را جدا نمی‌فرستد و فقط بعد از کاملِ‌شدنِ جمع‌آوری (سقفِ ۳ث)
/// توضیحِ کاملِ SDP را می‌فرستد. اگر اینجا trickle کنیم، سمتِ وب کاندیدا را
/// نادیده می‌گیرد و اتصال نیمه‌کاره می‌ماند.
class LiveService extends ChangeNotifier {
  LiveService(this._api);

  final ApiClient _api;

  static const _fallbackIce = <Map<String, dynamic>>[
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];
  static const _pollInterval = Duration(milliseconds: 1500);
  static const _stateInterval = Duration(milliseconds: 2500);

  // ── وضعیتِ مشترک ──
  LiveRole _role = LiveRole.idle;
  String _sessionId = '';
  List<Map<String, dynamic>> _iceServers = _fallbackIce;
  int _viewerCount = 0;
  int _hearts = 0;
  bool _ended = false;
  String? _error;
  List<LiveChatMessage> _chat = const [];

  Timer? _pollTimer;
  Timer? _stateTimer;
  bool _pollBusy = false;

  // ── میزبان ──
  MediaStream? _localStream;
  final _peers = <String, RTCPeerConnection>{};
  bool _micOff = false;
  bool _camOff = false;

  // ── بیننده ──
  RTCPeerConnection? _viewerPc;
  String _hostEarthId = '';
  LiveHost? _host;
  bool _remoteReady = false;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  LiveRole get role => _role;
  String get sessionId => _sessionId;
  int get viewerCount => _viewerCount;
  int get hearts => _hearts;
  bool get ended => _ended;
  String? get error => _error;
  List<LiveChatMessage> get chat => _chat;
  LiveHost? get host => _host;
  bool get micOff => _micOff;
  bool get camOff => _camOff;
  bool get remoteReady => _remoteReady;
  bool get active => _role != LiveRole.idle;

  Future<void> init() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  // ─────────────── میزبان ───────────────

  /// شروعِ پخش: اول دوربین را می‌گیریم و بعد نشست را می‌سازیم، تا اگر کاربر
  /// اجازهٔ دوربین را رد کرد، نشستِ زنده‌ی بی‌تصویر روی سرور باقی نماند.
  Future<bool> startBroadcast({String? title}) async {
    if (_role != LiveRole.idle) return false;
    _error = null;
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
    } catch (e) {
      _error = 'دسترسی به دوربین/میکروفن ممکن نشد.';
      notifyListeners();
      return false;
    }
    try {
      final (sid, ice) = await _api.liveStart(title: title);
      _sessionId = sid;
      _iceServers = ice.isEmpty ? _fallbackIce : ice;
    } catch (e) {
      await _disposeLocal();
      _error = 'شروعِ پخش ممکن نشد: $e';
      notifyListeners();
      return false;
    }
    if (_renderersReady) localRenderer.srcObject = _localStream;
    _role = LiveRole.host;
    _micOff = false;
    _camOff = false;
    _ended = false;
    _startLoops();
    notifyListeners();
    return true;
  }

  Future<void> stopBroadcast() async {
    if (_role != LiveRole.host) return;
    final sid = _sessionId;
    _stopLoops();
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    await _disposeLocal();
    _reset();
    notifyListeners();
    if (sid.isNotEmpty) {
      try {
        await _api.liveStop(sid);
      } catch (_) {}
    }
  }

  void toggleMic() {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    if (tracks.isEmpty) return;
    _micOff = !_micOff;
    for (final t in tracks) {
      t.enabled = !_micOff;
    }
    notifyListeners();
  }

  void toggleCam() {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    _camOff = !_camOff;
    for (final t in tracks) {
      t.enabled = !_camOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  /// ساختِ اتصالِ تازه برای یک بیننده و ارسالِ offer.
  Future<void> _offerToViewer(String viewer) async {
    final stream = _localStream;
    if (stream == null || _sessionId.isEmpty) return;
    try {
      final old = _peers.remove(viewer);
      if (old != null) await old.close();

      final pc = await _newPeer();
      _peers[viewer] = pc;
      pc.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _peers.remove(viewer)?.close();
        }
      };
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitIce(pc);
      final local = await pc.getLocalDescription();
      if (local == null) return;
      await _api.liveSignal(
        sessionId: _sessionId,
        toEarthId: viewer,
        type: 'offer',
        sdp: _desc(local),
      );
    } catch (_) {
      // بینندهٔ منفرد ممکن است قطع شده باشد؛ پخش نباید متوقف شود.
    }
  }

  // ─────────────── بیننده ───────────────

  /// پیوستن به یک پخش. اگر پخش تمام شده باشد سرور ۴۱۰ می‌دهد و [ended] می‌شود.
  Future<bool> watch(String sessionId) async {
    if (_role != LiveRole.idle) return false;
    _error = null;
    try {
      final info = await _api.liveJoin(sessionId);
      if (info.isHost) {
        _error = 'این پخشِ خودت است؛ از حالتِ میزبان مدیریتش کن.';
        notifyListeners();
        return false;
      }
      _sessionId = sessionId;
      _hostEarthId = info.hostEarthId;
      _host = info.host;
      _iceServers = info.iceServers.isEmpty ? _fallbackIce : info.iceServers;
      _viewerCount = info.viewerCount;
      _hearts = info.hearts;
      _ended = false;
      _remoteReady = false;
      _role = LiveRole.viewer;
      _startLoops();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '$e'.contains('410')
          ? 'این پخش پایان یافته است.'
          : 'پیوستن ممکن نشد: $e';
      _ended = '$e'.contains('410');
      notifyListeners();
      return false;
    }
  }

  Future<void> leaveWatch() async {
    if (_role != LiveRole.viewer) return;
    final sid = _sessionId;
    _stopLoops();
    await _viewerPc?.close();
    _viewerPc = null;
    if (_renderersReady) remoteRenderer.srcObject = null;
    _reset();
    notifyListeners();
    if (sid.isNotEmpty) {
      try {
        await _api.liveLeave(sid);
      } catch (_) {}
    }
  }

  /// پاسخ به offerِ میزبان. بیننده هیچ trackی نمی‌فرستد (تماشای یک‌طرفه).
  Future<void> _answerHost(Map<String, dynamic> signal) async {
    final sdp = signal['sdp'] as String?;
    final from = (signal['from'] ?? '') as String;
    if (sdp == null || from.isEmpty || from != _hostEarthId) return;
    try {
      await _viewerPc?.close();
      final pc = await _newPeer();
      _viewerPc = pc;
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          if (_renderersReady) remoteRenderer.srcObject = event.streams.first;
          _remoteReady = true;
          notifyListeners();
        }
      };
      final remote = jsonDecode(sdp) as Map<String, dynamic>;
      await pc.setRemoteDescription(RTCSessionDescription(
        remote['sdp'] as String?,
        remote['type'] as String?,
      ));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _waitIce(pc);
      final local = await pc.getLocalDescription();
      if (local == null) return;
      await _api.liveSignal(
        sessionId: _sessionId,
        toEarthId: from,
        type: 'answer',
        sdp: _desc(local),
      );
    } catch (e) {
      _error = 'اتصال به پخش برقرار نشد.';
      notifyListeners();
    }
  }

  // ─────────────── چت و قلب ───────────────

  Future<void> sendChat(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _sessionId.isEmpty) return;
    try {
      final sent = await _api.liveChat(_sessionId, msg);
      _chat = [..._chat.where((m) => m.id != sent.id), sent];
      notifyListeners();
    } catch (_) {
      _error = 'ارسالِ پیام ممکن نشد.';
      notifyListeners();
    }
  }

  Future<void> sendHeart() async {
    if (_sessionId.isEmpty) return;
    _hearts += 1; // خوش‌بینانه؛ حلقهٔ state عددِ درست را جایگزین می‌کند
    notifyListeners();
    try {
      _hearts = await _api.liveHeart(_sessionId);
      notifyListeners();
    } catch (_) {}
  }

  // ─────────────── حلقه‌ها ───────────────

  void _startLoops() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) => _pollTick());
    _stateTimer ??= Timer.periodic(_stateInterval, (_) => _stateTick());
    _pollTick();
    _stateTick();
  }

  void _stopLoops() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _stateTimer?.cancel();
    _stateTimer = null;
  }

  Future<void> _pollTick() async {
    if (_pollBusy || _role == LiveRole.idle) return;
    _pollBusy = true;
    try {
      for (final s in await _api.livePoll()) {
        await _handleSignal(s);
      }
    } catch (_) {
      // قطعیِ گذرا؛ تیکِ بعدی دوباره تلاش می‌کند.
    } finally {
      _pollBusy = false;
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> s) async {
    final type = (s['type'] ?? '') as String;
    final from = (s['from'] ?? '') as String;
    if (_role == LiveRole.host) {
      switch (type) {
        case 'viewer-join':
          if (from.isNotEmpty) await _offerToViewer(from);
        case 'answer':
          final pc = _peers[from];
          final sdp = s['sdp'] as String?;
          if (pc != null && sdp != null) {
            try {
              final m = jsonDecode(sdp) as Map<String, dynamic>;
              await pc.setRemoteDescription(RTCSessionDescription(
                m['sdp'] as String?,
                m['type'] as String?,
              ));
            } catch (_) {}
          }
        case 'viewer-leave':
        case 'bye':
          await _peers.remove(from)?.close();
      }
    } else if (_role == LiveRole.viewer && type == 'offer') {
      await _answerHost(s);
    }
  }

  /// وضعیت + چت. برای بیننده این فراخوانی heartbeatِ حضور هم هست، پس تا وقتی
  /// در پخش هستیم نباید متوقف شود وگرنه از شمارشِ بیننده حذف می‌شویم.
  Future<void> _stateTick() async {
    if (_role == LiveRole.idle || _sessionId.isEmpty) return;
    try {
      final st = await _api.liveStateOf(_sessionId);
      _viewerCount = st.viewerCount;
      _hearts = st.hearts;
      if (!st.isLive && _role == LiveRole.viewer) _ended = true;
      _chat = await _api.liveMessages(_sessionId);
      notifyListeners();
    } catch (_) {}
  }

  // ─────────────── کمکی ───────────────

  Future<RTCPeerConnection> _newPeer() => createPeerConnection({
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
      });

  /// انتظار تا کاملِ‌شدنِ جمع‌آوریِ ICE با سقفِ ۳ثانیه (هم‌رفتار با وب).
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

  String _desc(RTCSessionDescription d) =>
      jsonEncode({'type': d.type, 'sdp': d.sdp});

  Future<void> _disposeLocal() async {
    final stream = _localStream;
    _localStream = null;
    if (_renderersReady) localRenderer.srcObject = null;
    if (stream == null) return;
    for (final t in stream.getTracks()) {
      await t.stop();
    }
    await stream.dispose();
  }

  void _reset() {
    _role = LiveRole.idle;
    _sessionId = '';
    _hostEarthId = '';
    _host = null;
    _viewerCount = 0;
    _hearts = 0;
    _chat = const [];
    _remoteReady = false;
  }

  @override
  void dispose() {
    _stopLoops();
    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    _viewerPc?.close();
    _disposeLocal();
    if (_renderersReady) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}
