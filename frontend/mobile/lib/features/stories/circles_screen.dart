import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';

/// نامِ سه حلقهٔ مخاطب؛ همان مقادیرِ مجازِ `audience` در ساختِ داستان.
const _circles = <String, String>{
  'friends': 'دوستان',
  'family': 'خانواده',
  'colleagues': 'همکاران',
};

/// مدیریتِ حلقه‌های مخاطب: تعیینِ اینکه داستانِ با مخاطبِ «خانواده» را چه کسانی
/// می‌بینند. معادلِ بخشِ circles در وب.
class CirclesScreen extends StatefulWidget {
  const CirclesScreen({super.key});

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> {
  ContactCircles? _circlesData;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _circlesData == null) _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiScope.of(context).storyCircles();
      if (!mounted) return;
      setState(() {
        _circlesData = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'بارگذاریِ حلقه‌ها ممکن نشد: $e';
      });
    }
  }

  Future<void> _add(String circle) async {
    final earthId = await showDialog<String>(
      context: context,
      builder: (_) => const _AddMemberDialog(),
    );
    if (earthId == null || earthId.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiScope.of(context).addToCircle(circle, earthId);
      if (!mounted) return;
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _remove(String circle, CircleMember m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiScope.of(context).removeFromCircle(circle, m.earthId);
      if (!mounted) return;
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حلقه‌های مخاطب')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  Text(
                    'داستانی که مخاطبش «دوستان»، «خانواده» یا «همکاران» باشد، فقط برای اعضای همان حلقه دیده می‌شود.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final e in _circles.entries) _circleCard(e.key, e.value),
                ],
              ),
            ),
    );
  }

  Widget _circleCard(String key, String label) {
    final members = _circlesData?.of(key) ?? const <CircleMember>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$label (${members.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: () => _add(key),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('افزودن'),
                ),
              ],
            ),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('هنوز کسی در این حلقه نیست.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            else
              for (final m in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _avatar(m),
                  title: Text(m.name.isEmpty ? m.earthId : m.name),
                  subtitle: Text(m.earthId),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'حذف از حلقه',
                    onPressed: () => _remove(key, m),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(CircleMember m) {
    final url = AppConfig.absoluteMedia(m.avatarUrl);
    return CircleAvatar(
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null ? const Icon(Icons.person_outline) : null,
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('افزودن به حلقه'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Earth ID',
          hintText: 'مثلاً EID-XXXX',
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim().toUpperCase()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_ctrl.text.trim().toUpperCase()),
          child: const Text('افزودن'),
        ),
      ],
    );
  }
}
