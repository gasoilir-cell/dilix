import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';

/// شیت‌هایِ کمکیِ گفتگو: ساختِ نظرسنجی، هدیهٔ نقدی، رویداد، انتخابِ اتاقِ
/// بازارسال، اعضایِ گروه، جزئیاتِ هدیه، گزارشِ تخلف و تنظیمِ ناپدیدشدن.
///
/// هر تابع مقدارِ لازم برای فراخوانیِ API را برمی‌گرداند و خودش شبکه را صدا
/// نمی‌زند (به‌جز مواردی که فقط خواندنی‌اند)، تا منطقِ ارسال یک‌جا در
/// `ChatScreen` بماند.

/// خروجیِ سازندهٔ نظرسنجی.
class PollDraft {
  PollDraft(this.question, this.options, this.multiple);
  final String question;
  final List<String> options;
  final bool multiple;
}

Future<PollDraft?> showPollComposer(BuildContext context) {
  return showModalBottomSheet<PollDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _PollComposer(),
  );
}

class _PollComposer extends StatefulWidget {
  const _PollComposer();

  @override
  State<_PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<_PollComposer> {
  final _question = TextEditingController();
  final _options = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multiple = false;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    final filled = _options.where((c) => c.text.trim().isNotEmpty).length;
    return _question.text.trim().isNotEmpty && filled >= 2;
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart),
                const SizedBox(width: 8),
                const Text('نظرسنجیِ جدید',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _question,
              onChanged: (_) => setState(() {}),
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'پرسش',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _options[i],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'گزینهٔ ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() {
                          _options.removeAt(i).dispose();
                        }),
                      ),
                  ],
                ),
              ),
            if (_options.length < 12)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('گزینهٔ دیگر'),
                onPressed: () =>
                    setState(() => _options.add(TextEditingController())),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اجازهٔ انتخابِ چند گزینه'),
              value: _multiple,
              onChanged: (v) => setState(() => _multiple = v),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('ساختِ نظرسنجی'),
                onPressed: _valid
                    ? () => Navigator.pop(
                          context,
                          PollDraft(
                            _question.text.trim(),
                            _options
                                .map((c) => c.text.trim())
                                .where((t) => t.isNotEmpty)
                                .toList(),
                            _multiple,
                          ),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خروجیِ سازندهٔ هدیهٔ نقدی. [totalAmount] به **ریال**.
class RedPacketDraft {
  RedPacketDraft(this.totalAmount, this.count, this.mode, this.greeting);
  final int totalAmount;
  final int count;
  final String mode;
  final String? greeting;
}

Future<RedPacketDraft?> showRedPacketComposer(BuildContext context) {
  return showModalBottomSheet<RedPacketDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _RedPacketComposer(),
  );
}

class _RedPacketComposer extends StatefulWidget {
  const _RedPacketComposer();

  @override
  State<_RedPacketComposer> createState() => _RedPacketComposerState();
}

class _RedPacketComposerState extends State<_RedPacketComposer> {
  final _toman = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _greeting = TextEditingController();
  String _mode = 'equal';

  @override
  void dispose() {
    _toman.dispose();
    _count.dispose();
    _greeting.dispose();
    super.dispose();
  }

  int get _tomanValue => int.tryParse(_toman.text.trim()) ?? 0;
  int get _countValue => int.tryParse(_count.text.trim()) ?? 0;

