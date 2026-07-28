import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/models.dart';

/// فروشگاه و پرداختِ امانی — معادلِ صفحهٔ وبِ `app/(main)/shop/page.tsx`.
///
/// چهار بخش: کاتالوگ، کالاهای من، خریدها، فروش‌ها.
///
/// پولِ خریدار هنگامِ ثبتِ سفارش **بلوکه** می‌شود، نه منتقل؛ تا تأییدِ دریافت،
/// نه در دسترسِ خریدار است و نه مالِ فروشنده. دکمه‌های هر سفارش از پرچم‌های
/// `can*`ِ سرور می‌آیند تا ماشینِ وضعیت دوباره در کلاینت پیاده نشود.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  final _searchCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  List<ShopProduct> _catalog = const [];
  List<ShopProduct> _mine = const [];
  List<ShopOrder> _orders = const [];
  List<ShopOrder> _sales = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadAll();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // سرور ریال می‌دهد؛ کاربرِ ایرانی تومان می‌خواند.
  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  Future<void> _loadAll() async {
    await _run(() async {
      final api = ApiScope.of(context);
      final catalog = await api.shopProducts();
      final mine = await api.myProducts();
      final orders = await api.myOrders();
      final sales = await api.mySales();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _mine = mine;
        _orders = orders;
        _sales = sales;
      });
    }, tr('بارگیریِ فروشگاه ناموفق بود'));
  }

  Future<void> _run(Future<void> Function() body, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await body();
    } on ApiException catch (e) {
      // پیامِ سرور دقیق‌تر است (مثلِ «موجودیِ کالا کافی نیست»).
      if (mounted) {
        setState(() => _error = e.detail.isNotEmpty ? e.detail : failure);
      }
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('تأیید')),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _search() async {
    await _run(() async {
      final api = ApiScope.of(context);
      final rows = await api.shopProducts(q: _searchCtrl.text.trim());
      if (mounted) setState(() => _catalog = rows);
    }, tr('جستجو ناموفق بود'));
  }

  Future<void> _addProduct() async {
    final title = _titleCtrl.text.trim();
    final toman = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (title.length < 2) {
      setState(() => _error = tr('عنوان دستِ‌کم دو نویسه باشد'));
      return;
    }
    if (toman < 100) {
      setState(() => _error = tr('قیمت دستِ‌کم ۱۰۰ تومان باشد'));
      return;
    }
    // خالی یعنی نامحدود؛ سرور آن را با ‎-۱ می‌شناسد.
    final raw = _stockCtrl.text.trim();
    final stock = raw.isEmpty ? -1 : (int.tryParse(raw) ?? -1);

    await _run(() async {
      final api = ApiScope.of(context);
      await api.createProduct(
        title: title,
        price: toman * 10,
        stock: stock,
        description: _descCtrl.text.trim(),
      );
      final mine = await api.myProducts();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      _titleCtrl.clear();
      _priceCtrl.clear();
      _stockCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _mine = mine;
        _catalog = catalog;
        _notice = tr('کالا افزوده شد');
      });
    }, tr('افزودنِ کالا ناموفق بود'));
  }

  Future<void> _removeProduct(ShopProduct p) async {
    final yes = await _confirm(
      tr('برداشتنِ کالا'),
      tr('«{0}» از کاتالوگ برداشته شود؟', [p.title]),
    );
    if (!yes) return;
    await _run(() async {
      final api = ApiScope.of(context);
      await api.removeProduct(p.id);
      final mine = await api.myProducts();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _catalog = catalog;
        _notice = tr('کالا برداشته شد');
      });
    }, tr('برداشتنِ کالا ناموفق بود'));
  }

  Future<void> _buy(ShopProduct p) async {
    final qty = await _askQty(p);
    if (qty == null) return;
    final yes = await _confirm(
      tr('ثبتِ سفارش'),
      tr('{0} عدد «{1}» به مبلغِ {2}؟ مبلغ تا تأییدِ دریافت بلوکه می‌ماند و '
          'پس از آن به فروشنده می‌رسد.', [qty, p.title, _toman(p.price * qty)]),
    );
    if (!yes) return;
    await _run(() async {
      final api = ApiScope.of(context);
      await api.createOrder(productId: p.id, qty: qty);
      final orders = await api.myOrders();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _catalog = catalog;
        _notice = tr('سفارش ثبت شد');
      });
      _tabs.animateTo(2);
    }, tr('ثبتِ سفارش ناموفق بود'));
  }

  Future<int?> _askQty(ShopProduct p) async {
    final ctrl = TextEditingController(text: '1');
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('تعداد')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('چند عدد؟'),
            helperText: p.unlimited
                ? tr('موجودیِ نامحدود')
                : tr('موجودی: {0}', [p.stock]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 1),
            child: Text(tr('تأیید')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null) return null;
    return r < 1 ? 1 : r;
  }

  Future<void> _act(ShopOrder o, String kind) async {
    final ask = switch (kind) {
      'accept' => tr('این سفارش پذیرفته شود؟'),
      'ship' => tr('ارسالِ کالا ثبت شود؟'),
      'complete' =>
        tr('دریافتِ کالا تأیید شود؟ پس از آن پول به فروشنده می‌رسد و بازگشتی '
            'در کار نیست.'),
      _ => tr('سفارش لغو و وجهِ بلوکه بازگردانده شود؟'),
    };
    final yes = await _confirm(tr('سفارشِ {0}', [o.ref]), ask);
    if (!yes) return;

    await _run(() async {
      final api = ApiScope.of(context);
      switch (kind) {
        case 'accept':
          await api.acceptOrder(o.id);
        case 'ship':
          await api.shipOrder(o.id);
        case 'complete':
          await api.completeOrder(o.id);
        default:
          await api.cancelOrder(o.id);
      }
      final orders = await api.myOrders();
      final sales = await api.mySales();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _sales = sales;
        _catalog = catalog;
        _notice = tr('انجام شد');
      });
    }, tr('انجامِ عملیات ناموفق بود'));
  }

  StatusTone _statusTone(String s) => switch (s) {
        'pending' => StatusTone.warning,
        'accepted' => StatusTone.info,
        'shipped' => StatusTone.accent,
        'completed' => StatusTone.success,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('فروشگاه')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: tr('کاتالوگ')),
            Tab(text: tr('کالاهای من')),
            Tab(text: tr('خریدها')),
            Tab(text: tr('فروش‌ها')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_catalogTab(), _mineTab(), _ordersTab(), _salesTab()],
      ),
    );
  }

  Widget? _banner() {
    if (_error != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_error!),
        ),
      );
    }
    if (_notice != null) {
      return Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(_notice!),
        ),
      );
    }
    return null;
  }

  Widget _wrap(List<Widget> children) {
    final banner = _banner();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (banner != null) ...[banner, const SizedBox(height: 12)],
          ...children,
        ],
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      );

  // ── کاتالوگ ───────────────────────────────────────────────────────────────
  Widget _catalogTab() {
    return _wrap([
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: tr('جستجوی کالا'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _search,
            child: Text(tr('جستجو')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_catalog.isEmpty) _empty(tr('فعلاً کالایی برای فروش نیست')),
      ..._catalog.map((p) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title,
                                style: Theme.of(context).textTheme.titleSmall),
                            Text(p.sellerName ?? p.sellerEarthId,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Text(_toman(p.price),
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  if ((p.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(p.description!,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    p.unlimited
                        ? tr('موجودیِ نامحدود')
                        : tr('موجودی: {0}', [p.stock]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _buy(p),
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: Text(tr('خرید')),
                    ),
                  ),
                ],
              ),
            ),
          )),
      const SizedBox(height: 12),
      Text(
        tr('پولِ شما تا تأییدِ دریافتِ کالا بلوکه می‌ماند و تنها پس از آن به '
            'فروشنده می‌رسد.'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  // ── کالاهای من ────────────────────────────────────────────────────────────
  Widget _mineTab() {
    return _wrap([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('افزودنِ کالا'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: tr('عنوان')),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: tr('قیمت (تومان)')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('موجودی'),
                        helperText: tr('خالی = نامحدود'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('توضیح')),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _addProduct,
                  icon: const Icon(Icons.add),
                  label: Text(tr('افزودنِ کالا')),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_mine.isEmpty) _empty(tr('هنوز کالایی نگذاشته‌اید')),
      ..._mine.map((p) => Card(
            child: ListTile(
              title: Row(
                children: [
                  Expanded(child: Text(p.title)),
                  if (!p.isActive)
                    Chip(
                      label: Text(tr('غیرفعال'),
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              subtitle: Text(
                '${_toman(p.price)} · '
                '${p.unlimited ? tr('نامحدود') : tr('موجودی: {0}', [p.stock])} · '
                '${tr('فروخته‌شده: {0}', [p.soldCount])}',
              ),
              trailing: p.isActive
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _removeProduct(p),
                    )
                  : null,
            ),
          )),
    ]);
  }

  // ── سفارش‌ها ──────────────────────────────────────────────────────────────
  Widget _ordersTab() => _wrap([
        if (_orders.isEmpty) _empty(tr('هنوز خریدی نداشته‌اید')),
        ..._orders.map((o) => _orderCard(o, buying: true)),
      ]);

  Widget _salesTab() => _wrap([
        if (_sales.isEmpty) _empty(tr('هنوز فروشی نداشته‌اید')),
        ..._sales.map((o) => _orderCard(o, buying: false)),
      ]);

  Widget _orderCard(ShopOrder o, {required bool buying}) {
    final peer = buying
        ? (o.sellerName ?? o.sellerEarthId)
        : (o.buyerName ?? o.buyerEarthId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(o.title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                StatusChip(label: o.statusLabel, tone: _statusTone(o.status)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${buying ? tr('فروشنده') : tr('خریدار')}: $peer',
                style: Theme.of(context).textTheme.bodySmall),
            Text(o.ref, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('${o.qty} × ${_toman(o.unitPrice)} = ${_toman(o.total)}'),
            if (o.commission > 0)
              Text(tr('کارمزدِ پلتفرم: {0}', [_toman(o.commission)]),
                  style: Theme.of(context).textTheme.bodySmall),
            if (o.escrowLocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('وجه بلوکه است'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DilixSemanticColors.from(context).warning)),
              ),
            if ((o.address ?? '').isNotEmpty)
              Text(tr('نشانی: {0}', [o.address!]),
                  style: Theme.of(context).textTheme.bodySmall),
            if (o.hasAction) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (o.canAccept)
                    FilledButton(
                      onPressed: _busy ? null : () => _act(o, 'accept'),
                      child: Text(tr('پذیرش')),
                    ),
                  if (o.canShip)
                    FilledButton(
                      onPressed: _busy ? null : () => _act(o, 'ship'),
                      child: Text(tr('ارسال شد')),
                    ),
                  if (o.canComplete)
                    FilledButton(
                      onPressed: _busy ? null : () => _act(o, 'complete'),
                      child: Text(tr('تأییدِ دریافت')),
                    ),
                  if (o.canCancel)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _act(o, 'cancel'),
                      child: Text(tr('لغو')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
