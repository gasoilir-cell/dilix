import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// هایلایت‌های پروفایل — مجموعه‌های ماندگارِ داستان.
///
/// [isMe] از پاسخِ سرور مستقل است تا صفحه بدونِ رفت‌وبرگشتِ اضافه بداند دکمهٔ
/// «هایلایتِ جدید» را نشان بدهد یا نه؛ اقداماتِ ویرایشی همچنان به `isMine` هر
/// هایلایت وابسته‌اند (سرور هم مالکیت را دوباره بررسی می‌کند).
class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key, required this.earthId, this.isMe = false});

  final String earthId;
  final bool isMe;

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  List<StoryHighlight> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _items.isEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).highlights(widget.earthId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('بارگذاریِ هایلایت‌ها ممکن نشد: {0}', [e]);
      });
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateHighlightSheet(earthId: widget.earthId),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _open(StoryHighlight h) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => HighlightDetailScreen(highlightId: h.id)),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _rename(StoryHighlight h) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TitleDialog(initial: h.title),
    );
    if (title == null || title.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiScope.of(context).updateHighlight(h.id, title: title);
      if (!mounted) return;
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(StoryHighlight h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذفِ هایلایت')),
        content: Text(tr('«{0}» حذف شود؟', [h.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('حذف')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiScope.of(context).deleteHighlight(h.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('هایلایت‌ها'))),
      floatingActionButton: widget.isMe
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(tr('هایلایتِ جدید')),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Text(_error!, textAlign: TextAlign.center)),
                    ])
                  : _items.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Center(child: Text(tr('هنوز هایلایتی ساخته نشده است.'))),
                        ])
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _tile(_items[i]),
                        ),
            ),
    );
  }

  Widget _tile(StoryHighlight h) {
    final cover = AppConfig.absoluteMedia(h.coverUrl);
    return GestureDetector(
      onTap: () => _open(h),
      onLongPress: h.isMine ? () => _menu(h) : null,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                image: cover != null
                    ? DecorationImage(
                        image: NetworkImage(cover), fit: BoxFit.cover)
                    : null,
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 2),
              ),
              child: cover == null
                  ? const Icon(Icons.auto_awesome_motion_outlined)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(h.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
          Text('${h.itemCount}',
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  void _menu(StoryHighlight h) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('تغییرِ عنوان')),
              onTap: () {
                Navigator.of(ctx).pop();
                _rename(h);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('حذفِ هایلایت')),
              onTap: () {
                Navigator.of(ctx).pop();
                _delete(h);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// نمایشِ آیتم‌های یک هایلایت + حذفِ آیتم و افزودنِ داستانِ تازه (برای مالک).
class HighlightDetailScreen extends StatefulWidget {
  const HighlightDetailScreen({super.key, required this.highlightId});

  final String highlightId;

  @override
  State<HighlightDetailScreen> createState() => _HighlightDetailScreenState();
}

class _HighlightDetailScreenState extends State<HighlightDetailScreen> {
  HighlightDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _detail == null) _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiScope.of(context).highlight(widget.highlightId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('بارگذاری ممکن نشد: {0}', [e]);
      });
    }
  }

  Future<void> _addItems() async {
    final d = _detail;
    if (d == null) return;
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickStoriesSheet(earthId: d.ownerEarthId),
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ApiScope.of(context).addHighlightItems(d.id, ids);
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _changed = true;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removeItem(HighlightItem it) async {
    final d = _detail;
    if (d == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiScope.of(context).removeHighlightItem(d.id, it.id);
      if (!mounted) return;
      _changed = true;
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(d?.title ?? tr('هایلایت')),
          actions: [
            if (d?.isMine ?? false)
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: tr('افزودنِ داستان'),
                onPressed: _addItems,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : d == null || d.items.isEmpty
                    ? Center(child: Text(tr('این هایلایت خالی است.')))
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.6,
                        ),
                        itemCount: d.items.length,
                        itemBuilder: (_, i) => _itemTile(d, d.items[i]),
                      ),
      ),
    );
  }

  Widget _itemTile(HighlightDetail d, HighlightItem it) {
    final url = AppConfig.absoluteMedia(it.mediaUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url != null && it.mediaType == 'image'
              ? Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black12))
              : Container(
                  color: Colors.black87,
                  child: const Icon(Icons.play_circle_outline,
                      color: Colors.white70),
                ),
        ),
        if (d.isMine)
          Positioned(
            top: 0,
            left: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black45),
              tooltip: tr('حذف از هایلایت'),
              onPressed: () => _removeItem(it),
            ),
          ),
      ],
    );
  }
}