  /// کفِ هر سهم در بک‌اند ۱۰۰۰ ریال (۱۰۰ تومان) است.
  bool get _valid =>
      _tomanValue > 0 &&
      _countValue >= 1 &&
      _countValue <= 100 &&
      (_tomanValue * 10) >= _countValue * 1000;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🧧', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                const Text('هدیهٔ نقدی',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _toman,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'مبلغِ کل (تومان)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'تعدادِ سهم (۱ تا ۱۰۰)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'equal', label: Text('مساوی')),
                ButtonSegment(value: 'random', label: Text('شانسی')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _greeting,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'پیامِ همراه (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
            if (!_valid && _toman.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'هر سهم باید حداقل ۱۰۰ تومان باشد.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.card_giftcard),
                label: const Text('ارسالِ هدیه'),
                onPressed: _valid
                    ? () => Navigator.pop(
                          context,
                          RedPacketDraft(
                            _tomanValue * 10,
                            _countValue,
                            _mode,
                            _greeting.text.trim().isEmpty
                                ? null
                                : _greeting.text.trim(),
                          ),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خروجیِ سازندهٔ رویداد.
class EventDraft {
  EventDraft(this.title, this.startsAt, this.location, this.description);
  final String title;
  final DateTime startsAt;
  final String? location;
  final String? description;
}

Future<EventDraft?> showEventComposer(BuildContext context) {
  return showModalBottomSheet<EventDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _EventComposer(),
  );
}

class _EventComposer extends StatefulWidget {
  const _EventComposer();

  @override
  State<_EventComposer> createState() => _EventComposerState();
}

class _EventComposerState extends State<_EventComposer> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _desc = TextEditingController();
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 1));

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (!mounted) return;
    setState(() {
      _startsAt = DateTime(
          d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _startsAt;
    final when = '${d.year}/${d.month}/${d.day} — '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event),
                const SizedBox(width: 8),
                const Text('رویدادِ جدید',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'عنوان',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('زمانِ شروع'),
              subtitle: Text(when),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickWhen,
            ),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'مکان (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'توضیح (اختیاری)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('ارسالِ رویداد'),
                onPressed: _title.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                          context,
                          EventDraft(
                            _title.text.trim(),
                            _startsAt,
                            _location.text.trim().isEmpty
                                ? null
                                : _location.text.trim(),
                            _desc.text.trim().isEmpty
                                ? null
                                : _desc.text.trim(),
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// انتخابِ اتاقِ مقصد برای بازارسال. `(roomId, anonymous)` را برمی‌گرداند.
Future<(String, bool)?> showForwardPicker(
  BuildContext context, {
  required List<ChatRoom> rooms,
  required String currentRoomId,
}) {
  final others = rooms.where((r) => r.id != currentRoomId).toList();
  return showModalBottomSheet<(String, bool)>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ForwardPicker(rooms: others),
  );
}

class _ForwardPicker extends StatefulWidget {
  const _ForwardPicker({required this.rooms});
  final List<ChatRoom> rooms;

  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  bool _anonymous = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.shortcut),
            title: Text('بازارسال به…'),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('بی‌نام (بدونِ نامِ فرستندهٔ اصلی)'),
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
          ),
          const Divider(height: 1),
          if (widget.rooms.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('گفتگویِ دیگری برای بازارسال نیست.'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.rooms.length,
                itemBuilder: (ctx, i) {
                  final r = widget.rooms[i];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(r.displayTitle.isNotEmpty
                          ? r.displayTitle.characters.first
                          : '؟'),
                    ),
                    title: Text(r.displayTitle),
                    subtitle: r.isGroup
                        ? Text('گروه • ${r.memberCount} عضو')
                        : null,
                    onTap: () => Navigator.pop(context, (r.id, _anonymous)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// شیتِ اعضایِ گروه با افزودن/حذف (فقط برای ادمین) و ترکِ گروه.
Future<void> showMembersSheet(
  BuildContext context, {
  required ApiClient api,
  required ChatRoom room,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) =>
        _MembersSheet(api: api, room: room, onChanged: onChanged),
  );
}

class _MembersSheet extends StatefulWidget {
  const _MembersSheet(
      {required this.api, required this.room, required this.onChanged});
  final ApiClient api;
  final ChatRoom room;
  final VoidCallback onChanged;

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  List<RoomMember>? _members;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.roomMembers(widget.room.id);
      if (!mounted) return;
      setState(() {
        _members = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _add() async {
    final earthId = await _promptEarthId(context);
    if (earthId == null || earthId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.addRoomMember(widget.room.id, earthId);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) _toast(context, 'افزودنِ عضو ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(RoomMember m) async {
    setState(() => _busy = true);
    try {
      await widget.api.removeRoomMember(widget.room.id, m.earthId);
      if (m.isMe) {
        widget.onChanged();
        if (mounted) Navigator.pop(context);
        return;
      }
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) _toast(context, 'حذفِ عضو ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.group),
            title: Text('اعضایِ ${widget.room.displayTitle}'),
            trailing: widget.room.isAdmin
                ? IconButton(
                    icon: const Icon(Icons.person_add),
                    onPressed: _busy ? null : _add,
                  )
                : null,
          ),
          const Divider(height: 1),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('خطا در دریافتِ اعضا: $_error'),
            )
          else if (_members == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _members!.length,
                itemBuilder: (ctx, i) {
                  final m = _members![i];
                  final avatar = AppConfig.absoluteMedia(m.avatarUrl);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          avatar != null ? NetworkImage(avatar) : null,
                      child: avatar == null
                          ? Text(m.displayName.characters.first)
                          : null,
                    ),
                    title: Text(m.displayName + (m.isMe ? ' (خودم)' : '')),
                    subtitle: Text(m.earthId),
                    trailing: m.isAdmin
                        ? const Chip(
                            label: Text('ادمین',
                                style: TextStyle(fontSize: 10)),
                            visualDensity: VisualDensity.compact)
                        : (widget.room.isAdmin || m.isMe)
                            ? IconButton(
                                icon: Icon(m.isMe
                                    ? Icons.logout
                                    : Icons.person_remove),
                                onPressed: _busy ? null : () => _remove(m),
                              )
                            : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// جزئیاتِ هدیهٔ نقدی (فهرستِ برداشت‌کنندگان).
Future<void> showRedPacketDetails(
  BuildContext context, {
  required ApiClient api,
  required String packetId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _RedPacketDetails(api: api, packetId: packetId),
  );
}

class _RedPacketDetails extends StatefulWidget {
  const _RedPacketDetails({required this.api, required this.packetId});
  final ApiClient api;
  final String packetId;

  @override
  State<_RedPacketDetails> createState() => _RedPacketDetailsState();
}

class _RedPacketDetailsState extends State<_RedPacketDetails> {
  RedPacketInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.redPacketInfo(widget.packetId).then((v) {
      if (mounted) setState(() => _info = v);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🧧', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                const Text('جزئیاتِ هدیهٔ نقدی',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text('خطا: $_error')
            else if (info == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text('فرستنده: ${info.senderName}'),
              Text('مبلغِ کل: ${(info.totalAmount / 10).round()} تومان'),
              Text('برداشته‌شده: ${info.claimedCount} از ${info.count}'
                  ' (${(info.claimedAmount / 10).round()} تومان)'),
              Text('حالت: ${info.mode == 'random' ? 'شانسی' : 'مساوی'}'),
              Text('وضعیت: ${_statusLabel(info.status)}'),
              const Divider(height: 20),
              if (info.claims == null || info.claims!.isEmpty)
                const Text('هنوز کسی برنداشته است.')
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: info.claims!
                        .map((c) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.redeem, size: 18),
                              title: Text(c.name),
                              trailing: Text(
                                  '${(c.amount / 10).round()} تومان'),
                            ))
                        .toList(),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'active' => 'فعال',
        'finished' => 'تمام‌شده',
        'refunded' => 'بازگردانده‌شده',
        _ => s,
      };
}

/// شیتِ گزارشِ تخلف؛ `(reason, note)` را برمی‌گرداند.
Future<(String, String?)?> showReportSheet(BuildContext context) {
  return showModalBottomSheet<(String, String?)>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _ReportSheet(),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = 'spam';
  final _note = TextEditingController();

  static const _reasons = <String, String>{
    'spam': 'هرزنامه',
    'harassment': 'آزار و اذیت',
    'scam': 'کلاهبرداری',
    'inappropriate': 'محتوایِ نامناسب',
    'other': 'دیگر',
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('گزارشِ تخلف',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final e in _reasons.entries)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: e.key,
              groupValue: _reason,
              title: Text(e.value),
              onChanged: (v) => setState(() => _reason = v!),
            ),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'توضیحِ بیشتر (اختیاری)',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.flag),
              label: const Text('ارسالِ گزارش'),
              onPressed: () => Navigator.pop(
                context,
                (
                  _reason,
                  _note.text.trim().isEmpty ? null : _note.text.trim(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// انتخابِ TTLِ پیامِ ناپدیدشونده (ثانیه)؛ `null` یعنی لغو.
Future<int?> showDisappearingPicker(BuildContext context, int current) {
  const choices = <int, String>{
    0: 'خاموش',
    3600: '۱ ساعت',
    86400: '۲۴ ساعت',
    604800: '۷ روز',
  };
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.timer),
            title: Text('پیامِ ناپدیدشونده'),
            subtitle: Text('پیام‌های جدید پس از این مدت پاک می‌شوند.'),
          ),
          const Divider(height: 1),
          for (final e in choices.entries)
            ListTile(
              title: Text(e.value),
              trailing: current == e.key ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    ),
  );
}

/// انتخابِ مدتِ بی‌صداکردن؛ خروجی دقیقه است و `-1` یعنی «همیشه».
Future<int?> showMutePicker(BuildContext context) {
  const choices = <int, String>{
    60: '۱ ساعت',
    480: '۸ ساعت',
    1440: '۲۴ ساعت',
    10080: '۱ هفته',
    -1: 'همیشه',
  };
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.notifications_off),
            title: Text('بی‌صداکردنِ گفتگو'),
          ),
          const Divider(height: 1),
          for (final e in choices.entries)
            ListTile(
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    ),
  );
}

/// انتخابِ زبانِ مقصدِ ترجمه.
Future<String?> showLanguagePicker(BuildContext context) {
  const langs = <String, String>{
    'fa': 'فارسی',
    'en': 'انگلیسی',
    'ar': 'عربی',
    'tr': 'ترکی',
    'ru': 'روسی',
    'zh': 'چینی',
    'fr': 'فرانسوی',
    'de': 'آلمانی',
  };
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.translate),
            title: Text('ترجمه به…'),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: langs.entries
                  .map((e) => ListTile(
                        title: Text(e.value),
                        onTap: () => Navigator.pop(ctx, e.key),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// گرفتنِ Earth ID از کاربر (برای افزودنِ عضو یا اشتراکِ مخاطب).
Future<String?> promptEarthId(BuildContext context,
        {String title = 'Earth ID'}) =>
    _promptEarthId(context, title: title);

Future<String?> _promptEarthId(BuildContext context,
    {String title = 'Earth ID'}) async {
  final ctrl = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          hintText: 'DLX-XXXXXXXX',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('تأیید'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return value;
}

/// گرفتنِ مختصات برای ارسالِ موقعیت: با «موقعیتِ فعلیِ من» از GPS پر می‌شود و
/// در صورتِ نبودِ مجوز/GPS ورودِ دستی هم ممکن است. [fix] تأمین‌کنندهٔ GPS است و
/// در صورتِ خطا `null` برمی‌گرداند (پیامِ خطا را خودِ فراخوان نشان می‌دهد).
Future<(double, double, String?)?> showLocationComposer(
  BuildContext context, {
  required Future<(double, double)?> Function() fix,
}) {
  return showDialog<(double, double, String?)>(
    context: context,
    builder: (ctx) => _LocationComposer(fix: fix),
  );
}

class _LocationComposer extends StatefulWidget {
  const _LocationComposer({required this.fix});
  final Future<(double, double)?> Function() fix;

  @override
  State<_LocationComposer> createState() => _LocationComposerState();
}

class _LocationComposerState extends State<_LocationComposer> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _label = TextEditingController();
  bool _locating = false;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    final f = await widget.fix();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (f != null) {
        _lat.text = f.$1.toStringAsFixed(6);
        _lng.text = f.$2.toStringAsFixed(6);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ارسالِ موقعیت'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _locating ? null : _useGps,
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(_locating ? 'در حالِ مکان‌یابی…' : 'موقعیتِ فعلیِ من'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lat,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: const InputDecoration(
                labelText: 'عرضِ جغرافیایی (lat)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lng,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: const InputDecoration(
                labelText: 'طولِ جغرافیایی (lng)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
                labelText: 'برچسب (اختیاری)', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('لغو')),
        FilledButton(
          onPressed: () {
            final lat = double.tryParse(_lat.text.trim());
            final lng = double.tryParse(_lng.text.trim());
            if (lat == null || lng == null) return;
            Navigator.pop(context, (
              lat,
              lng,
              _label.text.trim().isEmpty ? null : _label.text.trim()
            ));
          },
          child: const Text('ارسال'),
        ),
      ],
    );
  }
}

/// مدتِ اشتراکِ موقعیتِ زنده (دقیقه). سرور حداکثر ۲۴ ساعت را می‌پذیرد.
Future<int?> showLiveLocationDuration(BuildContext context) {
  const options = <int, String>{
    15: '۱۵ دقیقه',
    60: '۱ ساعت',
    480: '۸ ساعت',
    1440: '۲۴ ساعت',
  };
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.podcasts),
            title: Text('اشتراکِ موقعیتِ زنده'),
            subtitle: Text(
                'موقعیتِ تو هر ۳۰ ثانیه به‌روز می‌شود و در پایانِ مدت خودکار متوقف می‌شود.'),
          ),
          const Divider(height: 1),
          for (final e in options.entries)
            ListTile(
              title: Text(e.value),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    ),
  );
}

/// کپیِ متن در کلیپ‌بورد + پیامِ تأیید.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) _toast(context, 'در کلیپ‌بورد کپی شد.');
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
