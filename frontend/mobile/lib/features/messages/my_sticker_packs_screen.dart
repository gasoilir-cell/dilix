import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';

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
      setState(() => _error = 'بارگذاریِ بسته‌ها ممکن نشد.\n$e');
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
      messenger.showSnackBar(const SnackBar(content: Text('بسته ساخته شد.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('ساختِ بسته ناموفق بود: $e')));
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
      appBar: AppBar(title: const Text('بسته‌های من')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.add),
        label: const Text('بستهٔ جدید'),
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
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'هنوز بسته‌ای نساخته‌اید. با دکمهٔ پایین شروع کنید.',
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
                              '${p.stickerCount} استیکر • '
                              '${p.isPublic ? 'عمومی' : 'خصوصی'}',
                            ),
                            trailing: const Icon(Icons.chevron_left),
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
      setState(() => _error = 'بارگذاریِ بسته ممکن نشد.\n$e');
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
      messenger.showSnackBar(const SnackBar(content: Text('استیکر اضافه شد.')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('افزودن ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(title: Text(pack?.title ?? 'بسته')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addSticker,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('افزودنِ استیکر'),
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
                    Expanded(
                      child: pack.stickers.isEmpty
                          ? const Center(
                              child: Text('این بسته هنوز استیکری ندارد.'))
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
                                final url = AppConfig.absoluteMedia(
                                    pack.stickers[i].mediaUrl);
                                if (url == null) {
                                  return const Center(
                                      child: Text('🙂',
                                          style: TextStyle(fontSize: 28)));
                                }
                                return Image.network(url,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Center(
                                        child: Text('🙂',
                                            style: TextStyle(fontSize: 28))));
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _NewPackDialog extends StatefulWidget {
  const _NewPackDialog();

  @override
  State<_NewPackDialog> createState() => _NewPackDialogState();
}

class _NewPackDialogState extends State<_NewPackDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _public = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('بستهٔ استیکرِ جدید'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'عنوان'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'توضیح (اختیاری)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('عمومی'),
            subtitle: const Text('بقیه بتوانند پیدا و نصب کنند'),
            value: _public,
            onChanged: (v) => setState(() => _public = v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف')),
        FilledButton(
          onPressed: () {
            final t = _title.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, (t, _desc.text.trim(), _public));
          },
          child: const Text('ساخت'),
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
      title: const Text('برچسبِ ایموجی'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'مثلاً 😀 (اختیاری)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('بدونِ برچسب'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('تأیید'),
        ),
      ],
    );
  }
}
