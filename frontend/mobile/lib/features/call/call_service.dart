import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';

/// فازِ تماس.
enum CallPhase { idle, outgoing, incoming, connecting, active }

/// نوعِ رسانه.
enum CallMedia { audio, video }

/// سرویسِ WebRTC تماسِ صوتی/تصویری. signaling روی همان `WS /v1/ws?token=`
/// انجام می‌شود و سرور فقط پیام‌ها را بینِ دو طرف relay می‌کند (سرور رسانه را
/// نمی‌بیند). پروتکل هم‌راستا با `CallManager.tsx` وب است:
///   call.offer/answer → payload.sdp {type,sdp}
///   ice.candidate     → payload.candidate {candidate,sdpMid,sdpMLineIndex}
///   call.end          → payload.reason
/// و در همهٔ پیام‌ها `to` (گیرنده) و `call_id` و `media` هست؛ سرور `from` را
/// به payload اضافه می‌کند.
class CallService extends ChangeNotifier {
  CallService(this._api);

  final ApiClient _api;

  static const _iceServers = <String, dynamic>{
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  RTCPeerConnection? _pc;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingCandidates = [];

  CallPhase _phase = CallPhase.idle;
  CallMedia _media = CallMedia.audio;
  String _peerId = '';
  String _peerName = '';
  String _callId = '';
  bool _outgoing = false;
  bool _muted = false;
  bool _camOff = false;
  bool _initialized = false;
  bool _renderersReady = false;
  String? _error;

  CallPhase get phase => _phase;
  CallMedia get media => _media;
  String get peerId => _peerId;
  String get peerName => _peerName;
  bool get muted => _muted;
  bool get camOff => _camOff;
  String? get error => _error;
  bool get isBusy => _phase != CallPhase.idle;

  /// آماده‌سازیِ رندررها و اتصالِ WebSocket. idempotent است و پس از احرازِ هویت
  /// یک‌بار به‌صورتِ سراسری صدا زده می‌شود تا WS همیشه به تماسِ ورودی گوش دهد.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // در محیطِ تست پلاگینِ WebRTC وجود ندارد؛ خطای مقداردهیِ رندرر را می‌بلعیم.
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersReady = true;
    } catch (_) {}
    await _ensureSocket();
  }

  /// فقط برای تست: تنظیمِ مستقیمِ فاز/طرف بدونِ درگیرکردنِ WebRTC واقعی.
  @visibleForTesting
  void debugSetPhase(
    CallPhase phase, {
    String peerName = 'آزمون',
    CallMedia media = CallMedia.audio,
  }) {
    _phase = phase;
    _peerName = peerName;
    _media = media;
    notifyListeners();
  }

  Future<void> _ensureSocket() async {
    if (_ws != null) return;
    final token = _api.accessToken;
    if (token == null) return;
    final base = _api.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    try {
      _ws = await WebSocket.connect('$base/v1/ws?token=$token');
      _wsSub = _ws!.listen(
        _onWsData,
        onDone: () {
          _ws = null;
        },
        onError: (_) {
          _ws = null;
        },
      );
    } catch (e) {
      _error = 'اتصالِ بلادرنگ برقرار نشد.';
      notifyListeners();
    }
  }

  void _send(String type, Map<String, dynamic> payload) {
    final ws = _ws;
    if (ws == null || _peerId.isEmpty) return;
    ws.add(jsonEncode({
      'type': type,
      'payload': {
        'to': _peerId,
        'call_id': _callId,
        'media': _media == CallMedia.video ? 'video' : 'audio',
        ...payload,
      },
    }));
  }

  Future<void> _onWsData(dynamic raw) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'] as String?;
    final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    switch (type) {
      case 'call.offer':
        await _onOffer(payload);
        break;
      case 'call.answer':
        await _onAnswer(payload);
        break;
      case 'ice.candidate':
        await _onRemoteCandidate(payload);
        break;
      case 'call.end':
        _teardown();
        break;
    }
  }

  // ─────────── ساختِ اتصال ───────────
  Future<RTCPeerConnection> _newPeerConnection() async {
    final pc = await createPeerConnection(_iceServers);
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _send('ice.candidate', {
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        notifyListeners();
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (_phase != CallPhase.idle) _teardown();
      }
    };
    return pc;
  }

  Future<void> _attachLocal() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _media == CallMedia.video,
    });
    _localStream = stream;
    localRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      await _pc!.addTrack(track, stream);
    }
    notifyListeners();
  }

  Future<void> _flushCandidates() async {
    final pending = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in pending) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
  }

  // ─────────── تماسِ خروجی ───────────
  Future<void> startCall({
    required String peerId,
    required String peerName,
    required CallMedia media,
  }) async {
    if (_phase != CallPhase.idle) return;
    await _ensureSocket();
    _error = null;
    _outgoing = true;
    _peerId = peerId;
    _peerName = peerName;
    _media = media;
    _callId = _newCallId();
    _phase = CallPhase.outgoing;
    notifyListeners();
    try {
      _pc = await _newPeerConnection();
      await _attachLocal();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _send('call.offer', {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (_) {
      _error = 'شروعِ تماس ناموفق بود.';
      _teardown();
    }
  }

  // ─────────── تماسِ ورودی ───────────
  Future<void> _onOffer(Map<String, dynamic> payload) async {
    if (_phase != CallPhase.idle) {
      // مشغول: به تماس‌گیرنده پایان می‌فرستیم.
      _peerId = (payload['from'] ?? '') as String;
      _callId = (payload['call_id'] ?? '') as String;
      _send('call.end', {'reason': 'busy'});
      _peerId = '';
      return;
    }
    _outgoing = false;
    _peerId = (payload['from'] ?? '') as String;
    _callId = (payload['call_id'] ?? '') as String;
    _media = payload['media'] == 'video' ? CallMedia.video : CallMedia.audio;
    final sdp = (payload['sdp'] as Map).cast<String, dynamic>();
    _pendingOffer = RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String);
    _phase = CallPhase.incoming;
    notifyListeners();
  }

  RTCSessionDescription? _pendingOffer;

  Future<void> accept() async {
    if (_pendingOffer == null) return;
    _phase = CallPhase.connecting;
    notifyListeners();
    try {
      _pc = await _newPeerConnection();
      await _attachLocal();
      await _pc!.setRemoteDescription(_pendingOffer!);
      await _flushCandidates();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _send('call.answer', {
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
      _pendingOffer = null;
      _phase = CallPhase.active;
      notifyListeners();
    } catch (_) {
      _error = 'پاسخ به تماس ناموفق بود.';
      _send('call.end', {'reason': 'failed'});
      _teardown();
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> payload) async {
    if (!_outgoing || _pc == null) return;
    final sdp = (payload['sdp'] as Map).cast<String, dynamic>();
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String),
    );
    await _flushCandidates();
    _phase = CallPhase.active;
    notifyListeners();
  }

  Future<void> _onRemoteCandidate(Map<String, dynamic> payload) async {
    final c = (payload['candidate'] as Map?)?.cast<String, dynamic>();
    if (c == null) return;
    final cand = RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      (c['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_pc != null && await _hasRemoteDescription()) {
      try {
        await _pc!.addCandidate(cand);
      } catch (_) {}
    } else {
      _pendingCandidates.add(cand);
    }
  }

  Future<bool> _hasRemoteDescription() async {
    if (_pc == null) return false;
    final desc = await _pc!.getRemoteDescription();
    return desc != null;
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

  /// قطعِ تماس (از سمتِ کاربر): پیامِ پایان می‌فرستد و منابع را آزاد می‌کند.
  void hangup() {
    if (_phase != CallPhase.idle) _send('call.end', {'reason': 'hangup'});
    _teardown();
  }

  /// ردِ تماسِ ورودی.
  void reject() {
    if (_phase == CallPhase.incoming) _send('call.end', {'reason': 'declined'});
    _teardown();
  }

  void _teardown() {
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
    _pendingCandidates.clear();
    _pendingOffer = null;
    _peerId = '';
    _peerName = '';
    _callId = '';
    _outgoing = false;
    _muted = false;
    _camOff = false;
    _phase = CallPhase.idle;
    notifyListeners();
  }

  static String _newCallId() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ws?.close();
    _teardown();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
