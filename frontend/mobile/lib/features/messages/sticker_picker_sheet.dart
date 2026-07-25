import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import 'my_sticker_packs_screen.dart';

/// انتخابگرِ استیکر. شناسهٔ استیکرِ انتخاب‌شده را برمی‌گرداند تا `ChatScreen`
/// خودش `sendSticker` را صدا بزند (منطقِ ارسال یک‌جا می‌ماند).
Future<String?> showStickerPicker(BuildContext context, {required ApiClient api}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _StickerPicker(api: api),
  );
}

class _StickerPicker extends StatefulWidget {
  const _StickerPicker({required this.api});
  final ApiClient api;

  @override
  State<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<_StickerPicker> {
  /// `null` = زبانهٔ ستاره‌دارها؛ در غیرِ این‌صورت شناسهٔ بستهٔ انتخاب‌شده.
  String? _packId;
  bool _discover = false;

  List<StickerPack>? _packs;
  List<StickerItem>? _starred;
  final _stickersByPack = <String, List<StickerItem>>{};

  List<StickerPack>? _public;
  final _query = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final packs = await widget.api.installedStickerPacks();
      final starred = await widget.api.starredStickers();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _starred = starred;
        _error = null;
        // اگر ستاره‌داری نیست، مستقیم اولین بسته را باز کن.
        if (starred.isEmpty && packs.isNotEmpty) _packId = packs.first.id;
      });
      if (_packId != null) await _loadPack(_packId!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'دریافتِ استیکرها ناموفق بود: $e');
    }
  }

  Future<void> _loadPack(String packId) async {
    if (_stickersByPack.containsKey(packId)) return;
    try {
      final pack = await widget.api.stickerPack(packId);
      if (!mounted) return;
      setState(() => _stickersByPack[packId] = pack.stickers);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'بازکردنِ بسته ناموفق بود: $e');
    }
  }

  Future<void> _searchPublic() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final list = await widget.api.publicStickerPacks(q: _query.text.trim());
      if (!mounted) return;
      setState(() {
        _public = list;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'جستجویِ بسته‌ها ناموفق بود: $e';
      });
    }
  }

  /// استودیوی بسته‌های خودم. پس از بازگشت فهرستِ نصب‌شده‌ها را تازه می‌کنیم
  /// چون ممکن است بستهٔ تازه‌ای ساخته و پر شده باشد.
  Future<void> _openMyPacks() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyStickerPacksScreen(api: widget.api),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _install(StickerPack pack) async {
    setState(() => _busy = true);
    try {
      if (pack.installed) {
        await widget.api.uninstallStickerPack(pack.id);
      } else {
        await widget.api.installStickerPack(pack.id);
      }
      _stickersByPack.remove(pack.id);
      final packs = await widget.api.installedStickerPacks();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        if (_packId != null && !packs.any((p) => p.id == _packId)) _packId = null;
        _busy = false;
      });
      // وضعیتِ `is_installed` در فهرستِ عمومی از سرور دوباره خوانده می‌شود.
      await _searchPublic();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تغییرِ وضعیتِ نصب ناموفق بود: $e';
      });
    }
  }

  Future<void> _toggleStar(StickerItem s) async {
    try {
      await widget.api.setStickerStarred(s.id, !s.starred);
      final starred = await widget.api.starredStickers();
      if (!mounted) return;
      setState(() {
        _starred = starred;
        final list = _stickersByPack[s.packId];
        if (list != null) {
          final i = list.indexWhere((e) => e.id == s.id);
          if (i >= 0) list[i] = s.copyWith(starred: !s.starred);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'ستاره‌دارکردن ناموفق بود: $e');
    }
  }

  List<StickerItem> get _visible => _packId == null
      ? (_starred ?? const [])
      : (_stickersByPack[_packId] ?? const []);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: Text(_discover ? 'بسته‌های عمومی' : 'استیکرها'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'بسته‌های من',
                    icon: const Icon(Icons.brush_outlined),
                    onPressed: _openMyPacks,
                  ),
                  IconButton(
                    tooltip: _discover ? 'استیکرهای من' : 'کشفِ بسته‌ها',
                    icon:
                        Icon(_discover ? Icons.close : Icons.add_circle_outline),
                    onPressed: () {
                      setState(() => _discover = !_discover);
                      if (_discover && _public == null) _searchPublic();
                    },
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const Divider(height: 1),
            Expanded(child: _discover ? _discoverBody() : _myBody()),
          ],
        ),
      ),
    );
  }

  Widget _myBody() {
    if (_packs == null && _starred == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final packs = _packs ?? const <StickerPack>[];
    if (packs.isEmpty && (_starred ?? const []).isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('هنوز بستهٔ استیکری نصب نکرده‌ای.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                setState(() => _discover = true);
                if (_public == null) _searchPublic();
              },
              icon: const Icon(Icons.search),
              label: const Text('دیدنِ بسته‌های عمومی'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(child: _grid()),
        const Divider(height: 1),
        SizedBox(
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              _packTab(
                selected: _packId == null,
                onTap: () => setState(() => _packId = null),
                child: const Icon(Icons.star),
              ),
              for (final p in packs)
                _packTab(
                  selected: _packId == p.id,
                  onTap: () {
                    setState(() => _packId = p.id);
                    _loadPack(p.id);
                  },
                  child: _packCover(p),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _packTab({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 46,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _packCover(StickerPack p) {
    final url = AppConfig.absoluteMedia(p.coverUrl);
    if (url == null) {
      return Text(
        p.title.isNotEmpty ? p.title.characters.first : '؟',
        style: const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    return SizedBox(
      width: 30,
      height: 30,
      child: Image.network(url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, size: 20)),
    );
  }

  Widget _grid() {
    final items = _visible;
    if (_packId != null && !_stickersByPack.containsKey(_packId)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Text(_packId == null
            ? 'استیکرِ ستاره‌داری نداری. روی هر استیکر نگه‌دار تا ستاره شود.'
            : 'این بسته خالی است.'),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final s = items[i];
        final url = AppConfig.absoluteMedia(s.mediaUrl);
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.pop(context, s.id),
          onLongPress: () => _toggleStar(s),
          child: Stack(
            children: [
              Positioned.fill(
                child: url == null
                    ? const Center(child: Text('🙂', style: TextStyle(fontSize: 28)))
                    : Image.network(url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Text('🙂', style: TextStyle(fontSize: 28)))),
              ),
              if (s.starred)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(Icons.star, size: 12, color: Colors.amber),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _discoverBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchPublic(),
            decoration: InputDecoration(
              hintText: 'جستجویِ بستهٔ استیکر…',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchPublic,
              ),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: _publicList()),
      ],
    );
  }

  Widget _publicList() {
    final list = _public;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return const Center(child: Text('بستهٔ عمومی‌ای پیدا نشد.'));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = list[i];
        return ListTile(
          leading: SizedBox(width: 40, height: 40, child: _packCover(p)),
          title: Text(p.title),
          subtitle: Text(
            '${p.stickerCount} استیکر • ${p.installCount} نصب'
            '${p.ownerName != null ? ' • ${p.ownerName}' : ''}',
          ),
          trailing: p.installed
              ? IconButton(
                  tooltip: 'حذفِ بسته',
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: _busy ? null : () => _install(p),
                )
              : IconButton(
                  tooltip: 'نصبِ بسته',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: _busy ? null : () => _install(p),
                ),
        );
      },
    );
  }
}
