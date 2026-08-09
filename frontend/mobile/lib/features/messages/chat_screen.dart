import 'dart:async';
import 'dart:io';

import 'package:dilix_media_store/dilix_media_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/location_service.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../call/call_service.dart';
import '../social/profile_screen.dart';
import 'chat_sheets.dart';
import 'media_editor_screen.dart';
import 'media_viewer.dart';
import 'message_bubble.dart';
import 'sticker_picker_sheet.dart';
import 'sticker_studio_screen.dart';

import '../../core/l10n.dart';
/// نمای بومیِ گفتگو با پوششِ کاملِ پیام‌رسانِ dilix-api:
/// متن/پاسخ/ویرایش/حذف، رسانه (عکس، ویدیو، صوت، فایل)، واکنش، بازارسال،
/// سنجاق، جستجو، تایپینگ و حضور، نظرسنجی، هدیهٔ نقدی، موقعیت (ثابت و زنده)،
/// مخاطب، رویداد، ترجمه، گروه و اعضا، بی‌صدا/مسدود/پاک‌سازی/ناپدیدشدن و گزارش.
///
/// realtime با polling ساخته می‌شود (پیام‌ها ۵ث، وضعیت ۴ث) — هم‌راستا با وبِ
/// زنده که WebSocket ندارد.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.room});

  final ChatRoom room;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _messages = <ChatMessage>[];

  /// ترجمهٔ نمایش‌داده‌شده برای هر پیام (id → متنِ ترجمه).
  final _translations = <String, String>{};
  final _selectedIds = <String>{};
  bool _selectMode = false;
  bool _autoTranslate = false;
  String _translateLanguage = 'fa';
  Color? _mineBubbleColor;
  int _wallpaperIndex = 0;

  static const _bubbleColors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFF4F46E5),
    Color(0xFF334155),
  ];
  static const _wallpapers = <List<Color>>[
    [Color(0x00000000), Color(0x00000000)],
    [Color(0x221D4ED8), Color(0x220F766E)],
    [Color(0x223B0764), Color(0x221E1B4B)],
    [Color(0x223F6212), Color(0x2214532D)],
    [Color(0x227C2D12), Color(0x224C0519)],
    [Color(0x221E3A8A), Color(0x22312E81)],
    [Color(0x2244403C), Color(0x221C1917)],
    [Color(0x223F3F46), Color(0x2218181B)],
  ];

  /// ضبطِ پیامِ صوتی.
  final _recorder = AudioRecorder();
  bool _recording = false;
  Duration _recElapsed = Duration.zero;
  Timer? _recTimer;
  String? _recPath;

  /// اشتراکِ موقعیتِ زندهٔ فعالِ من در این اتاق (شناسهٔ پیام) و جریانِ GPSِ آن.
  ///
  /// به‌جای `Timer.periodic` از جریانِ `LocationService.liveStream` استفاده
  /// می‌شود تا روی اندروید یک foreground service بالا بیاید؛ وگرنه به‌محضِ رفتنِ
  /// اپ به پس‌زمینه سیستم موقعیت را throttle می‌کرد و اشتراک عملاً می‌ایستاد.
  static const _location = LocationService();
  String? _liveLocationId;
  StreamSubscription<LocationFix>? _liveSub;

  /// آخرین ارسالِ موفق به سرور؛ جریان ممکن است تندتر از این فیکس بدهد و لازم
  /// نیست هر فیکس یک درخواست شود.
  DateTime _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);
  static const _livePushInterval = Duration(seconds: 30);

  Timer? _poll;
  Timer? _statusPoll;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// آخرین وضعیتِ «فیلد متن دارد؟» برای سوییچِ دکمهٔ ارسال/میکروفن.
  bool _hadText = false;

  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// اتاق را در state نگه می‌داریم چون فیلدهایی مثلِ بی‌صدا/مسدود تغییر می‌کنند.
  late ChatRoom _room;
  RoomStatus? _status;
  List<ChatMessage> _pins = const [];

  /// پیامی که به آن پاسخ می‌دهیم، یا پیامی که در حالِ ویرایشِ آن هستیم.
  ChatMessage? _replyTo;
  ChatMessage? _editing;

  ApiClient get _api => ApiScope.of(context);

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _inputCtrl.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChatPreferences();
      _load(initial: true);
      _markRead();
      _refreshStatus();
      _loadPins();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
      _statusPoll =
          Timer.periodic(const Duration(seconds: 4), (_) => _refreshStatus());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _statusPoll?.cancel();
    _liveSub?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _scrollCtrl.dispose();
    _inputCtrl
      ..removeListener(_onInputChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadChatPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoTranslate = prefs.getBool('chat.auto_translate') ?? false;
      _translateLanguage = prefs.getString('chat.translate_language') ?? 'fa';
      _wallpaperIndex = prefs.getInt('chat.wallpaper.${_room.id}') ?? 0;
      final color = prefs.getInt('chat.bubble.${_room.id}');
      _mineBubbleColor = color == null ? null : Color(color);
    });
  }

  Future<void> _persistChatPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('chat.auto_translate', _autoTranslate);
    await prefs.setString('chat.translate_language', _translateLanguage);
    await prefs.setInt('chat.wallpaper.${_room.id}', _wallpaperIndex);
    if (_mineBubbleColor != null) {
      await prefs.setInt('chat.bubble.${_room.id}', _mineBubbleColor!.toARGB32());
    }
  }

  Future<void> _translateIncoming(List<ChatMessage> list) async {
    if (!_autoTranslate) return;
    final pending = list.where((m) =>
        !m.isMine &&
        !m.deleted &&
        m.content.trim().isNotEmpty &&
        !_translations.containsKey(m.id));
    for (final m in pending.take(12)) {
      try {
        final result = await _api.translateMessage(m.id, _translateLanguage);
        if (mounted && result.detectedLang != _translateLanguage) {
          setState(() => _translations[m.id] = result.translatedText);
        }
      } catch (_) {}
    }
  }

  // ─────────────── داده ───────────────

  Future<void> _load({bool initial = false}) async {
    try {
      final list = await _api.roomMessages(_room.id, limit: 60);
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
        _syncLiveLocation(list);
      });
      if (initial || (hadNew && wasAtBottom)) _scrollToBottom();
      if (hadNew && !initial) _markRead();
      if (hadNew || initial) _translateIncoming(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (initial) _error = '$e';
      });
    }
  }

  /// اشتراکِ موقعیتِ زندهٔ فعالِ خودم را از پیام‌های بارگذاری‌شده بازیابی می‌کند تا
  /// با بازکردنِ دوبارهٔ گفتگو (یا انقضا از سمتِ سرور) وضعیتِ دکمه و جریانِ GPS
  /// درست بماند.
  void _syncLiveLocation(List<ChatMessage> list) {
    final active = list
        .where((m) =>
            m.isMine &&
            !m.deleted &&
            (m.location?.live ?? false) &&
            (m.location?.active ?? false))
        .toList();
    final id = active.isEmpty ? null : active.last.id;
    if (id == _liveLocationId) return;
    _liveLocationId = id;
    if (id == null) {
      _endLiveTracking();
    } else {
      _beginLiveTracking();
    }
  }

  /// جریانِ GPS را آغاز می‌کند (روی اندروید همراهِ یک foreground service، پس در
  /// پس‌زمینه هم فیکس می‌رسد). هر فیکس از throttleِ [_livePushInterval] می‌گذرد
  /// تا شبکه با هر جابه‌جاییِ چندمتری درگیر نشود.
  void _beginLiveTracking() {
    _liveSub?.cancel();
    _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);
    _liveSub = _location
        .liveStream(
          interval: _livePushInterval,
          notificationTitle: tr('اشتراکِ موقعیتِ زنده'),
          notificationText:
              tr('موقعیتِ تو با {0} به اشتراک گذاشته می‌شود.', [_room.title]),
        )
        .listen(_onLiveFix);
  }

  void _endLiveTracking() {
    _liveSub?.cancel();
    _liveSub = null;
  }

  void _onLiveFix(LocationFix fix) {
    if (!fix.isOk || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastLivePush) < _livePushInterval) return;
    _lastLivePush = now;
    _pushLiveLocation(fix);
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await _api.roomStatus(_room.id);
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  Future<void> _loadPins() async {
    try {
      final p = await _api.roomPins(_room.id);
      if (mounted) setState(() => _pins = p);
    } catch (_) {}
  }

  Future<void> _markRead() async {
    try {
      await _api.markRoomRead(_room.id);
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// یک کنشِ شبکه را با نشانگرِ ارسال و پیامِ خطا اجرا می‌کند.
  Future<void> _run(Future<void> Function() action, {String? failure}) async {
    setState(() => _sending = true);
    try {
      await action();
    } catch (e) {
      _toast(tr('{0}: {1}', [failure ?? tr('عملیات ناموفق بود'), e]));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ─────────────── ارسال ───────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    // حالتِ ویرایش: متنِ پیامِ موجود را عوض می‌کنیم.
    final editing = _editing;
    if (editing != null) {
      await _run(() async {
        await _api.editMessage(editing.id, text);
        _inputCtrl.clear();
        if (mounted) setState(() => _editing = null);
        await _load();
      }, failure: tr('ویرایش ناموفق بود'));
      return;
    }

    await _run(() async {
      final msg = await _api.sendMessage(_room.id, text, replyToId: _replyTo?.id);
      _inputCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: tr('ارسال ناموفق بود'));
  }

  /// خالی/پرشدنِ فیلد → سوییچِ دکمهٔ ارسال ↔ میکروفن. روی `addListener` است تا
  /// پاک‌شدنِ برنامه‌ایِ فیلد (پس از ارسال) هم دیده شود، نه فقط تایپِ کاربر.
  void _onInputChanged() {
    final hasText = _inputCtrl.text.trim().isNotEmpty;
    if (hasText != _hadText && mounted) {
      setState(() => _hadText = hasText);
    }
  }

  /// «در حالِ نوشتن» را حداکثر هر ۳ ثانیه یک‌بار به سرور اعلام می‌کند.
  void _onTextChanged(String value) {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inSeconds < 3) return;
    _lastTypingSent = now;
    _api.setTyping(_room.id).catchError((_) {});
  }

  /// تصویر پیش از ارسال از ویرایشگر می‌گذرد (همان رفتارِ وب در
  /// `messages/page.tsx` → `onPickFile`). ویدیو مستقیم می‌رود چون ویرایشگرِ
  /// ویدیو در موبایل بدونِ وابستگیِ بومی ممکن نیست.
  /// `null` یعنی کاربر در ویرایشگر لغو کرد → ارسالی در کار نیست.
  Future<String?> _editBeforeSend(String path) async {
    final edited = await openMediaEditor(context, File(path));
    return edited?.path;
  }

  Future<void> _pickAndSendMedia({required bool video}) async {
    final XFile? file = video
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    String path = file.path;
    if (!video) {
      if (!mounted) return;
      final edited = await _editBeforeSend(path);
      if (edited == null) return;
      path = edited;
    }
    final caption = _inputCtrl.text.trim();
    await _run(() async {
      final msg = await _api.sendMedia(
        _room.id,
        path,
        caption: caption.isEmpty ? null : caption,
        replyToId: _replyTo?.id,
      );
      _inputCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: tr('ارسالِ رسانه ناموفق بود'));
  }

  Future<void> _captureAndSendPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    if (!mounted) return;
    final path = await _editBeforeSend(file.path);
    if (path == null) return;
    await _run(() async {
      final msg = await _api.sendMedia(_room.id, path,
          replyToId: _replyTo?.id);
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: tr('ارسالِ عکس ناموفق بود'));
  }

  /// پیوستِ فایلِ دلخواه (سند/PDF/…). سقفِ سرور ۲۵MB است.
  Future<void> _pickAndSendFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles();
    } catch (e) {
      _toast(tr('انتخابِ فایل ناموفق بود: {0}', [e]));
      return;
    }
    final path = result?.files.single.path;
    if (path == null) return;
    final caption = _inputCtrl.text.trim();
    await _run(() async {
      final msg = await _api.sendMedia(
        _room.id,
        path,
        caption: caption.isEmpty ? null : caption,
        replyToId: _replyTo?.id,
      );
      _inputCtrl.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: tr('ارسالِ فایل ناموفق بود'));
  }

  // ─────────────── پیامِ صوتی ───────────────

  /// شروعِ ضبط. مجوزِ میکروفن را خودِ پلاگین می‌گیرد؛ در نبودِ مجوز پیام می‌دهیم.
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast(tr('برای ضبطِ صدا به اجازهٔ میکروفن نیاز است.'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recPath = path;
        _recElapsed = Duration.zero;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recElapsed += const Duration(seconds: 1));
        }
      });
    } catch (e) {
      _toast(tr('شروعِ ضبط ناموفق بود: {0}', [e]));
    }
  }

  Future<String?> _finishRecording() async {
    _recTimer?.cancel();
    _recTimer = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    if (mounted) setState(() => _recording = false);
    return path ?? _recPath;
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    _recTimer = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndSendRecording() async {
    // صداهای زیرِ ۱ ثانیه معمولاً لمسِ اشتباهی‌اند.
    final tooShort = _recElapsed.inSeconds < 1;
    final path = await _finishRecording();
    if (tooShort) {
      _toast(tr('پیامِ صوتی خیلی کوتاه بود.'));
      return;
    }
    if (path == null) {
      _toast(tr('فایلِ صوتی ساخته نشد.'));
      return;
    }
    await _run(() async {
      final msg = await _api.sendMedia(_room.id, path,
          replyToId: _replyTo?.id);
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: tr('ارسالِ پیامِ صوتی ناموفق بود'));
  }

  /// ذخیرهٔ رسانهٔ یک پیام روی دستگاه — معادلِ `saveMedia` در وب.
  ///
  /// فایل در فضای موقت دانلود و بعد با MediaStore در گالریِ عمومی نوشته می‌شود
  /// (`Pictures/Dilix`، `Movies/Dilix`، …). پیش‌تر اینجا برگهٔ اشتراک‌گذاری باز
  /// می‌شد که کارِ **اشتراک** است نه ذخیره؛ کاربر گزینهٔ «ذخیرهٔ رسانه» را می‌زد
  /// و لیستِ اپ‌ها می‌آمد. اگر پلاگینِ بومی در دسترس نباشد (تست/دسکتاپ) همان
  /// رفتارِ اشتراک به‌عنوانِ آخرین چاره می‌ماند.
  Future<void> _saveMedia(ChatMessage m) async {
    final url = AppConfig.absoluteMedia(m.mediaUrl);
    if (url == null) {
      _toast(tr('این پیام رسانه‌ای ندارد.'));
      return;
    }
    await _run(() async {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode >= 400) {
        throw StateError(tr('کدِ {0}', [res.statusCode]));
      }
      final dir = await getTemporaryDirectory();
      // نامِ سرور را نگه می‌داریم تا پسوند (و در نتیجه نوعِ MIME و آلبومِ مقصد)
      // درست دربیاید.
      final name = (m.mediaName ?? '').trim().isNotEmpty
          ? m.mediaName!.trim()
          : 'dilix-${m.mediaType ?? 'media'}-${DateTime.now().millisecondsSinceEpoch}';
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(res.bodyBytes, flush: true);

      if (await DilixMediaStore.isSupported) {
        final where = await DilixMediaStore.save(path: f.path, name: name);
        // فایلِ موقت دیگر لازم نیست؛ نسخهٔ اصلی در گالری است.
        try {
          await f.delete();
        } on FileSystemException {
          // پاک‌نشدنِ کشِ موقت نباید ذخیرهٔ موفق را «ناموفق» نشان دهد.
        }
        if (!mounted) return;
        _toast(where.isEmpty
            ? tr('در گالری ذخیره شد.')
            : tr('در {0} ذخیره شد.', [where]));
        return;
      }
      await Share.shareXFiles([XFile(f.path)]);
    }, failure: tr('ذخیرهٔ رسانه ناموفق بود'));
  }

  // ─────────────── کنش‌های پیام ───────────────

  Future<void> _messageActions(ChatMessage m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reactionPickerRow(ctx, m),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(tr('پاسخ')),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (m.isPlainText && m.content.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(tr('کپیِ متن')),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            ListTile(
              leading: const Icon(Icons.shortcut),
              title: Text(tr('بازارسال')),
              onTap: () => Navigator.pop(ctx, 'forward'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(tr('اشتراک‌گذاری')),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(tr('انتخاب')),
              onTap: () => Navigator.pop(ctx, 'select'),
            ),
            ListTile(
              leading: Icon(m.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(m.isPinned ? tr('برداشتنِ سنجاق') : tr('سنجاق‌کردن')),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            if (m.content.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(tr('ترجمه')),
                onTap: () => Navigator.pop(ctx, 'translate'),
              ),
            if ((m.mediaUrl ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(tr('ذخیرهٔ رسانه')),
                onTap: () => Navigator.pop(ctx, 'save_media'),
              ),
            if ((m.stickerId ?? '').isNotEmpty) ...[
              ListTile(
                leading: Icon(Icons.star_outline,
                    color: DilixSemanticColors.from(context).warning),
                title: Text(tr('ذخیره در ستاره‌دارها')),
                onTap: () => Navigator.pop(ctx, 'star_sticker'),
              ),
              ListTile(
                leading: const Icon(Icons.travel_explore),
                title: Text(tr('کاوشِ بستهٔ این استیکر')),
                onTap: () => Navigator.pop(ctx, 'explore_sticker'),
              ),
            ],
            if (m.event != null)
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text(tr('افزودن به تقویم')),
                onTap: () => Navigator.pop(ctx, 'calendar'),
              ),
            if (m.isMine && m.isPlainText && !m.deleted)
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(tr('ویرایش')),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (m.isMine && !m.deleted)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text(tr('حذف'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            if (!m.isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(tr('گزارشِ تخلف')),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'reply':
        setState(() {
          _replyTo = m;
          _editing = null;
        });
      case 'copy':
        await copyToClipboard(context, m.content);
      case 'forward':
        await _forward(m);
      case 'share':
        await _shareMessages([m]);
      case 'select':
        setState(() {
          _selectMode = true;
          _selectedIds.add(m.id);
        });
      case 'pin':
        await _run(() async {
          await _api.pinMessage(m.id);
          await Future.wait([_load(), _loadPins()]);
        }, failure: tr('سنجاق ناموفق بود'));
      case 'translate':
        await _translate(m);
      case 'save_media':
        await _saveMedia(m);
      case 'star_sticker':
        await _run(() async {
          await _api.setStickerStarred(m.stickerId!, true);
          _toast(tr('به ستاره‌دارها اضافه شد.'));
        }, failure: tr('ستاره‌دارکردن ناموفق بود'));
      case 'explore_sticker':
        await _exploreSticker(m.stickerId!);
      case 'calendar':
        await _shareEventCalendar(m.event!);
      case 'edit':
        setState(() {
          _editing = m;
          _replyTo = null;
          _inputCtrl.text = m.content;
        });
      case 'delete':
        await _confirmDelete(m);
      case 'report':
        await _report(messageId: m.id);
    }
  }

  Widget _reactionPickerRow(BuildContext ctx, ChatMessage m) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ApiClient.allowedReactions.map((emoji) {
            final selected = m.myReaction == emoji;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.pop(ctx);
                _toggleReaction(m, emoji);
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.25)
                      : null,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            );
          }).toList(),
        ),
      );

  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    await _run(() async {
      // بک‌اند toggle است: اگر همین ایموجی را دارم، حذفش می‌کند.
      await _api.reactToMessage(m.id, emoji);
      await _load();
    }, failure: tr('ثبتِ واکنش ناموفق بود'));
  }

  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذفِ پیام')),
        content: Text(tr('این پیام برای همه حذف می‌شود. مطمئنی؟')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('لغو'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _api.deleteMessage(m.id);
      await _load();
    }, failure: tr('حذف ناموفق بود'));
  }

  Future<void> _exploreSticker(String stickerId) async {
    await _run(() async {
      final item = await _api.sticker(stickerId);
      final pack = await _api.stickerPack(item.packId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            builder: (ctx, controller) => Column(children: [
              ListTile(
                title: Text(pack.title),
                subtitle: Text(pack.description ?? tr('{0} استیکر', [pack.stickerCount])),
                trailing: pack.installed
                    ? Icon(Icons.check_circle,
                        color: DilixSemanticColors.from(ctx).success)
                    : FilledButton(
                        onPressed: () async {
                          await _api.installStickerPack(pack.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _toast(tr('بسته نصب شد.'));
                        },
                        child: Text(tr('نصب')),
                      ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: controller,
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
                  itemCount: pack.stickers.length,
                  itemBuilder: (_, i) {
                    final sticker = pack.stickers[i];
                    final url = AppConfig.absoluteMedia(sticker.mediaUrl);
                    return InkWell(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _run(() async {
                          await _api.sendSticker(_room.id, sticker.id,
                              replyToId: _replyTo?.id);
                          await _load();
                        }, failure: tr('ارسالِ استیکر ناموفق بود'));
                      },
                      child: url == null
                          ? const Icon(Icons.emoji_emotions_outlined)
                          : Image.network(url, fit: BoxFit.contain),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );
    }, failure: tr('کاوشِ بسته ناموفق بود'));
  }

  String _icsEscape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');

  String _icsDate(DateTime value) {
    final u = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  Future<void> _shareEventCalendar(EventInfo event) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dilix-event-${event.id}.ics');
    final end = event.startsAt.add(const Duration(hours: 1));
    final ics = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Dilix//Chat Event//FA',
      'BEGIN:VEVENT',
      'UID:${event.id}@dilix.ir',
      'DTSTAMP:${_icsDate(DateTime.now())}',
      'DTSTART:${_icsDate(event.startsAt)}',
      'DTEND:${_icsDate(end)}',
      'SUMMARY:${_icsEscape(event.title)}',
      if ((event.location ?? '').isNotEmpty) 'LOCATION:${_icsEscape(event.location!)}',
      if ((event.description ?? '').isNotEmpty)
        'DESCRIPTION:${_icsEscape(event.description!)}',
      'END:VEVENT',
      'END:VCALENDAR',
      '',
    ].join('\r\n');
    await file.writeAsString(ics, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: event.title);
  }

  String _shareText(ChatMessage m) {
    final sender = m.senderName?.trim();
    final body = m.content.trim().isNotEmpty
        ? m.content.trim()
        : (AppConfig.absoluteMedia(m.mediaUrl) ?? m.mediaType ?? tr('رسانه'));
    return sender == null || sender.isEmpty ? body : '$sender: $body';
  }

  Future<void> _shareMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final files = <XFile>[];
    final text = messages.map(_shareText).join('\n\n');
    if (messages.length == 1 && (messages.first.mediaUrl ?? '').isNotEmpty) {
      try {
        final m = messages.first;
        final url = AppConfig.absoluteMedia(m.mediaUrl);
        if (url != null) {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode < 400) {
            final dir = await getTemporaryDirectory();
            final name = (m.mediaName ?? '').trim().isNotEmpty
                ? m.mediaName!.trim()
                : 'dilix-${m.mediaType ?? 'media'}';
            final file = File('${dir.path}/$name');
            await file.writeAsBytes(res.bodyBytes, flush: true);
            files.add(XFile(file.path));
          }
        }
      } catch (_) {}
    }
    if (files.isEmpty) {
      await Share.share(text);
    } else {
      await Share.shareXFiles(files, text: text);
    }
  }

  void _toggleSelected(ChatMessage m) {
    setState(() {
      if (!_selectedIds.add(m.id)) _selectedIds.remove(m.id);
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  List<ChatMessage> get _selectedMessages =>
      _messages.where((m) => _selectedIds.contains(m.id)).toList();

  void _exitSelection() => setState(() {
        _selectedIds.clear();
        _selectMode = false;
      });

  Future<void> _bulkCopy() async {
    await copyToClipboard(context, _selectedMessages.map(_shareText).join('\n\n'));
    _exitSelection();
  }

  Future<void> _bulkForward() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;
    List<ChatRoom> rooms;
    try {
      rooms = await _api.listRooms();
    } catch (e) {
      _toast(tr('دریافتِ فهرستِ گفتگوها ناموفق بود: {0}', [e]));
      return;
    }
    if (!mounted) return;
    final picked = await showForwardPicker(context,
        rooms: rooms, currentRoomId: _room.id);
    if (picked == null) return;
    await _run(() async {
      for (final m in selected) {
        await _api.forwardMessage(m.id, picked.$1, anonymous: picked.$2);
      }
      _toast(tr('{0} پیام بازارسال شد.', [selected.length]));
      _exitSelection();
    }, failure: tr('بازارسال ناموفق بود'));
  }

  Future<void> _bulkDelete() async {
    final mine = _selectedMessages.where((m) => m.isMine && !m.deleted).toList();
    if (mine.isEmpty) {
      _toast(tr('از میانِ انتخاب‌ها پیامِ قابل‌حذفی از خودت وجود ندارد.'));
      return;
    }
    await _run(() async {
      for (final m in mine) {
        await _api.deleteMessage(m.id);
      }
      _exitSelection();
      await _load();
    }, failure: tr('حذفِ گروهی ناموفق بود'));
  }

  Future<void> _exportChat() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dilix-chat-${_room.id}.txt');
    final text = _messages.map((m) {
      final at = m.sentAt.toLocal().toIso8601String();
      return '[$at] ${m.senderName ?? m.senderEarthId}: ${_shareText(m)}';
    }).join('\n');
    await file.writeAsString(text, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: tr('خروجی گفتگوی {0}', [_room.title]));
  }

  Future<void> _forward(ChatMessage m) async {
    List<ChatRoom> rooms;
    try {
      rooms = await _api.listRooms();
    } catch (e) {
      _toast(tr('دریافتِ فهرستِ گفتگوها ناموفق بود: {0}', [e]));
      return;
    }
    if (!mounted) return;
    final picked =
        await showForwardPicker(context, rooms: rooms, currentRoomId: _room.id);
    if (picked == null || !mounted) return;
    await _run(() async {
      await _api.forwardMessage(m.id, picked.$1, anonymous: picked.$2);
      _toast(tr('بازارسال شد.'));
    }, failure: tr('بازارسال ناموفق بود'));
  }

  Future<void> _translate(ChatMessage m) async {
    final lang = await showLanguagePicker(context);
    if (lang == null || !mounted) return;
    await _run(() async {
      final r = await _api.translateMessage(m.id, lang);
      if (mounted) {
        setState(() => _translations[m.id] = r.translatedText);
      }
    }, failure: tr('ترجمه ناموفق بود'));
  }

  Future<void> _report({String? messageId}) async {
    final earthId = _room.partnerEarthId;
    if (earthId == null || earthId.isEmpty) {
      _toast(tr('گزارش فقط در گفتگویِ مستقیم ممکن است.'));
      return;
    }
    final result = await showReportSheet(context);
    if (result == null || !mounted) return;
    await _run(() async {
      await _api.reportUser(earthId,
          reason: result.$1, note: result.$2, messageId: messageId);
      _toast(tr('گزارش ثبت شد. سپاس از هم‌کاری.'));
    }, failure: tr('ثبتِ گزارش ناموفق بود'));
  }

  // ─────────────── محتوایِ ساختاری ───────────────

  Future<void> _createPoll() async {
    final draft = await showPollComposer(context);
    if (draft == null || !mounted) return;
    await _run(() async {
      await _api.createPoll(_room.id,
          question: draft.question,
          options: draft.options,
          multiple: draft.multiple);
      await _load();
      _scrollToBottom();
    }, failure: tr('ساختِ نظرسنجی ناموفق بود'));
  }

  Future<void> _vote(PollInfo poll, int index) async {
    await _run(() async {
      await _api.votePoll(poll.id, index);
      await _load();
    }, failure: tr('ثبتِ رأی ناموفق بود'));
  }

  Future<void> _createRedPacket() async {
    final draft = await showRedPacketComposer(context);
    if (draft == null || !mounted) return;
    await _run(() async {
      await _api.createRedPacket(_room.id,
          totalAmount: draft.totalAmount,
          count: draft.count,
          mode: draft.mode,
          greeting: draft.greeting);
      await _load();
      _scrollToBottom();
    }, failure: tr('ارسالِ هدیه ناموفق بود'));
  }

  Future<void> _onRedPacket(RedPacketInfo p) async {
    // فرستنده یا کسی که قبلاً برداشته → فقط جزئیات.
    if (!p.isOpenable) {
      await showRedPacketDetails(context, api: _api, packetId: p.id);
      return;
    }
    await _run(() async {
      final res = await _api.openRedPacket(p.id);
      final amount = (res['amount'] ?? 0) as int;
      _toast(tr('🧧 {0} تومان به کیفِ پاداشِ تو اضافه شد.', [(amount / 10).round()]));
      await _load();
    }, failure: tr('بازکردنِ هدیه ناموفق بود'));
  }

  /// ارسالِ مستقیمِ پول یا ثبتِ درخواستِ پول در گفتگویِ دونفره.
  Future<void> _composeMoney({required bool request}) async {
    final draft = await showMoneyComposer(context, request: request);
    if (draft == null || !mounted) return;
    await _run(() async {
      if (request) {
        await _api.requestMoney(_room.id, amount: draft.amount, note: draft.note);
      } else {
        await _api.sendMoney(_room.id, amount: draft.amount, note: draft.note);
      }
      await _load();
      _scrollToBottom();
    },
        failure: request
            ? tr('ثبتِ درخواست ناموفق بود')
            : tr('ارسالِ پول ناموفق بود'));
  }

  /// پرداخت (`pay`) یا رد/لغوِ (`decline`) یک درخواستِ پول.
  Future<void> _settleMoney(ChatMessage m, String action) async {
    final money = m.money;
    if (money == null) return;
    await _run(() async {
      final info = action == 'pay'
          ? await _api.payMoneyRequest(money.id)
          : await _api.declineMoneyRequest(money.id);
      if (info.status == 'paid') {
        _toast(tr('💸 {0} تومان پرداخت شد.', [(info.amount / 10).round()]));
      }
      await _load();
    },
        failure: action == 'pay'
            ? tr('پرداخت ناموفق بود')
            : tr('بستنِ درخواست ناموفق بود'));
  }

  Future<void> _sendLocation() async {
    final loc = await showLocationComposer(context, fix: _currentFix);
    if (loc == null || !mounted) return;
    await _run(() async {
      await _api.sendLocation(_room.id,
          lat: loc.$1, lng: loc.$2, label: loc.$3, replyToId: _replyTo?.id);
      if (mounted) setState(() => _replyTo = null);
      await _load();
      _scrollToBottom();
    }, failure: tr('ارسالِ موقعیت ناموفق بود'));
  }

  /// تأمین‌کنندهٔ GPS برای شیتِ موقعیت؛ خطا را همان‌جا toast می‌کند.
  Future<(double, double)?> _currentFix() async {
    final fix = await _location.current();
    if (!fix.isOk) {
      if (mounted) _toast(fix.error!);
      return null;
    }
    return (fix.lat, fix.lng);
  }

  /// شروعِ اشتراکِ موقعیتِ زنده: مختصاتِ اول از GPS، سپس هر ۳۰ ثانیه به‌روزرسانی
  /// تا پایانِ مدت یا توقفِ دستی. سرور حداکثر ۲۴ ساعت را می‌پذیرد.
  Future<void> _startLiveLocation() async {
    final minutes = await showLiveLocationDuration(context);
    if (minutes == null || !mounted) return;
    final fix = await _location.current();
    if (!mounted) return;
    if (!fix.isOk) {
      _toast(fix.error!);
      return;
    }
    await _run(() async {
      final msg = await _api.startLiveLocation(_room.id,
          lat: fix.lat, lng: fix.lng, durationMinutes: minutes);
      if (!mounted) return;
      setState(() => _liveLocationId = msg.id);
      _beginLiveTracking();
      await _load();
      _scrollToBottom();
      _toast(tr('موقعیتِ زنده تا {0} دقیقه به اشتراک گذاشته شد.', [minutes]));
    }, failure: tr('شروعِ موقعیتِ زنده ناموفق بود'));
  }

  /// یک ضربانِ به‌روزرسانی؛ خطا سکوت می‌کند تا اشتراک با یک قطعیِ گذرا نمیرد،
  /// ولی اگر سرور اشتراک را پایان‌یافته بداند جریانِ GPS متوقف می‌شود (وگرنه
  /// foreground service و باتری بی‌دلیل مصرف می‌شدند).
  Future<void> _pushLiveLocation(LocationFix fix) async {
    final id = _liveLocationId;
    if (id == null) return;
    try {
      await _api.updateLiveLocation(id, lat: fix.lat, lng: fix.lng);
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 409 || e.status == 400) {
        _endLiveTracking();
        if (mounted) setState(() => _liveLocationId = null);
      }
    } catch (_) {}
  }

  Future<void> _stopLiveLocation() async {
    final id = _liveLocationId;
    if (id == null) return;
    _endLiveTracking();
    await _run(() async {
      await _api.stopLiveLocation(id);
      if (mounted) setState(() => _liveLocationId = null);
      await _load();
      _toast(tr('اشتراکِ موقعیتِ زنده متوقف شد.'));
    }, failure: tr('توقفِ موقعیتِ زنده ناموفق بود'));
  }

  Future<void> _sendSticker() async {
    final pick = await showStickerPicker(context, api: _api);
    if (pick == null || !mounted) return;
    final studio = pick.studio;
    if (studio != null) {
      await _sendStudioResult(studio);
      return;
    }
    await _run(() async {
      await _api.sendSticker(_room.id, pick.stickerId!, replyToId: _replyTo?.id);
      if (mounted) setState(() => _replyTo = null);
      await _load();
      _scrollToBottom();
    }, failure: tr('ارسالِ استیکر ناموفق بود'));
  }

  /// خروجیِ استودیو (تصویر/ویدیو/صدا) مثلِ هر رسانهٔ دیگری ارسال می‌شود؛ سرور
  /// نوعش را از پسوندِ فایل تشخیص می‌دهد، پس شاخهٔ جداگانه‌ای لازم نیست.
  Future<void> _sendStudioResult(StudioResult r) async {
    await _run(() async {
      final msg = await _api.sendMedia(_room.id, r.file.path,
          replyToId: _replyTo?.id);
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: tr('ارسالِ استیکر ناموفق بود'));
  }

  /// «ساختِ استیکر» از منوی پیوست — معادلِ `chat.makeSticker` در وب.
  Future<void> _openStickerStudio() async {
    final result = await openStickerStudio(context);
    if (result == null || !mounted) return;
    await _sendStudioResult(result);
  }

  Future<void> _createEvent() async {
    final draft = await showEventComposer(context);
    if (draft == null || !mounted) return;
    await _run(() async {
      await _api.createChatEvent(_room.id,
          title: draft.title,
          startsAt: draft.startsAt,
          location: draft.location,
          description: draft.description);
      await _load();
      _scrollToBottom();
    }, failure: tr('ارسالِ رویداد ناموفق بود'));
  }

  Future<void> _shareContact() async {
    final earthId =
        await promptEarthId(context, title: tr('Earth IDِ مخاطب'));
    if (earthId == null || earthId.isEmpty || !mounted) return;
    await _run(() async {
      await _api.shareContact(_room.id, earthId, replyToId: _replyTo?.id);
      if (mounted) setState(() => _replyTo = null);
      await _load();
      _scrollToBottom();
    }, failure: tr('اشتراکِ مخاطب ناموفق بود'));
  }

  // ─────────────── مدیریتِ اتاق ───────────────

  Future<void> _toggleMute() async {
    if (_room.isMuted) {
      await _run(() async {
        final muted = await _api.setRoomMute(_room.id, muted: false);
        if (mounted) setState(() => _room = _copyRoom(isMuted: muted));
      }, failure: tr('تغییرِ وضعیتِ اعلان ناموفق بود'));
      return;
    }
    final minutes = await showMutePicker(context);
    if (minutes == null || !mounted) return;
    await _run(() async {
      final muted = await _api.setRoomMute(
        _room.id,
        muted: true,
        durationMinutes: minutes == -1 ? null : minutes,
      );
      if (mounted) setState(() => _room = _copyRoom(isMuted: muted));
      _toast(muted ? tr('گفتگو بی‌صدا شد.') : tr('اعلان فعال شد.'));
    }, failure: tr('بی‌صداکردن ناموفق بود'));
  }

  Future<void> _toggleBlock() async {
    final earthId = _room.partnerEarthId;
    if (earthId == null || earthId.isEmpty) {
      _toast(tr('مسدودسازی فقط در گفتگویِ مستقیم ممکن است.'));
      return;
    }
    await _run(() async {
      final blocked = await _api.toggleBlock(earthId);
      if (mounted) setState(() => _room = _copyRoom(isBlocked: blocked));
      _toast(blocked ? tr('کاربر مسدود شد.') : tr('مسدودی برداشته شد.'));
    }, failure: tr('تغییرِ مسدودی ناموفق بود'));
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('پاک‌کردنِ گفتگو')),
        content: Text(
            tr('پیام‌ها فقط از نمای تو پاک می‌شوند؛ طرفِ مقابل دست‌نخورده می‌ماند.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('لغو'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('پاک کن'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _api.clearChat(_room.id);
      await _load();
    }, failure: tr('پاک‌کردن ناموفق بود'));
  }

  Future<void> _setDisappearing() async {
    final seconds = await showDisappearingPicker(
        context, _status?.disappearSeconds ?? _room.disappearSeconds);
    if (seconds == null || !mounted) return;
    await _run(() async {
      await _api.setDisappearing(_room.id, seconds);
      await _refreshStatus();
      _toast(seconds == 0
          ? tr('پیامِ ناپدیدشونده خاموش شد.')
          : tr('پیامِ ناپدیدشونده فعال شد.'));
    }, failure: tr('تنظیمِ ناپدیدشدن ناموفق بود'));
  }

  Future<void> _search() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SearchSheet(api: _api, roomId: _room.id),
    );
  }

  Future<void> _showPins() async {
    await _loadPins();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin),
              title: Text(tr('پیام‌های سنجاق‌شده')),
            ),
            const Divider(height: 1),
            if (_pins.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('هیچ پیامی سنجاق نشده است.')),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _pins
                      .map((m) => ListTile(
                            dense: true,
                            title: Text(
                              m.content.isEmpty
                                  ? (m.mediaType ?? tr('رسانه'))
                                  : m.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(m.senderName ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.push_pin_outlined),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _run(() async {
                                  await _api.pinMessage(m.id);
                                  await Future.wait([_load(), _loadPins()]);
                                }, failure: tr('برداشتنِ سنجاق ناموفق بود'));
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// نسخهٔ به‌روزِ اتاق با تغییرِ چند فیلد (مدل immutable است).
  ChatRoom _copyRoom({bool? isMuted, bool? isBlocked}) => ChatRoom(
        id: _room.id,
        roomType: _room.roomType,
        title: _room.title,
        isE2ee: _room.isE2ee,
        createdBy: _room.createdBy,
        partnerName: _room.partnerName,
        partnerEarthId: _room.partnerEarthId,
        partnerRole: _room.partnerRole,
        partnerAvatar: _room.partnerAvatar,
        lastMessage: _room.lastMessage,
        lastMessageAt: _room.lastMessageAt,
        unreadCount: _room.unreadCount,
        partnerOnline: _room.partnerOnline,
        memberCount: _room.memberCount,
        isAdmin: _room.isAdmin,
        partnerLastSeen: _room.partnerLastSeen,
        isMuted: isMuted ?? _room.isMuted,
        isBlocked: isBlocked ?? _room.isBlocked,
        disappearSeconds: _room.disappearSeconds,
      );

  void _startCall(CallMedia media) {
    final peerId = _room.partnerEarthId;
    if (peerId == null || peerId.isEmpty) {
      _toast(tr('تماس فقط در گفتگویِ مستقیم ممکن است.'));
      return;
    }
    CallScope.of(context).startCall(
      peerId: peerId,
      peerName: _room.displayTitle,
      media: media,
    );
  }

  Future<void> _translateCompose() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final lang = await showLanguagePicker(context);
    if (lang == null || !mounted) return;
    await _run(() async {
      final result = await _api.translateText(text, lang);
      _inputCtrl.value = TextEditingValue(
        text: result.translatedText,
        selection: TextSelection.collapsed(offset: result.translatedText.length),
      );
      _translateLanguage = lang;
      await _persistChatPreferences();
    }, failure: tr('ترجمهٔ متن ناموفق بود'));
  }

  Future<void> _translationSettings() async {
    var enabled = _autoTranslate;
    var language = _translateLanguage;
    final result = await showModalBottomSheet<(bool, String)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        const langs = <String, String>{
          'fa': 'فارسی', 'en': 'English', 'ar': 'العربية', 'tr': 'Türkçe',
          'ru': 'Русский', 'fr': 'Français', 'de': 'Deutsch', 'es': 'Español',
          'zh': '中文', 'hi': 'हिन्दी', 'ur': 'اردو', 'ps': 'پښتو',
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                value: enabled,
                title: Text(tr('ترجمهٔ خودکارِ پیام‌های دریافتی')),
                onChanged: (v) => setLocal(() => enabled = v),
              ),
              Align(alignment: Alignment.centerRight, child: Text(tr('زبانِ مقصد'))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in langs.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: language == e.key,
                    onSelected: (_) => setLocal(() => language = e.key),
                  ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, (enabled, language)),
                  child: Text(tr('ذخیره و ترجمهٔ پیام‌های موجود')),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (result == null || !mounted) return;
    setState(() {
      _autoTranslate = result.$1;
      _translateLanguage = result.$2;
      _translations.clear();
    });
    await _persistChatPreferences();
    if (_autoTranslate) await _translateIncoming(_messages);
  }

  Future<void> _chatAppearance() async {
    var wallpaper = _wallpaperIndex;
    var bubble = _mineBubbleColor ?? Theme.of(context).colorScheme.primary;
    final saved = await showModalBottomSheet<(int, Color)>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerRight, child: Text(tr('پس‌زمینهٔ گفتگو'))),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              for (var i = 0; i < _wallpapers.length; i++)
                ChoiceChip(
                  selected: wallpaper == i,
                  label: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: _wallpapers[i]),
                      border: Border.all(color: Theme.of(ctx).dividerColor),
                    ),
                  ),
                  onSelected: (_) => setLocal(() => wallpaper = i),
                ),
            ]),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerRight, child: Text(tr('رنگِ حباب‌های من'))),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              for (final color in _bubbleColors)
                ChoiceChip(
                  selected: bubble.toARGB32() == color.toARGB32(),
                  label: CircleAvatar(radius: 13, backgroundColor: color),
                  onSelected: (_) => setLocal(() => bubble = color),
                ),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () => Navigator.pop(ctx, (wallpaper, bubble)),
              child: Text(tr('ذخیره')),
            )),
          ]),
        ),
      )),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _wallpaperIndex = saved.$1;
      _mineBubbleColor = saved.$2;
    });
    await _persistChatPreferences();
  }

  Future<void> _emojiPicker() async {
    const emojis = <String>[
      '😀','😂','😍','🥰','😎','🤔','😭','😡','👍','👎','👏','🙏','🔥','❤️','💯','🎉',
      '🌹','✨','💪','🤝','✅','⭐','🚀','📌','💬','😊','😉','😅','🤩','🥳','😴','🤯',
    ];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 8,
        padding: const EdgeInsets.all(12),
        children: [for (final e in emojis) InkWell(
          onTap: () => Navigator.pop(ctx, e),
          child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
        )],
      )),
    );
    if (emoji == null) return;
    final value = _inputCtrl.value;
    final start = value.selection.isValid ? value.selection.start : value.text.length;
    final end = value.selection.isValid ? value.selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, emoji);
    _inputCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    final isDirect =
        _room.partnerEarthId != null && _room.partnerEarthId!.isNotEmpty;
    return Scaffold(
      appBar: _selectMode ? _selectionBar() : AppBar(
        titleSpacing: 0,
        title: _appBarTitle(),
        actions: [
          if (isDirect) ...[
            IconButton(
              tooltip: tr('تماسِ صوتی'),
              icon: const Icon(Icons.call),
              onPressed: () => _startCall(CallMedia.audio),
            ),
            IconButton(
              tooltip: tr('تماسِ تصویری'),
              icon: const Icon(Icons.videocam),
              onPressed: () => _startCall(CallMedia.video),
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'search':
                  _search();
                case 'pins':
                  _showPins();
                case 'members':
                  showMembersSheet(context,
                      api: _api, room: _room, onChanged: _load);
                case 'mute':
                  _toggleMute();
                case 'block':
                  _toggleBlock();
                case 'clear':
                  _clearChat();
                case 'disappearing':
                  _setDisappearing();
                case 'report':
                  _report();
                case 'translate_settings':
                  _translationSettings();
                case 'appearance':
                  _chatAppearance();
                case 'export':
                  _exportChat();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                  value: 'search',
                  child: ListTile(
                      leading: const Icon(Icons.search),
                      title: Text(tr('جستجو در گفتگو')))),
              PopupMenuItem(
                  value: 'pins',
                  child: ListTile(
                      leading: const Icon(Icons.push_pin),
                      title: Text(tr('سنجاق‌شده‌ها')))),
              PopupMenuItem(
                  value: 'translate_settings',
                  child: ListTile(
                      leading: const Icon(Icons.translate),
                      title: Text(tr('ترجمهٔ همزمان')))),
              PopupMenuItem(
                  value: 'appearance',
                  child: ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: Text(tr('ظاهرِ گفتگو')))),
              PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(tr('خروجیِ گفتگو')))),
              if (_room.isGroup)
                PopupMenuItem(
                    value: 'members',
                    child: ListTile(
                        leading: const Icon(Icons.group), title: Text(tr('اعضا')))),
              PopupMenuItem(
                value: 'mute',
                child: ListTile(
                  leading: Icon(_room.isMuted
                      ? Icons.notifications_active
                      : Icons.notifications_off),
                  title: Text(_room.isMuted ? tr('فعال‌کردنِ اعلان') : tr('بی‌صدا')),
                ),
              ),
              PopupMenuItem(
                  value: 'disappearing',
                  child: ListTile(
                      leading: const Icon(Icons.timer),
                      title: Text(tr('پیامِ ناپدیدشونده')))),
              PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                      leading: const Icon(Icons.cleaning_services),
                      title: Text(tr('پاک‌کردنِ گفتگو')))),
              if (isDirect) ...[
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(_room.isBlocked ? tr('رفعِ مسدودی') : tr('مسدودکردن')),
                  ),
                ),
                PopupMenuItem(
                    value: 'report',
                    child: ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(tr('گزارشِ تخلف')))),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pins.isNotEmpty) _pinnedBar(),
          if ((_status?.disappearSeconds ?? 0) > 0) _disappearingBanner(),
          if (_liveLocationId != null) _liveLocationBanner(),
          if (_room.isBlocked) _blockedBanner(),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: _wallpapers[_wallpaperIndex.clamp(0, _wallpapers.length - 1)],
                ),
              ),
              child: _body(),
            ),
          ),
          if (_replyTo != null || _editing != null) _draftBanner(),
          _composer(),
        ],
      ),
    );
  }

  PreferredSizeWidget _selectionBar() => AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelection),
        title: Text(tr('{0} انتخاب', [_selectedIds.length])),
        actions: [
          IconButton(tooltip: tr('کپی'), icon: const Icon(Icons.copy), onPressed: _bulkCopy),
          IconButton(tooltip: tr('اشتراک'), icon: const Icon(Icons.share_outlined),
              onPressed: () async {
                await _shareMessages(_selectedMessages);
                _exitSelection();
              }),
          IconButton(tooltip: tr('بازارسال'), icon: const Icon(Icons.shortcut), onPressed: _bulkForward),
          IconButton(tooltip: tr('حذف پیام‌های من'), icon: const Icon(Icons.delete_outline), onPressed: _bulkDelete),
        ],
      );

  Widget _appBarTitle() {
    final avatar = AppConfig.absoluteMedia(_room.partnerAvatar);
    final online = _status?.partnerOnline ?? _room.partnerOnline;
    final typing = _status?.typing ?? const [];
    final subtitle = typing.isNotEmpty
        ? (_room.isGroup
            ? tr('{0} در حالِ نوشتن…', [typing.join(tr('، '))])
            : tr('در حالِ نوشتن…'))
        : (_room.isGroup
            ? tr('{0} عضو', [_room.memberCount])
            : (online ? tr('آنلاین') : _lastSeenLabel()));
    final partnerId = _room.partnerEarthId;
    // مثلِ وب (آواتار/نامِ هدرِ direct → `/u/{partner_earth_id}`) هدر به پروفایل
    // می‌رود؛ در گروه مقصدی وجود ندارد پس تپ غیرفعال می‌ماند.
    return InkWell(
      onTap: (partnerId == null || partnerId.isEmpty)
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ProfileScreen(
                    earthId: partnerId, fallbackName: _room.partnerName),
              )),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: online ? const Color(0xFF22C55E) : Colors.grey,
            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
            child: avatar == null
                ? Text(
                    _room.displayTitle.isNotEmpty
                        ? _room.displayTitle.characters.first
                        : tr('؟'),
                    style: const TextStyle(color: Colors.white))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(_room.displayTitle,
                          style: const TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (_room.isMuted)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.notifications_off, size: 13),
                      ),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: typing.isNotEmpty
                        ? const Color(0xFF60A5FA)
                        : (online ? const Color(0xFF22C55E) : Colors.grey),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _lastSeenLabel() {
    final t = _status?.partnerLastSeen ?? _room.partnerLastSeen;
    if (t == null) return tr('آفلاین');
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inMinutes < 1) return tr('همین حالا');
    if (diff.inMinutes < 60) return tr('{0} دقیقه پیش', [diff.inMinutes]);
    if (diff.inHours < 24) return tr('{0} ساعت پیش', [diff.inHours]);
    return tr('{0} روز پیش', [diff.inDays]);
  }

  Widget _pinnedBar() {
    final first = _pins.first;
    return InkWell(
      onTap: _showPins,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            const Icon(Icons.push_pin, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                first.content.isEmpty
                    ? (first.mediaType ?? tr('رسانه'))
                    : first.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (_pins.length > 1)
              Text('${_pins.length}', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _liveLocationBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: Colors.blue.withValues(alpha: 0.16),
        child: Row(
          children: [
            const Icon(Icons.podcasts, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(tr('موقعیتِ زندهٔ تو در حالِ اشتراک است.'),
                  style: const TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: _sending ? null : _stopLiveLocation,
              child: Text(tr('توقف'), style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );

  Widget _disappearingBanner() {
    final s = _status!.disappearSeconds;
    final label = switch (s) {
      3600 => tr('۱ ساعت'),
      86400 => tr('۲۴ ساعت'),
      604800 => tr('۷ روز'),
      _ => tr('{0} ثانیه', [s]),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: DilixSemanticColors.from(context).warningContainer,
      child: Row(
        children: [
          Icon(Icons.timer,
              size: 14,
              color: DilixSemanticColors.from(context).onWarningContainer),
          const SizedBox(width: 6),
          Text(tr('پیام‌ها پس از {0} ناپدید می‌شوند.', [label]),
              style: TextStyle(
                  fontSize: 11,
                  color:
                      DilixSemanticColors.from(context).onWarningContainer)),
        ],
      ),
    );
  }

  Widget _blockedBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Row(
          children: [
            Icon(Icons.block,
                size: 14,
                color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr('این کاربر مسدود است؛ ارسالِ پیام ممکن نیست.'),
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );

  Widget _draftBanner() {
    final editing = _editing != null;
    final m = _editing ?? _replyTo!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(editing ? Icons.edit : Icons.reply, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(editing ? tr('ویرایشِ پیام') : tr('پاسخ به {0}', [m.senderName ?? '']),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
                Text(
                  m.content.isEmpty ? (m.mediaType ?? tr('رسانه')) : m.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _replyTo = null;
              _editing = null;
              if (editing) _inputCtrl.clear();
            }),
          ),
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
              Text(tr('بارگذاریِ گفتگو ناموفق بود.\n{0}', [_error]),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () => _load(initial: true),
                  child: Text(tr('تلاشِ دوباره'))),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(child: Text(tr('هنوز پیامی نیست. اولین پیام را بفرست.')));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final m = _messages[i];
        return MessageBubble(
          message: m,
          showSender: _room.isGroup,
          translation: _translations[m.id],
          selected: _selectedIds.contains(m.id),
          mineColor: _mineBubbleColor,
          onTap: _selectMode ? () => _toggleSelected(m) : null,
          onLongPress: () {
            if (_selectMode) {
              _toggleSelected(m);
            } else {
              _messageActions(m);
            }
          },
          onSwipeReply: _selectMode ? null : () => setState(() {
            _replyTo = m;
            _editing = null;
          }),
          onSwipeShare: _selectMode ? null : () => _shareMessages([m]),
          onVote: _vote,
          onOpenRedPacket: _onRedPacket,
          onSettleMoney: _settleMoney,
          onTapContact: _openContact,
          onTapMedia: _openMedia,
          onTapReply: _jumpToReply,
          onToggleReaction: (emoji) => _toggleReaction(m, emoji),
        );
      },
    );
  }

  Future<void> _openContact(ContactInfo c) async {
    await _run(() async {
      final room = await _api.createDirectRoom(c.earthId, title: c.name);
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ChatScreen(room: room)));
    }, failure: tr('بازکردنِ گفتگو ناموفق بود'));
  }

  void _openMedia(ChatMessage m) {
    final url = AppConfig.absoluteMedia(m.mediaUrl);
    if (url == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewer(
          url: url,
          isVideo: m.mediaType == 'video',
          isAudio: m.mediaType == 'voice',
          title: m.mediaName,
        ),
      ),
    );
  }

  /// پرش به پیامی که پاسخ به آن داده شده (اگر در فهرستِ بارگذاری‌شده باشد).
  void _jumpToReply(ReplyPreview r) {
    final index = _messages.indexWhere((m) => m.id == r.id);
    if (index < 0) {
      _toast(tr('پیامِ اصلی در این بازه بارگذاری نشده است.'));
      return;
    }
    if (!_scrollCtrl.hasClients) return;
    final target = _scrollCtrl.position.maxScrollExtent *
        (index / _messages.length.clamp(1, double.infinity));
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Widget _composer() {
    final blocked = _room.isBlocked;
    if (_recording) return _recordingBar();
    final hasText = _inputCtrl.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('پیوست'),
              icon: const Icon(Icons.add_circle_outline),
              onPressed: blocked || _sending ? null : _attachmentSheet,
            ),
            IconButton(
              tooltip: tr('ایموجی'),
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: blocked || _sending ? null : _emojiPicker,
            ),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                enabled: !blocked,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: blocked ? tr('کاربر مسدود است') : tr('پیام…'),
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
            const SizedBox(width: 4),
            if (hasText)
              IconButton(
                tooltip: tr('ترجمهٔ متنِ در حالِ نگارش'),
                icon: const Icon(Icons.translate),
                onPressed: blocked || _sending ? null : _translateCompose,
              ),
            if (hasText || _editing != null)
              IconButton(
                tooltip: tr('دوربین'),
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: blocked || _sending ? null : _captureAndSendPhoto,
              )
            else
              IconButton(
                tooltip: tr('پیامِ صوتی'),
                icon: const Icon(Icons.mic_none),
                onPressed: blocked || _sending ? null : _startRecording,
              ),
            IconButton.filled(
              onPressed: blocked || _sending
                  ? null
                  : (hasText || _editing != null ? _send : _captureAndSendPhoto),
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_editing != null
                      ? Icons.check
                      : hasText
                          ? Icons.send
                          : Icons.photo_camera_outlined),
            ),
          ],
        ),
      ),
    );
  }

  /// نوارِ ضبطِ صدا: زمانِ سپری‌شده + لغو + ارسال.
  Widget _recordingBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Icon(Icons.fiber_manual_record,
                color: Theme.of(context).colorScheme.error, size: 16),
            const SizedBox(width: 8),
            Text(
              '${_recElapsed.inMinutes.toString().padLeft(2, '0')}:'
              '${_recElapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('در حالِ ضبطِ پیامِ صوتی…'),
                  style: const TextStyle(fontSize: 12)),
            ),
            IconButton(
              tooltip: tr('لغو'),
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              onPressed: _cancelRecording,
            ),
            IconButton.filled(
              onPressed: _stopAndSendRecording,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attachmentSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: Text(tr('عکس از گالری')),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(tr('ویدیو از گالری')),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(tr('فایل')),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.place),
              title: Text(tr('موقعیتِ مکانی')),
              onTap: () => Navigator.pop(ctx, 'location'),
            ),
            ListTile(
              leading: Icon(_liveLocationId == null
                  ? Icons.podcasts
                  : Icons.stop_circle_outlined),
              title: Text(_liveLocationId == null
                  ? tr('موقعیتِ زنده')
                  : tr('توقفِ موقعیتِ زنده')),
              onTap: () => Navigator.pop(ctx, 'live'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: Text(tr('استیکر')),
              onTap: () => Navigator.pop(ctx, 'sticker'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(tr('ساختِ استیکر')),
              onTap: () => Navigator.pop(ctx, 'studio'),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: Text(tr('نظرسنجی')),
              onTap: () => Navigator.pop(ctx, 'poll'),
            ),
            ListTile(
              leading: const Text('🧧', style: TextStyle(fontSize: 20)),
              title: Text(tr('هدیهٔ نقدی')),
              onTap: () => Navigator.pop(ctx, 'redpacket'),
            ),
            // پولِ مستقیم فقط در گفتگویِ دونفره؛ پولِ گروهی مسیرِ 🧧 را دارد.
            if (_room.roomType != 'group') ...[
              ListTile(
                leading: const Icon(Icons.payments),
                title: Text(tr('ارسالِ پول')),
                onTap: () => Navigator.pop(ctx, 'money_send'),
              ),
              ListTile(
                leading: const Icon(Icons.request_quote),
                title: Text(tr('درخواستِ پول')),
                onTap: () => Navigator.pop(ctx, 'money_request'),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.event),
              title: Text(tr('رویداد')),
              onTap: () => Navigator.pop(ctx, 'event'),
            ),
            ListTile(
              leading: const Icon(Icons.contact_page),
              title: Text(tr('اشتراکِ مخاطب')),
              onTap: () => Navigator.pop(ctx, 'contact'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'image':
        await _pickAndSendMedia(video: false);
      case 'video':
        await _pickAndSendMedia(video: true);
      case 'file':
        await _pickAndSendFile();
      case 'location':
        await _sendLocation();
      case 'live':
        if (_liveLocationId == null) {
          await _startLiveLocation();
        } else {
          await _stopLiveLocation();
        }
      case 'sticker':
        await _sendSticker();
      case 'studio':
        await _openStickerStudio();
      case 'poll':
        await _createPoll();
      case 'redpacket':
        await _createRedPacket();
      case 'money_send':
        await _composeMoney(request: false);
      case 'money_request':
        await _composeMoney(request: true);
      case 'event':
        await _createEvent();
      case 'contact':
        await _shareContact();
    }
  }
}

/// شیتِ جستجویِ متنی در پیام‌هایِ یک اتاق.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.api, required this.roomId});
  final ApiClient api;
  final String roomId;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();
  List<ChatMessage> _results = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      setState(() => _error = tr('حداقل ۲ نویسه لازم است.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.searchMessages(widget.roomId, q);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: tr('جستجو در پیام‌ها…'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _run,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            )
          else if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr('نتیجه‌ای نیست.')),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final m = _results[i];
                  final d = m.sentAt.toLocal();
                  return ListTile(
                    dense: true,
                    title: Text(m.content,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${m.senderName ?? ''} • '
                      '${d.year}/${d.month}/${d.day} '
                      '${d.hour.toString().padLeft(2, '0')}:'
                      '${d.minute.toString().padLeft(2, '0')}',
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
