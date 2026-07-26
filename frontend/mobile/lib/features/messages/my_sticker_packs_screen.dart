import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// بسته‌های استیکرِ ساختهٔ خودم — `GET /stickers/packs/mine`،
/// `POST /stickers/packs` و `POST /stickers/packs/{id}/stickers`.
class MyStickerPacksScreen extends StatefulWidget {
  const MyStickerPacksScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<MyStickerPacksScreen> createState() => _MyStickerPacksScreenState();
}

class _MyStickerPacksScreenState extends State<MyStickerPacksScreen> {
  List<StickerPack>? _packs;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final packs = await widget.api.myStickerPacks();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('بارگذاریِ بسته‌ها ممکن نشد.\n{0}', [e]));
    }
  }

  Future<void> _create() async {
    final result = await showDialog<(String, String, bool)>(
      context: context,
      builder: (_) => const _NewPackDialog(),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.createStickerPack(
        title: result.$1,
        description: result.$2,
        isPublic: result.$3,
      );
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('بسته ساخته شد.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('ساختِ بسته ناموفق بود: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(StickerPack p) async {
    final result = await showDialog<(String, String, bool)>(
      context: context,
      builder: (_) => _NewPackDialog(pack: p),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.updateStickerPack(
        p.id,
        title: result.$1,
        description: result.$2,
        isPublic: result.$3,
      );
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('بسته به‌روز شد.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('ویرایش ناموفق بود: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(StickerPack p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذفِ بسته')),
        content: Text(
          tr('«{0}» با همهٔ استیکرهایش حذف می‌شود. این کار برگشت‌پذیر نیست.', [p.title]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('حذف'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.deleteStickerPack(p.id);
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('بسته حذف شد.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('حذف ناموفق بود: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPack(StickerPack p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PackEditorScreen(api: widget.api, packId: p.id),
      ),
    );
    // شمارِ استیکرها ممکن است عوض شده باشد.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final packs = _packs;
    return Scaffold(
      appBar: AppBar(title: Text(tr('بسته‌های من'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.add),
        label: Text(tr('بستهٔ جدید')),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : packs == null
              ? const Center(child: CircularProgressIndicator())
              : packs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          tr('هنوز بسته‌ای نساخته‌اید. با دکمهٔ پایین شروع کنید.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: packs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final p = packs[i];
                          return ListTile(
                            leading: SizedBox(
                                width: 40, height: 40, child: _cover(p)),
                            title: Text(p.title),
                            subtitle: Text(
                              tr('{0} استیکر • {1}', [p.stickerCount, p.isPublic ? tr('عمومی') : tr('خصوصی')]),
                            ),
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (v) =>
                                  v == 'edit' ? _edit(p) : _delete(p),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'edit', child: Text(tr('ویرایش'))),
                                PopupMenuItem(
                                    value: 'delete', child: Text(tr('حذفِ بسته'))),
                              ],
                            ),
                            onTap: () => _openPack(p),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _cover(StickerPack p) {
    final url = AppConfig.absoluteMedia(p.coverUrl);
    if (url == null) return const Icon(Icons.emoji_emotions_outlined);
    return Image.network(url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions_outlined));
  }
}

/// افزودنِ استیکر به یک بستهٔ خودم.
class _PackEditorScreen extends StatefulWidget {
  const _PackEditorScreen({required this.api, required this.packId});

  final ApiClient api;
  final String packId;

  @override
  State<_PackEditorScreen> createState() => _PackEditorScreenState();
}

class _PackEditorScreenState extends State<_PackEditorScreen> {
  StickerPack? _pack;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pack = await widget.api.stickerPack(widget.packId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('بارگذاریِ بسته ممکن نشد.\n{0}', [e]));
    }
  }

  Future<void> _addSticker() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final emoji = await showDialog<String>(
      context: context,
      builder: (_) => const _EmojiTagDialog(),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.addSticker(
        packId: widget.packId,
        filePath: picked.path,
        emojiTag: emoji,
      );
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('استیکر اضافه شد.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('افزودن ناموفق بود: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSticker(StickerItem s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذفِ استیکر')),
        content: Text(tr('این استیکر از بسته حذف شود؟')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('حذف'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.api.deleteSticker(s.id);
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('استیکر حذف شد.'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('حذف ناموفق بود: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(title: Text(pack?.title ?? tr('بسته'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addSticker,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(tr('افزودنِ استیکر')),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : pack == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (pack.stickers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Text(
                          tr('برای حذفِ یک استیکر، روی آن نگه دارید.'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Expanded(
                      child: pack.stickers.isEmpty
                          ? Center(
                              child: Text(
                                  tr('این بسته هنوز استیکری ندارد.')))
                          : GridView.builder(
                              padding: const EdgeInsets.all(10),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                              itemCount: pack.stickers.length,
                              itemBuilder: (ctx, i) {
                                final s = pack.stickers[i];
                                final url = AppConfig.absoluteMedia(s.mediaUrl);
                                const fallback = Center(
                                    child: Text('🙂',
                                        style: TextStyle(fontSize: 28)));
                                // نگه‌داشتن = حذف؛ گرید جای دکمهٔ جدا ندارد.
                                return InkWell(
                                  onLongPress:
                                      _busy ? null : () => _deleteSticker(s),
                                  child: url == null
                                      ? fallback
                                      : Image.network(url,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              fallback),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

/// ساخت یا ویرایشِ بسته — با [pack] غیرِ null حالتِ ویرایش می‌شود.
class _NewPackDialog extends StatefulWidget {
  const _NewPackDialog({this.pack});

  final StickerPack? pack;

  @override
  State<_NewPackDialog> createState() => _NewPackDialogState();
}

class _NewPackDialogState extends State<_NewPackDialog> {
  late final _title = TextEditingController(text: widget.pack?.title ?? '');
  late final _desc =
      TextEditingController(text: widget.pack?.description ?? '');
  late bool _public = widget.pack?.isPublic ?? false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.pack != null;
    return AlertDialog(
      title: Text(editing ? tr('ویرایشِ بسته') : tr('بستهٔ استیکرِ جدید')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(labelText: tr('عنوان')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            decoration: InputDecoration(labelText: tr('توضیح (اختیاری)')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('عمومی')),
            subtitle: Text(tr('بقیه بتوانند پیدا و نصب کنند')),
            value: _public,
            onChanged: (v) => setState(() => _public = v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('انصراف'))),
        FilledButton(
          onPressed: () {
            final t = _title.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, (t, _desc.text.trim(), _public));
          },
          child: Text(editing ? tr('ذخیره') : tr('ساخت')),
        ),
      ],
    );
  }
}

class _EmojiTagDialog extends StatelessWidget {
  const _EmojiTagDialog();

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    return AlertDialog(
      title: Text(tr('برچسبِ ایموجی')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: tr('مثلاً 😀 (اختیاری)')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('بدونِ برچسب')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: Text(tr('تأیید')),
        ),
      ],
    );
  }
}
