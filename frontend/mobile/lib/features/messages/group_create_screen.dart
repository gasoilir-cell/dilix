import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../models/models.dart';
import 'chat_sheets.dart';

/// ساختِ گروهِ گفتگو: نامِ گروه + فهرستِ اعضا با Earth ID.
///
/// اعضا از دو راه اضافه می‌شوند: انتخاب از میانِ گفتگوهای دوطرفهٔ موجود، یا
/// واردکردنِ دستیِ Earth ID. با موفقیت، اتاقِ ساخته‌شده به فراخوان برگردانده
/// می‌شود تا مستقیم باز شود.
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _selected = <String, String>{}; // earthId → نامِ نمایشی
  List<ChatRoom>? _directRooms;
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  ApiClient get _api => ApiScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadContacts();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final rooms = await _api.listRooms();
      if (!mounted) return;
      setState(() => _directRooms = rooms
          .where((r) => !r.isGroup && (r.partnerEarthId ?? '').isNotEmpty)
          .toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _directRooms = const []);
    }
  }

  Future<void> _addManual() async {
    final id = await promptEarthId(context, title: 'افزودنِ عضو با Earth ID');
    if (id == null || id.isEmpty) return;
    setState(() => _selected[id] = id);
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'نامِ گروه حداقل ۲ نویسه باشد.');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'حداقل یک عضو انتخاب کن.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room =
          await _api.createGroup(name, memberEarthIds: _selected.keys.toList());
      if (!mounted) return;
      Navigator.pop(context, room);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'ساختِ گروه ناموفق بود: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _directRooms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('گروهِ جدید'),
        actions: [
          IconButton(
            tooltip: 'افزودن با Earth ID',
            icon: const Icon(Icons.person_add_alt),
            onPressed: _busy ? null : _addManual,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'نامِ گروه',
              prefixIcon: Icon(Icons.groups),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_selected.isNotEmpty) ...[
            Text('اعضایِ انتخاب‌شده (${_selected.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selected.entries
                  .map((e) => Chip(
                        label: Text(e.value),
                        onDeleted: _busy
                            ? null
                            : () => setState(() => _selected.remove(e.key)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          Text('از گفتگوهای موجود',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          if (rooms == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rooms.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'گفتگویِ دوطرفه‌ای نداری. اعضا را با Earth ID اضافه کن.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            for (final r in rooms) _contactTile(r),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('ساختِ گروه'),
          ),
        ],
      ),
    );
  }

  Widget _contactTile(ChatRoom r) {
    final id = r.partnerEarthId!;
    final avatar = r.partnerAvatar;
    final checked = _selected.containsKey(id);
    return CheckboxListTile(
      value: checked,
      onChanged: _busy
          ? null
          : (v) => setState(() {
                if (v == true) {
                  _selected[id] = r.displayTitle.isEmpty ? id : r.displayTitle;
                } else {
                  _selected.remove(id);
                }
              }),
      secondary: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage:
            (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
        child: (avatar == null || avatar.isEmpty)
            ? Text(r.displayTitle.isNotEmpty
                ? r.displayTitle.characters.first
                : '؟')
            : null,
      ),
      title: Text(r.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(id, style: const TextStyle(fontSize: 11)),
    );
  }
}