// ─────────────── شیت‌ها و دیالوگ‌ها ───────────────

/// انتخابِ داستان‌های خودم برای افزودن (به هایلایتِ جدید یا موجود).
class _PickStoriesSheet extends StatefulWidget {
  const _PickStoriesSheet({required this.earthId});

  final String earthId;

  @override
  State<_PickStoriesSheet> createState() => _PickStoriesSheetState();
}

class _PickStoriesSheetState extends State<_PickStoriesSheet> {
  List<Story> _stories = const [];
  final _selected = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _stories.isEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).userStories(widget.earthId);
      if (!mounted) return;
      setState(() {
        _stories = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('بارگذاریِ داستان‌ها ممکن نشد: {0}', [e]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Text(tr('انتخابِ داستان'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : _stories.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                tr('داستانِ فعالی نداری. هایلایت فقط از داستان‌های موجود ساخته می‌شود.'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : GridView.builder(
                            controller: controller,
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: 0.6,
                            ),
                            itemCount: _stories.length,
                            itemBuilder: (_, i) => _tile(_stories[i]),
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                child: Text(tr('افزودن ({0})', [_selected.length])),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Story s) {
    final url = AppConfig.absoluteMedia(s.mediaUrl);
    final on = _selected.contains(s.id);
    return GestureDetector(
      onTap: () => setState(
          () => on ? _selected.remove(s.id) : _selected.add(s.id)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: url != null && s.mediaType == 'image'
                ? Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Colors.black12))
                : Container(
                    color: Colors.black87,
                    child: const Icon(Icons.play_circle_outline,
                        color: Colors.white70),
                  ),
          ),
          if (on)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
              ),
              child: const Icon(Icons.check_circle, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

/// ساختِ هایلایتِ جدید: عنوان + انتخابِ داستان‌ها در یک شیت.
class _CreateHighlightSheet extends StatefulWidget {
  const _CreateHighlightSheet({required this.earthId});

  final String earthId;

  @override
  State<_CreateHighlightSheet> createState() => _CreateHighlightSheetState();
}

class _CreateHighlightSheetState extends State<_CreateHighlightSheet> {
  final _titleCtrl = TextEditingController();
  List<String> _storyIds = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickStoriesSheet(earthId: widget.earthId),
    );
    if (ids != null && mounted) setState(() => _storyIds = ids);
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('عنوان را وارد کنید.'));
      return;
    }
    if (_storyIds.isEmpty) {
      setState(() => _error = tr('حداقل یک داستان انتخاب کنید.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context)
          .createHighlight(title: title, storyIds: _storyIds);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('هایلایتِ جدید'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            maxLength: 60,
            decoration: InputDecoration(labelText: tr('عنوان')),
          ),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_storyIds.isEmpty
                ? tr('انتخابِ داستان‌ها')
                : tr('{0} داستان انتخاب شد', [_storyIds.length])),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('ساختن')),
          ),
        ],
      ),
    );
  }
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({required this.initial});

  final String initial;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('تغییرِ عنوان')),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: tr('عنوان')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('انصراف')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: Text(tr('ذخیره')),
        ),
      ],
    );
  }
}

/// شیتِ «افزودن به هایلایت» از داخلِ نمایش‌گرِ داستان: یا یکی از هایلایت‌های
/// موجود انتخاب می‌شود یا هایلایتِ تازه‌ای با همان داستان ساخته می‌شود.
Future<bool> showAddToHighlightSheet(
  BuildContext context, {
  required String earthId,
  required String storyId,
}) async {
  final api = ApiScope.of(context);
  List<StoryHighlight> existing = const [];
  try {
    existing = await api.highlights(earthId);
  } catch (_) {}
  if (!context.mounted) return false;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(tr('هایلایتِ جدید')),
            onTap: () async {
              final title = await showDialog<String>(
                context: ctx,
                builder: (_) => const _TitleDialog(initial: ''),
              );
              if (title == null || title.isEmpty || !ctx.mounted) return;
              try {
                await api.createHighlight(title: title, storyIds: [storyId]);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } catch (_) {
                if (ctx.mounted) Navigator.of(ctx).pop(false);
              }
            },
          ),
          for (final h in existing.where((e) => e.isMine))
            ListTile(
              leading: const Icon(Icons.auto_awesome_motion_outlined),
              title: Text(h.title),
              subtitle: Text(tr('{0} آیتم', [h.itemCount])),
              onTap: () async {
                try {
                  await api.addHighlightItems(h.id, [storyId]);
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (_) {
                  if (ctx.mounted) Navigator.of(ctx).pop(false);
                }
              },
            ),
        ],
      ),
    ),
  );
  return ok ?? false;
}
