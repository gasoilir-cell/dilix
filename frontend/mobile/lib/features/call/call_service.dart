import 'dart:async';
import 'dart:convert';

import 'package:dilix_screen_share/dilix_screen_share.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';
import '../../core/l10n.dart';
/// فازِ تماس.
enum CallPhase { idle, outgoing, incoming, connecting, active }

/// نوعِ رسانه.
enum CallMedia { audio, video }

/// یک شرکت‌کنندهٔ **اضافه** در تماسِ گروهی (نفرِ سوم به بعد).
///
/// چرا جدا از اتصالِ اصلی: مسیرِ ۱:۱ سرویسِ زنده است و بازنویسی‌اش برای گروه
/// یعنی ریسک روی چیزی که کار می‌کند. گروه لایه‌ای روی همان ساخته شده — نفرِ اول
/// همان `_pc`ِ قدیمی می‌مانَد و هر نفرِ بعدی یک [CallParticipant] با
/// PeerConnection و رندررِ خودش است (توپولوژیِ mesh: n عضو ⇒ n−۱ اتصال روی هر
/// گوشی؛ به همین دلیل سرور سقفِ ۶ نفر دارد).
class CallParticipant {
  CallParticipant(this.earthId, this.name);

  final String earthId;
  String name;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool rendererReady = false;
  bool remoteSet = false;
  bool sharingScreen = false;
  final List<RTCIceCandidate> pendingIce = [];

