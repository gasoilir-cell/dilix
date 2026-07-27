import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';
import '../messages/my_sticker_packs_screen.dart';

/// بازارِ استیکر (فاز ۵) — ویترین، خرید از کیفِ پول، خریدها و فروشِ من.
/// معادلِ صفحهٔ وبِ `/stickers` روی `/api/v1/stickers/{market,purchases,sales}`.
class StickerMarketScreen extends StatefulWidget {
  const StickerMarketScreen({super.key});

  @override
  State<StickerMarketScreen> createState() => _StickerMarketScreenState();
}

enum _Tab { market, bought, sales }

class _StickerMarketScreenState extends State<StickerMarketScreen> {
  final _search = TextEditingController();

  _Tab _tab = _Tab.market;
  String _kind = 'all';

  List<StickerPack> _market = const [];
  List<StickerPurchase> _bought = const [];
  StickerSales? _sales;

  bool _loading = true;
  String? _busyId;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      switch (_tab) {
        case _Tab.market:
          final rows = await api.stickerMarket(q: _search.text.trim(), kind: _kind);
          if (mounted) setState(() => _market = rows);
        case _Tab.bought:
          final rows = await api.stickerPurchases();
          if (mounted) setState(() => _bought = rows);
        case _Tab.sales:
          final s = await api.stickerSales();
          if (mounted) setState(() => _sales = s);
      }
    } catch (e) {
      if (mounted) setState(() => _error = tr('بارگذاری ممکن نشد. ابتدا وارد شوید.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _buy(StickerPack p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('خریدِ بسته')),
        content: Text(tr('«{0}» به مبلغِ {1} تومان از کیفِ پول خریده و نصب شود؟',
            [p.title, (p.price / 10).round()])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('انصراف'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('خرید'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = p.id);
    try {
      await ApiScope.of(context).purchaseStickerPack(p.id);
      _snack(tr('خرید انجام شد و بسته نصب شد.'));
      await _load();
    } catch (e) {
      _snack(tr('خرید ناموفق بود. موجودیِ کیفِ پول را بررسی کنید.'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _toggleInstall(StickerPack p) async {
    setState(() => _busyId = p.id);
    try {
      final api = ApiScope.of(context);
      if (p.installed) {
        await api.uninstallStickerPack(p.id);
        _snack(tr('بسته حذف شد.'));
      } else {
        await api.installStickerPack(p.id);
        _snack(tr('بسته نصب شد.'));
      }
      await _load();
    } catch (e) {
      _snack(tr('عملیات ناموفق بود.'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('بازارِ استیکر')),
        actions: [
          IconButton(
            tooltip: tr('بسته‌های من'),
            icon: const Icon(Icons.folder_special_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MyStickerPacksScreen(api: ApiScope.of(context)),
                ),
              );
              if (mounted) await _load();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SegmentedButton<_Tab>(
              segments: [
                ButtonSegment(value: _Tab.market, label: Text(tr('بازار'))),
                ButtonSegment(value: _Tab.bought, label: Text(tr('خریدها'))),
                ButtonSegment(value: _Tab.sales, label: Text(tr('فروش'))),
              ],
              selected: {_tab},
              onSelectionChanged: (s) {
                setState(() => _tab = s.first);
                _load();
              },
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tab == _Tab.market)
              ..._marketSection()
            else if (_tab == _Tab.bought)
              ..._boughtSection()
            else
              ..._salesSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _marketSection() {
    return [
      TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _load(),
        decoration: InputDecoration(
          labelText: tr('جست‌وجوی بسته'),
          suffixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: _load,
          ),
        ),
      ),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'all', label: Text(tr('همه'))),
          ButtonSegment(value: 'paid', label: Text(tr('پولی'))),
          ButtonSegment(value: 'free', label: Text(tr('رایگان'))),
        ],
        selected: {_kind},
        onSelectionChanged: (s) {
          setState(() => _kind = s.first);
          _load();
        },
      ),
      const SizedBox(height: 8),
      if (_market.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('بستهٔ منتشرشده‌ای پیدا نشد.'), textAlign: TextAlign.center),
        )
      else
        ..._market.map(_marketTile),
    ];
  }

  Widget _marketTile(StickerPack p) {
    final busy = _busyId == p.id;
    Widget action;
    if (p.mine) {
      action = Text(tr('مالِ شماست'), style: Theme.of(context).textTheme.bodySmall);
    } else if (p.isPaid && !p.purchased) {
      action = FilledButton(
        onPressed: busy ? null : () => _buy(p),
        child: Text(tr('خرید')),
      );
    } else {
      action = OutlinedButton(
        onPressed: busy ? null : () => _toggleInstall(p),
        child: Text(p.installed ? tr('نصب‌شده') : tr('نصب')),
      );
    }
    return Card(
      child: ListTile(
        leading: SizedBox(width: 40, height: 40, child: _cover(p.coverUrl)),
        title: Text(p.title),
        subtitle: Text(
          p.isPaid
              ? tr('{0} • {1} استیکر • {2} تومان', [
                  p.ownerName ?? '—',
                  p.stickerCount,
                  (p.price / 10).round(),
                ])
              : tr('{0} • {1} استیکر • رایگان', [p.ownerName ?? '—', p.stickerCount]),
        ),
        trailing: action,
      ),
    );
  }

  List<Widget> _boughtSection() {
    if (_bought.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('هنوز بستهٔ پولی نخریده‌اید.'), textAlign: TextAlign.center),
        ),
      ];
    }
    return _bought
        .map((b) => Card(
              child: ListTile(
                leading: SizedBox(width: 40, height: 40, child: _cover(b.coverUrl)),
                title: Text(b.packTitle),
                subtitle: Text(tr('{0} تومان', [(b.price / 10).round()])),
              ),
            ))
        .toList();
  }

  List<Widget> _salesSection() {
    final s = _sales;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('فروشِ من'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(tr('{0} فروش', [s?.salesCount ?? 0]))),
                  Chip(label: Text(tr('{0} تومان درآمدِ خالص',
                      [((s?.revenueTotal ?? 0) / 10).round()]))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr('کارمزدِ بازار ۲٪ است و پیش از واریز کسر می‌شود.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      if ((s?.packs ?? const []).isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('هنوز بستهٔ پولی برای فروش ندارید.'), textAlign: TextAlign.center),
        )
      else
        ...s!.packs.map((p) => Card(
              child: ListTile(
                leading: SizedBox(width: 40, height: 40, child: _cover(p.coverUrl)),
                title: Text(p.title),
                subtitle: Text(tr('{0} تومان • {1} فروش',
                    [(p.price / 10).round(), p.salesCount])),
              ),
            )),
    ];
  }

  Widget _cover(String? coverUrl) {
    final url = AppConfig.absoluteMedia(coverUrl);
    if (url == null) return const Icon(Icons.emoji_emotions_outlined);
    return Image.network(url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions_outlined));
  }
}
