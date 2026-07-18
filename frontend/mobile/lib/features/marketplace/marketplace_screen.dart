import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

const _orderStatusLabel = <String, String>{
  'pending': 'در انتظارِ پذیرش',
  'accepted': 'پذیرفته‌شده',
  'in_progress': 'در حالِ انجام',
  'delivered': 'تحویل‌شده',
  'completed': 'تکمیل‌شده',
  'cancelled': 'لغوشده',
  'disputed': 'مورد اختلاف',
};

String _formatPrice(int minor, String currency) {
  if (currency == 'IRR') return '${(minor / 10).round()} تومان';
  return '${(minor / 100).round()} $currency';
}

/// بازارگاهِ خدمت (فریلنسری): فهرست/جستجویِ آگهی، سفارش، و سفارش‌های من با
/// چرخهٔ accept/deliver/complete. هم‌سبکِ سایرِ صفحاتِ feature.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _searchController = TextEditingController();

  Future<List<Listing>>? _listings;
  Future<List<MarketOrder>>? _orders;
  String? _myEarthId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listings ??= ApiScope.of(context).marketplaceListings();
    _loadMe();
  }

  Future<void> _loadMe() async {
    if (_myEarthId != null) return;
    try {
      final me = await ApiScope.of(context).me();
      if (mounted) setState(() => _myEarthId = me.earthId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _listings = ApiScope.of(context)
          .marketplaceListings(keyword: _searchController.text.trim());
    });
  }

  void _reloadOrders() {
    setState(() => _orders = ApiScope.of(context).marketplaceOrders());
  }

  Future<void> _order(Listing l) async {
    try {
      await ApiScope.of(context).placeOrder(
        l.id,
        agreedPriceMinor: l.basePriceMinor,
        currency: l.currency,
      );
      _snack('سفارش ثبت شد؛ مبلغ در امانت نگه داشته شد.');
      _reloadOrders();
      _tabs.animateTo(1);
    } catch (_) {
      _snack('ثبتِ سفارش ممکن نشد (نمی‌توانید از آگهیِ خودتان سفارش دهید).');
    }
  }

  Future<void> _act(MarketOrder o, String action) async {
    try {
      await ApiScope.of(context).orderAction(o.id, action);
      _reloadOrders();
    } catch (_) {
      _snack('انجامِ این عملیات ممکن نشد.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بازارگاه'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (i) {
            if (i == 1 && _orders == null) _reloadOrders();
          },
          tabs: const [
            Tab(text: 'خدمات'),
            Tab(text: 'سفارش‌های من'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_listingsTab(), _ordersTab()],
      ),
    );
  }

  Widget _listingsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'جستجوی خدمت…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _search, child: const Text('جستجو')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Listing>>(
            future: _listings,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text('بارگذاری ممکن نشد.\n${snap.error}',
                      textAlign: TextAlign.center),
                );
              }
              final items = snap.data ?? const <Listing>[];
              if (items.isEmpty) {
                return const Center(child: Text('خدمتی ثبت نشده است.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final l = items[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.title,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(l.description,
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${l.category} · ${l.deliveryDays} روز',
                                  style: Theme.of(context).textTheme.bodySmall),
                              Text(_formatPrice(l.basePriceMinor, l.currency),
                                  style:
                                      const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FilledButton(
                              onPressed: () => _order(l),
                              child: const Text('سفارش'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ordersTab() {
    return FutureBuilder<List<MarketOrder>>(
      future: _orders,
      builder: (context, snap) {
        if (_orders == null ||
            snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('بارگذاری ممکن نشد.\n${snap.error}',
                textAlign: TextAlign.center),
          );
        }
        final orders = snap.data ?? const <MarketOrder>[];
        if (orders.isEmpty) {
          return const Center(child: Text('هنوز سفارشی ندارید.'));
        }
        return RefreshIndicator(
          onRefresh: () async => _reloadOrders(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, i) => _orderCard(orders[i]),
          ),
        );
      },
    );
  }

  Widget _orderCard(MarketOrder o) {
    final isProvider = _myEarthId != null && o.providerEarthId == _myEarthId;
    final isBuyer = _myEarthId != null && o.buyerEarthId == _myEarthId;
    final actions = <Widget>[];
    if (isProvider && o.status == 'pending') {
      actions.add(_actionBtn('پذیرش', () => _act(o, 'accept')));
    }
    if (isProvider && (o.status == 'accepted' || o.status == 'in_progress')) {
      actions.add(_actionBtn('تحویل', () => _act(o, 'deliver')));
    }
    if (isBuyer && o.status == 'delivered') {
      actions.add(_actionBtn('تأیید و تکمیل', () => _act(o, 'complete')));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('سفارش #${o.id.substring(0, 8)}…',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text(_orderStatusLabel[o.status] ?? o.status)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('نقشِ شما: ${isProvider ? 'فروشنده' : 'خریدار'}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text(_formatPrice(o.agreedPriceMinor, o.currency),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onTap) =>
      FilledButton(onPressed: onTap, child: Text(label));
}