  Future<void> close() async {
    try {
      await pc?.close();
    } catch (_) {}
    pc = null;
    if (rendererReady) {
      renderer.srcObject = null;
      try {
        await renderer.dispose();
      } catch (_) {}
      rendererReady = false;
    }
    pendingIce.clear();
  }
}

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

  /// شرکت‌کنندگانِ اضافه (نفرِ سوم به بعد)، به کلیدِ Earth ID.
  final Map<String, CallParticipant> _extra = {};

  /// offerهایی که هنگامِ زنگ‌خوردن رسیده‌اند و پس از پاسخ پردازش می‌شوند.
  final Map<String, String> _pendingPeerOffers = {};

  /// اشتراکِ صفحه روشن است؟ مسیرِ ویدیوی خروجی به‌جای دوربین، تصویرِ صفحه است.
  bool _screenSharing = false;

  /// طرفِ اصلی در حالِ اشتراکِ صفحه است (فقط برچسبِ UI).
  bool _peerSharingScreen = false;

  /// در تماسِ گروهی، طرفِ اصلی رفته ولی بقیه مانده‌اند. اتصالِ اصلی بسته شده و
  /// UI باید فقط شبکهٔ شرکت‌کنندگان را نشان دهد.
  bool _primaryGone = false;

  /// استریمِ تصویرِ صفحه؛ جدا از `_localStream` نگه داشته می‌شود تا با پایانِ
  /// اشتراک بتوان دقیقاً همان را بست و دوربین را برگرداند.
  MediaStream? _screenStream;
  MediaStreamTrack? _cameraTrack;

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

  /// اشتراکِ صفحه از سمتِ من روشن است؟
  bool get screenSharing => _screenSharing;

  /// طرفِ اصلی صفحه‌اش را به اشتراک گذاشته است؟
  bool get peerSharingScreen => _peerSharingScreen;

  /// اتصالِ اصلی هنوز زنده است؟ در گروه ممکن است نفرِ اول رفته باشد.
  bool get primaryActive => !_primaryGone;

  /// شرکت‌کنندگانِ اضافه به ترتیبِ پیوستن — منبعِ چیدمانِ شبکه‌ایِ UI.
  List<CallParticipant> get participants =>
      List<CallParticipant>.unmodifiable(_extra.values);

  /// تماس بیش از دو نفر دارد؟ در این حالت قطع‌کردن یعنی «من رفتم»، نه
  /// «تماس تمام شد» — و همین تفاوت تعیین می‌کند چه سیگنالی برود.
  bool get isGroup => _extra.isNotEmpty;

  /// جا برای دعوتِ نفرِ بعدی هست؟ سقف با `MAX_PARTICIPANTS`ِ سرور یکی است؛
  /// نگه‌داشتنش اینجا فقط برای غیرفعال‌کردنِ دکمه پیش از خطای ۴۰۹ است.
  static const maxParticipants = 6;
  bool get canInvite =>
      _phase == CallPhase.active && _extra.length + 2 < maxParticipants;

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
  /// [to] خالی یعنی «به طرفِ اصلی». در تماسِ گروهی هر سیگنال باید مقصدِ صریح
  /// داشته باشد، وگرنه answer/ice نفرِ سوم به نفرِ اول می‌رود و اتصال نمی‌گیرد.
  Future<void> _signal(String type,
      {String? sdp, String? text, String? lang, String? to}) async {
    final dest = (to ?? _peerId).toUpperCase();
    if (_callId.isEmpty || dest.isEmpty) return;
    try {
      await _api.callSignal(
        callId: _callId,
        toEarthId: dest,
        type: type,
        sdp: sdp,
        text: text,
        lang: lang,
      );
    } catch (_) {}
  }

  /// پخشِ یک سیگنال به همهٔ اعضا (اصلی + اضافه‌ها).
  Future<void> _broadcast(String type, {String? text}) async {
    await _signal(type, text: text);
    for (final id in _extra.keys.toList()) {
      await _signal(type, text: text, to: id);
    }
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
      // تماسِ گروهی: offerهایی که حینِ زنگ رسیده بودند حالا میکروفنِ باز دارند.
      final queued = Map<String, String>.from(_pendingPeerOffers);
      _pendingPeerOffers.clear();
      for (final entry in queued.entries) {
        await _onPeerOffer(entry.key, entry.value);
      }
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
        // در گروه «قطع» یعنی «من رفتم»، نه «تماس تمام شد»؛ پس اعضای اضافه
        // `peer-left` می‌گیرند و تماس بینِ باقی‌مانده‌ها برقرار می‌مانَد.
        //
        // ولی به عضوِ اصلی همچنان `end` می‌رود، چون ممکن است کلاینتِ وب باشد:
        // `CallManager.tsx` هیچ caseای برای `peer-left` ندارد و آن را بی‌صدا
        // دور می‌ریزد، یعنی تا ابد در حالتِ «برقرار» با اتصالِ مرده می‌مانَد.
        // موبایلِ گروه‌آگاه هم `end` را در گروه فقط «بستنِ همان اتصال»
        // می‌فهمد (`_closePrimary`)، پس این انتخاب برای هر دو درست است.
        if (isGroup) {
          await _signal('end');
          for (final id in _extra.keys.toList()) {
            await _signal('peer-left', to: id);
          }
        } else {
          await _signal('end');
        }
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
        // در گروه، پاسخِ یک عضوِ اضافه هم با همین نوع می‌آید؛ فرستنده تعیین
        // می‌کند کدام اتصال است.
        final ansFrom = ((s['from'] ?? '') as String).toUpperCase();
        final ansPeer = _extra[ansFrom];
        if (ansPeer != null && callId == _callId) {
          try {
            final desc =
                jsonDecode((s['sdp'] ?? '{}') as String) as Map<String, dynamic>;
            await ansPeer.pc?.setRemoteDescription(RTCSessionDescription(
                desc['sdp'] as String?, desc['type'] as String?));
            ansPeer.remoteSet = true;
            await _flushParticipantIce(ansPeer);
            notifyListeners();
          } catch (_) {
            await _dropParticipant(ansFrom);
          }
          return;
        }
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
          // در گروه، رفتنِ نفرِ اول نباید تماسِ بقیه را قطع کند: فقط همان
          // اتصال بسته می‌شود و UI به شبکهٔ شرکت‌کنندگان می‌افتد.
          if (isGroup) {
            await _closePrimary();
            return;
          }
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
          final res = await _api.translateLive(text, L10n.language);
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
          // مسیرِ کاندیدا به اتصالِ همان فرستنده؛ در گروه ریختنِ همه در `_pc`
          // یعنی هیچ‌کدام از اتصال‌های اضافه هرگز connected نمی‌شوند.
          final iceFrom = ((s['from'] ?? '') as String).toUpperCase();
          final icePeer = _extra[iceFrom];
          if (icePeer != null) {
            if (icePeer.pc != null && icePeer.remoteSet) {
              await icePeer.pc!.addCandidate(cand);
            } else {
              icePeer.pendingIce.add(cand);
            }
            return;
          }
          if (_pc != null && _remoteSet) {
            await _pc!.addCandidate(cand);
          } else {
            _pendingRemoteIce.add(cand);
          }
        } catch (_) {}
        break;

      // ── تماسِ گروهی ──

      // سرور: «فلانی وارد شد» → من offer می‌سازم و برایش می‌فرستم.
      case 'peer-join':
        if (!_inCall(callId)) return;
        await _onPeerJoin(
          ((s['peer'] ?? '') as String).toUpperCase(),
          (s['peer_name'] as String?) ?? '',
        );
        break;

      // offerِ یک عضوِ دیگرِ همین تماس — نباید زنگ بخورد.
      case 'offer':
        if (callId != _callId || _callId.isEmpty || s['sdp'] == null) return;
        // اعضای قدیمی به‌محضِ دعوت offer می‌فرستند، اما گوشیِ من هنوز زنگ
        // می‌خورد و میکروفن باز نشده است. دورانداختنِ offer یعنی آن عضو تا
        // آخرِ تماس بی‌صدا می‌مانَد؛ پس تا لحظهٔ پاسخ نگه داشته می‌شود.
        if (_phase == CallPhase.incoming) {
          _pendingPeerOffers[((s['from'] ?? '') as String).toUpperCase()] =
              s['sdp'] as String;
          return;
        }
        if (!_inCall(callId)) return;
        await _onPeerOffer(
          ((s['from'] ?? '') as String).toUpperCase(),
          s['sdp'] as String,
        );
        break;

      case 'peer-left':
        if (callId != _callId) return;
        final leftId = ((s['from'] ?? '') as String).toUpperCase();
        if (leftId == _peerId && !_primaryGone) {
          await _closePrimary();
        } else {
          await _dropParticipant(leftId);
        }
        break;

      // اعلامِ روشن/خاموش‌شدنِ اشتراکِ صفحهٔ طرفِ مقابل (فقط برچسبِ UI).
      case 'screen':
        if (!_inCall(callId)) return;
        final scFrom = ((s['from'] ?? '') as String).toUpperCase();
        final on = (s['text'] as String?) == 'on';
        final scPeer = _extra[scFrom];
        if (scPeer != null) {
          scPeer.sharingScreen = on;
        } else if (scFrom == _peerId) {
          _peerSharingScreen = on;
        }
        notifyListeners();
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

  // ─────────── تماسِ گروهی (mesh) ───────────

  /// ساختِ اتصال به یک عضوِ اضافه و سوارکردنِ مسیرهای محلیِ **موجود** روی آن.
  ///
  /// از `_attachLocal` استفاده نمی‌شود: میکروفن/دوربین همین حالا در تماسِ جاری
  /// باز است و گرفتنِ دوبارهٔ آن روی اندروید دستگاه را قفل یا صدا را قطع می‌کند.
  Future<CallParticipant?> _openParticipant(String earthId, String name) async {
    final id = earthId.toUpperCase();
    if (id.isEmpty || id == _peerId || _extra.containsKey(id)) return null;
    final p = CallParticipant(id, name);
    _extra[id] = p;
    try {
      await p.renderer.initialize();
      p.rendererReady = true;
    } catch (_) {
      // محیطِ تست/بدونِ پلاگین — اتصال بی‌تصویر ادامه می‌یابد.
    }
    final pc = await createPeerConnection({
      'iceServers': await _ice(),
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _signal('ice',
          to: id,
          sdp: jsonEncode({
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          }));
    };
    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      if (p.rendererReady) p.renderer.srcObject = event.streams[0];
      notifyListeners();
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        // فقط همین شاخه می‌افتد؛ تماس برای بقیه برقرار می‌مانَد.
        _dropParticipant(id);
      }
    };
    p.pc = pc;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await pc.addTrack(track, _localStream!);
      } catch (_) {}
    }
    return p;
  }

  /// دعوتِ نفرِ تازه به تماسِ در جریان.
  ///
  /// همان `invite`ِ سرور با `call_id`ِ فعلی صدا زده می‌شود؛ سرور به بقیهٔ اعضا
  /// `peer-join` می‌دهد تا آن‌ها هم به تازه‌وارد وصل شوند.
  Future<bool> addParticipant(String earthId, String name) async {
    if (!canInvite) return false;
    final id = earthId.trim().toUpperCase();
    if (id.isEmpty || id == _peerId || _extra.containsKey(id)) return false;
    final p = await _openParticipant(id, name);
    if (p?.pc == null) return false;
    try {
      final offer = await p!.pc!.createOffer();
      await p.pc!.setLocalDescription(offer);
      await _waitIce(p.pc!);
      final local = await p.pc!.getLocalDescription() ?? offer;
      final (_, status) = await _api.callInvite(
        toEarthId: id,
        media: _media == CallMedia.video ? 'video' : 'audio',
        sdp: _localDesc(local),
        callId: _callId,
      );
      if (status == 'offline') {
        _error = tr('مخاطب در دسترس نیست.');
        await _dropParticipant(id);
        return false;
      }
      notifyListeners();
      return true;
    } catch (_) {
      _error = tr('افزودنِ مخاطب ناموفق بود.');
      await _dropParticipant(id);
      return false;
    }
  }

  /// بستنِ اتصالِ یک عضو بدونِ دست‌زدن به بقیهٔ تماس.
  Future<void> _dropParticipant(String earthId) async {
    final p = _extra.remove(earthId.toUpperCase());
    if (p == null) return;
    await p.close();
    // آخرین نفر رفت و نفرِ اول هم قبلاً رفته بود → دیگر کسی نمانده.
    if (_extra.isEmpty && _primaryGone) {
      _teardown();
      return;
    }
    notifyListeners();
  }

  /// بستنِ فقط اتصالِ نفرِ اول در تماسِ گروهی.
  ///
  /// `_teardown` کلِ تماس را جمع می‌کند و اینجا اشتباه است: بقیهٔ اعضا هنوز
  /// روی خط‌اند و صدایشان نباید قطع شود.
  Future<void> _closePrimary() async {
    if (_primaryGone) return;
    _primaryGone = true;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _remoteSet = false;
    _pendingRemoteIce.clear();
    if (_renderersReady) remoteRenderer.srcObject = null;
    if (_extra.isEmpty) {
      _teardown();
      return;
    }
    notifyListeners();
  }

  /// سرور خبر داده کسی وارد شد: من (عضوِ قدیمی) باید offer بسازم.
  Future<void> _onPeerJoin(String earthId, String name) async {
    final p = await _openParticipant(earthId, name);
    if (p?.pc == null) return;
    try {
      final offer = await p!.pc!.createOffer();
      await p.pc!.setLocalDescription(offer);
      await _waitIce(p.pc!);
      final local = await p.pc!.getLocalDescription() ?? offer;
      await _signal('offer', to: p.earthId, sdp: _localDesc(local));
    } catch (_) {
      await _dropParticipant(earthId);
    }
  }

  /// offerِ یک عضوِ دیگرِ همین تماس رسید (زنگ نمی‌خورد — از قبل در تماسم).
  Future<void> _onPeerOffer(String earthId, String rawSdp) async {
    final p = await _openParticipant(earthId, '') ?? _extra[earthId.toUpperCase()];
    if (p?.pc == null) return;
    try {
      final desc = jsonDecode(rawSdp) as Map<String, dynamic>;
      await p!.pc!.setRemoteDescription(
        RTCSessionDescription(desc['sdp'] as String?, desc['type'] as String?),
      );
      p.remoteSet = true;
      await _flushParticipantIce(p);
      final answer = await p.pc!.createAnswer();
      await p.pc!.setLocalDescription(answer);
      await _waitIce(p.pc!);
      final local = await p.pc!.getLocalDescription() ?? answer;
      await _signal('answer', to: p.earthId, sdp: _localDesc(local));
      notifyListeners();
    } catch (_) {
      await _dropParticipant(earthId);
    }
  }

  Future<void> _flushParticipantIce(CallParticipant p) async {
    final queued = List<RTCIceCandidate>.from(p.pendingIce);
    p.pendingIce.clear();
    for (final c in queued) {
      try {
        await p.pc!.addCandidate(c);
      } catch (_) {}
    }
  }

  // ─────────── اشتراکِ صفحه ───────────

  /// روشن/خاموش‌کردنِ اشتراکِ صفحه (کاربردِ «کلاسِ درس»).
  ///
  /// تصویرِ صفحه **جای مسیرِ ویدیوی موجود** را با `replaceTrack` می‌گیرد، نه
  /// اینکه مسیرِ دومی اضافه کند: جایگزینی نیازی به مذاکرهٔ دوباره ندارد، پس
  /// تصویر روی همهٔ اعضا بی‌وقفه عوض می‌شود. اگر تماس صوتی باشد اول به تصویری
  /// ارتقا داده می‌شود، وگرنه اصلاً مسیرِ ویدیویی برای جایگزینی وجود ندارد.
  Future<void> toggleScreenShare() async {
    if (_phase != CallPhase.active || _switching) return;
    if (_screenSharing) {
      await _stopScreenShare();
      return;
    }
    if (!await DilixScreenShare.isSupported) {
      _error = tr('اشتراکِ صفحه روی این دستگاه پشتیبانی نمی‌شود.');
      notifyListeners();
      return;
    }
    _switching = true;
    notifyListeners();
    try {
      if (_media != CallMedia.video) {
        await switchMedia(CallMedia.video);
      }
      // سرویسِ پیش‌زمینه باید **پیش از** گرفتنِ تصویرِ صفحه بالا باشد؛ اندروید
      // ۱۴ در غیرِ این صورت SecurityException می‌دهد.
      final ok = await DilixScreenShare.start(
        title: tr('دیلیکس'),
        body: tr('اشتراکِ صفحه در جریان است'),
      );
      if (!ok) {
        _error = tr('اجازهٔ اشتراکِ صفحه داده نشد.');
        return;
      }
      final screen = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': false,
      });
      final track = screen.getVideoTracks().isNotEmpty
          ? screen.getVideoTracks().first
          : null;
      if (track == null) {
        await DilixScreenShare.stop();
        _error = tr('تصویرِ صفحه در دسترس نبود.');
        return;
      }
      _screenStream = screen;
      _cameraTrack = _localStream?.getVideoTracks().isNotEmpty == true
          ? _localStream!.getVideoTracks().first
          : null;
      await _replaceVideoTrackEverywhere(track);
      _screenSharing = true;
      // کاربر می‌تواند از خودِ اعلانِ سیستم اشتراک را قطع کند؛ بدونِ این،
      // دکمهٔ اپ روشن می‌مانَد و طرفِ مقابل تصویرِ یخ‌زده می‌بیند.
      track.onEnded = () {
        if (_screenSharing) _stopScreenShare();
      };
      await _broadcast('screen', text: 'on');
    } catch (_) {
      await DilixScreenShare.stop();
      _error = tr('اشتراکِ صفحه ناموفق بود.');
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  Future<void> _stopScreenShare() async {
    if (!_screenSharing) return;
    _screenSharing = false;
    try {
      // دوربین اگر هنوز زنده است برمی‌گردد؛ اگر تماس در این فاصله صوتی شده
      // باشد مسیر خالی می‌مانَد و طرفِ مقابل تصویری نمی‌بیند — که درست است.
      if (_cameraTrack != null) {
        await _replaceVideoTrackEverywhere(_cameraTrack!);
      }
      for (final t in _screenStream?.getTracks() ?? <MediaStreamTrack>[]) {
        try {
          await t.stop();
        } catch (_) {}
      }
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;
    _cameraTrack = null;
    await DilixScreenShare.stop();
    await _broadcast('screen', text: 'off');
    if (_renderersReady) localRenderer.srcObject = _localStream;
    notifyListeners();
  }

  /// جایگزینیِ مسیرِ ویدیوی خروجی روی اتصالِ اصلی و همهٔ اعضای گروه.
  Future<void> _replaceVideoTrackEverywhere(MediaStreamTrack track) async {
    Future<void> apply(RTCPeerConnection? pc) async {
      if (pc == null) return;
      for (final s in await pc.getSenders()) {
        if (s.track?.kind != 'video') continue;
        try {
          await s.replaceTrack(track);
        } catch (_) {}
      }
    }

    await apply(_pc);
    for (final p in _extra.values) {
      await apply(p.pc);
    }
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
    // اتصال‌های گروهی هم باید بسته شوند وگرنه میکروفن/دوربین آزاد نمی‌شود و
    // رندررهایشان نشت می‌کنند.
    for (final p in _extra.values.toList()) {
      p.close();
    }
    _extra.clear();
    _primaryGone = false;
    _peerSharingScreen = false;
    // سرویسِ پیش‌زمینه باید برود، وگرنه اعلانِ «اشتراکِ صفحه» پس از پایانِ تماس
    // روی نوار می‌مانَد.
    if (_screenSharing || _screenStream != null) {
      _screenSharing = false;
      for (final t in _screenStream?.getTracks() ?? <MediaStreamTrack>[]) {
        try {
          t.stop();
        } catch (_) {}
      }
      _screenStream?.dispose();
      _screenStream = null;
      _cameraTrack = null;
      DilixScreenShare.stop();
    }
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
    _pendingPeerOffers.clear();
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
