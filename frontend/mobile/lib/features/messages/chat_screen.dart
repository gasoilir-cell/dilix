import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../call/call_service.dart';
import 'chat_sheets.dart';
import 'media_viewer.dart';
import 'message_bubble.dart';

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

  /// ضبطِ پیامِ صوتی.
  final _recorder = AudioRecorder();
  bool _recording = false;
  Duration _recElapsed = Duration.zero;
  Timer? _recTimer;
  String? _recPath;

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
    _recTimer?.cancel();
    _recorder.dispose();
    _scrollCtrl.dispose();
    _inputCtrl
      ..removeListener(_onInputChanged)
      ..dispose();
    super.dispose();
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
      });
      if (initial || (hadNew && wasAtBottom)) _scrollToBottom();
      if (hadNew && !initial) _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (initial) _error = '$e';
      });
    }
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
      _toast('${failure ?? 'عملیات ناموفق بود'}: $e');
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
      }, failure: 'ویرایش ناموفق بود');
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
    }, failure: 'ارسال ناموفق بود');
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

  Future<void> _pickAndSendMedia({required bool video}) async {
    final XFile? file = video
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final caption = _inputCtrl.text.trim();
    await _run(() async {
      final msg = await _api.sendMedia(
        _room.id,
        file.path,
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
    }, failure: 'ارسالِ رسانه ناموفق بود');
  }

  Future<void> _captureAndSendPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    await _run(() async {
      final msg = await _api.sendMedia(_room.id, file.path,
          replyToId: _replyTo?.id);
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();
    }, failure: 'ارسالِ عکس ناموفق بود');
  }

  /// پیوستِ فایلِ دلخواه (سند/PDF/…). سقفِ سرور ۲۵MB است.
  Future<void> _pickAndSendFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles();
    } catch (e) {
      _toast('انتخابِ فایل ناموفق بود: $e');
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
    }, failure: 'ارسالِ فایل ناموفق بود');
  }

  // ─────────────── پیامِ صوتی ───────────────

  /// شروعِ ضبط. مجوزِ میکروفن را خودِ پلاگین می‌گیرد؛ در نبودِ مجوز پیام می‌دهیم.
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast('برای ضبطِ صدا به اجازهٔ میکروفن نیاز است.');
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
      _toast('شروعِ ضبط ناموفق بود: $e');
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
      _toast('پیامِ صوتی خیلی کوتاه بود.');
      return;
    }
    if (path == null) {
      _toast('فایلِ صوتی ساخته نشد.');
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
    }, failure: 'ارسالِ پیامِ صوتی ناموفق بود');
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
              title: const Text('پاسخ'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (m.isPlainText && m.content.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('کپیِ متن'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            ListTile(
              leading: const Icon(Icons.shortcut),
              title: const Text('بازارسال'),
              onTap: () => Navigator.pop(ctx, 'forward'),
            ),
            ListTile(
              leading: Icon(m.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(m.isPinned ? 'برداشتنِ سنجاق' : 'سنجاق‌کردن'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            if (m.content.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('ترجمه'),
                onTap: () => Navigator.pop(ctx, 'translate'),
              ),
            if (m.isMine && m.isPlainText && !m.deleted)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('ویرایش'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (m.isMine && !m.deleted)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title:
                    const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            if (!m.isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('گزارشِ تخلف'),
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
      case 'pin':
        await _run(() async {
          await _api.pinMessage(m.id);
          await Future.wait([_load(), _loadPins()]);
        }, failure: 'سنجاق ناموفق بود');
      case 'translate':
        await _translate(m);
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
    }, failure: 'ثبتِ واکنش ناموفق بود');
  }

  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذفِ پیام'),
        content: const Text('این پیام برای همه حذف می‌شود. مطمئنی؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لغو')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _api.deleteMessage(m.id);
      await _load();
    }, failure: 'حذف ناموفق بود');
  }

  Future<void> _forward(ChatMessage m) async {
    List<ChatRoom> rooms;
    try {
      rooms = await _api.listRooms();
    } catch (e) {
      _toast('دریافتِ فهرستِ گفتگوها ناموفق بود: $e');
      return;
    }
    if (!mounted) return;
    final picked =
        await showForwardPicker(context, rooms: rooms, currentRoomId: _room.id);
    if (picked == null || !mounted) return;
    await _run(() async {
      await _api.forwardMessage(m.id, picked.$1, anonymous: picked.$2);
      _toast('بازارسال شد.');
    }, failure: 'بازارسال ناموفق بود');
  }

  Future<void> _translate(ChatMessage m) async {
    final lang = await showLanguagePicker(context);
    if (lang == null || !mounted) return;
    await _run(() async {
      final r = await _api.translateMessage(m.id, lang);
      if (mounted) {
        setState(() => _translations[m.id] = r.translatedText);
      }
    }, failure: 'ترجمه ناموفق بود');
  }

  Future<void> _report({String? messageId}) async {
    final earthId = _room.partnerEarthId;
    if (earthId == null || earthId.isEmpty) {
      _toast('گزارش فقط در گفتگویِ مستقیم ممکن است.');
      return;
    }
    final result = await showReportSheet(context);
    if (result == null || !mounted) return;
    await _run(() async {
      await _api.reportUser(earthId,
          reason: result.$1, note: result.$2, messageId: messageId);
      _toast('گزارش ثبت شد. سپاس از هم‌کاری.');
    }, failure: 'ثبتِ گزارش ناموفق بود');
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
    }, failure: 'ساختِ نظرسنجی ناموفق بود');
  }

  Future<void> _vote(PollInfo poll, int index) async {
    await _run(() async {
      await _api.votePoll(poll.id, index);
      await _load();
    }, failure: 'ثبتِ رأی ناموفق بود');
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
    }, failure: 'ارسالِ هدیه ناموفق بود');
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
      _toast('🧧 ${(amount / 10).round()} تومان به کیفِ پاداشِ تو اضافه شد.');
      await _load();
    }, failure: 'بازکردنِ هدیه ناموفق بود');
  }

  Future<void> _sendLocation() async {
    final loc = await showLocationComposer(context);
    if (loc == null || !mounted) return;
    await _run(() async {
      await _api.sendLocation(_room.id,
          lat: loc.$1, lng: loc.$2, label: loc.$3, replyToId: _replyTo?.id);
      if (mounted) setState(() => _replyTo = null);
      await _load();
      _scrollToBottom();
    }, failure: 'ارسالِ موقعیت ناموفق بود');
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
    }, failure: 'ارسالِ رویداد ناموفق بود');
  }

  Future<void> _shareContact() async {
    final earthId =
        await promptEarthId(context, title: 'Earth IDِ مخاطب');
    if (earthId == null || earthId.isEmpty || !mounted) return;
    await _run(() async {
      await _api.shareContact(_room.id, earthId, replyToId: _replyTo?.id);
      if (mounted) setState(() => _replyTo = null);
      await _load();
      _scrollToBottom();
    }, failure: 'اشتراکِ مخاطب ناموفق بود');
  }

  // ─────────────── مدیریتِ اتاق ───────────────

  Future<void> _toggleMute() async {
    if (_room.isMuted) {
      await _run(() async {
        final muted = await _api.setRoomMute(_room.id, muted: false);
        if (mounted) setState(() => _room = _copyRoom(isMuted: muted));
      }, failure: 'تغییرِ وضعیتِ اعلان ناموفق بود');
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
      _toast(muted ? 'گفتگو بی‌صدا شد.' : 'اعلان فعال شد.');
    }, failure: 'بی‌صداکردن ناموفق بود');
  }

  Future<void> _toggleBlock() async {
    final earthId = _room.partnerEarthId;
    if (earthId == null || earthId.isEmpty) {
      _toast('مسدودسازی فقط در گفتگویِ مستقیم ممکن است.');
      return;
    }
    await _run(() async {
      final blocked = await _api.toggleBlock(earthId);
      if (mounted) setState(() => _room = _copyRoom(isBlocked: blocked));
      _toast(blocked ? 'کاربر مسدود شد.' : 'مسدودی برداشته شد.');
    }, failure: 'تغییرِ مسدودی ناموفق بود');
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌کردنِ گفتگو'),
        content: const Text(
            'پیام‌ها فقط از نمای تو پاک می‌شوند؛ طرفِ مقابل دست‌نخورده می‌ماند.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لغو')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('پاک کن')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _api.clearChat(_room.id);
      await _load();
    }, failure: 'پاک‌کردن ناموفق بود');
  }

  Future<void> _setDisappearing() async {
    final seconds = await showDisappearingPicker(
        context, _status?.disappearSeconds ?? _room.disappearSeconds);
    if (seconds == null || !mounted) return;
    await _run(() async {
      await _api.setDisappearing(_room.id, seconds);
      await _refreshStatus();
      _toast(seconds == 0
          ? 'پیامِ ناپدیدشونده خاموش شد.'
          : 'پیامِ ناپدیدشونده فعال شد.');
    }, failure: 'تنظیمِ ناپدیدشدن ناموفق بود');
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
            const ListTile(
              leading: Icon(Icons.push_pin),
              title: Text('پیام‌های سنجاق‌شده'),
            ),
            const Divider(height: 1),
            if (_pins.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('هیچ پیامی سنجاق نشده است.'),
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
                                  ? (m.mediaType ?? 'رسانه')
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
                                }, failure: 'برداشتنِ سنجاق ناموفق بود');
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
      _toast('تماس فقط در گفتگویِ مستقیم ممکن است.');
      return;
    }
    CallScope.of(context).startCall(
      peerId: peerId,
      peerName: _room.displayTitle,
      media: media,
    );
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    final isDirect =
        _room.partnerEarthId != null && _room.partnerEarthId!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _appBarTitle(),
        actions: [
          if (isDirect) ...[
            IconButton(
              tooltip: 'تماسِ صوتی',
              icon: const Icon(Icons.call),
              onPressed: () => _startCall(CallMedia.audio),
            ),
            IconButton(
              tooltip: 'تماسِ تصویری',
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
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 'search',
                  child: ListTile(
                      leading: Icon(Icons.search),
                      title: Text('جستجو در گفتگو'))),
              const PopupMenuItem(
                  value: 'pins',
                  child: ListTile(
                      leading: Icon(Icons.push_pin),
                      title: Text('سنجاق‌شده‌ها'))),
              if (_room.isGroup)
                const PopupMenuItem(
                    value: 'members',
                    child: ListTile(
                        leading: Icon(Icons.group), title: Text('اعضا'))),
              PopupMenuItem(
                value: 'mute',
                child: ListTile(
                  leading: Icon(_room.isMuted
                      ? Icons.notifications_active
                      : Icons.notifications_off),
                  title: Text(_room.isMuted ? 'فعال‌کردنِ اعلان' : 'بی‌صدا'),
                ),
              ),
              const PopupMenuItem(
                  value: 'disappearing',
                  child: ListTile(
                      leading: Icon(Icons.timer),
                      title: Text('پیامِ ناپدیدشونده'))),
              const PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                      leading: Icon(Icons.cleaning_services),
                      title: Text('پاک‌کردنِ گفتگو'))),
              if (isDirect) ...[
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(_room.isBlocked ? 'رفعِ مسدودی' : 'مسدودکردن'),
                  ),
                ),
                const PopupMenuItem(
                    value: 'report',
                    child: ListTile(
                        leading: Icon(Icons.flag_outlined),
                        title: Text('گزارشِ تخلف'))),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pins.isNotEmpty) _pinnedBar(),
          if ((_status?.disappearSeconds ?? 0) > 0) _disappearingBanner(),
          if (_room.isBlocked) _blockedBanner(),
          Expanded(child: _body()),
          if (_replyTo != null || _editing != null) _draftBanner(),
          _composer(),
        ],
      ),
    );
  }

  Widget _appBarTitle() {
    final avatar = AppConfig.absoluteMedia(_room.partnerAvatar);
    final online = _status?.partnerOnline ?? _room.partnerOnline;
    final typing = _status?.typing ?? const [];
    final subtitle = typing.isNotEmpty
        ? (_room.isGroup
            ? '${typing.join('، ')} در حالِ نوشتن…'
            : 'در حالِ نوشتن…')
        : (_room.isGroup
            ? '${_room.memberCount} عضو'
            : (online ? 'آنلاین' : _lastSeenLabel()));
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: online ? const Color(0xFF22C55E) : Colors.grey,
          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
          child: avatar == null
              ? Text(
                  _room.displayTitle.isNotEmpty
                      ? _room.displayTitle.characters.first
                      : '؟',
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
    );
  }

  String _lastSeenLabel() {
    final t = _status?.partnerLastSeen ?? _room.partnerLastSeen;
    if (t == null) return 'آفلاین';
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inMinutes < 1) return 'همین حالا';
    if (diff.inMinutes < 60) return '${diff.inMinutes} دقیقه پیش';
    if (diff.inHours < 24) return '${diff.inHours} ساعت پیش';
    return '${diff.inDays} روز پیش';
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
                    ? (first.mediaType ?? 'رسانه')
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

  Widget _disappearingBanner() {
    final s = _status!.disappearSeconds;
    final label = switch (s) {
      3600 => '۱ ساعت',
      86400 => '۲۴ ساعت',
      604800 => '۷ روز',
      _ => '$s ثانیه',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.amber.withValues(alpha: 0.18),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 14),
          const SizedBox(width: 6),
          Text('پیام‌ها پس از $label ناپدید می‌شوند.',
              style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _blockedBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.red.withValues(alpha: 0.18),
        child: const Row(
          children: [
            Icon(Icons.block, size: 14, color: Colors.red),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'این کاربر مسدود است؛ ارسالِ پیام ممکن نیست.',
                style: TextStyle(fontSize: 11),
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
                Text(editing ? 'ویرایشِ پیام' : 'پاسخ به ${m.senderName ?? ''}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
                Text(
                  m.content.isEmpty ? (m.mediaType ?? 'رسانه') : m.content,
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
              Text('بارگذاریِ گفتگو ناموفق بود.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () => _load(initial: true),
                  child: const Text('تلاشِ دوباره')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('هنوز پیامی نیست. اولین پیام را بفرست.'));
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
          onLongPress: () => _messageActions(m),
          onVote: _vote,
          onOpenRedPacket: _onRedPacket,
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
    }, failure: 'بازکردنِ گفتگو ناموفق بود');
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
      _toast('پیامِ اصلی در این بازه بارگذاری نشده است.');
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
              tooltip: 'پیوست',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: blocked || _sending ? null : _attachmentSheet,
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
                  hintText: blocked ? 'کاربر مسدود است' : 'پیام…',
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
            if (hasText || _editing != null)
              IconButton(
                tooltip: 'دوربین',
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: blocked || _sending ? null : _captureAndSendPhoto,
              )
            else
              IconButton(
                tooltip: 'پیامِ صوتی',
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
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Text(
              '${_recElapsed.inMinutes.toString().padLeft(2, '0')}:'
              '${_recElapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}',
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('در حالِ ضبطِ پیامِ صوتی…',
                  style: TextStyle(fontSize: 12)),
            ),
            IconButton(
              tooltip: 'لغو',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
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
              title: const Text('عکس از گالری'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('ویدیو از گالری'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('فایل'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.place),
              title: const Text('موقعیتِ مکانی'),
              onTap: () => Navigator.pop(ctx, 'location'),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('نظرسنجی'),
              onTap: () => Navigator.pop(ctx, 'poll'),
            ),
            ListTile(
              leading: const Text('🧧', style: TextStyle(fontSize: 20)),
              title: const Text('هدیهٔ نقدی'),
              onTap: () => Navigator.pop(ctx, 'redpacket'),
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('رویداد'),
              onTap: () => Navigator.pop(ctx, 'event'),
            ),
            ListTile(
              leading: const Icon(Icons.contact_page),
              title: const Text('اشتراکِ مخاطب'),
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
      case 'poll':
        await _createPoll();
      case 'redpacket':
        await _createRedPacket();
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
      setState(() => _error = 'حداقل ۲ نویسه لازم است.');
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
              hintText: 'جستجو در پیام‌ها…',
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
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('نتیجه‌ای نیست.'),
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
