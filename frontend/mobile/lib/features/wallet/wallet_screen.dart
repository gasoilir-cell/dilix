import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// کیفِ پول: کیفِ پاداش + پرداختِ امانی (escrow) + سهم از درآمد و لینکِ دعوت.
/// معادلِ صفحهٔ وبِ `app/wallet/page.tsx`. شارژ/برداشتِ مستقیم در Core فعلی
/// فعال نیست و به‌صورتِ کاشیِ غیرفعالِ توضیح‌دار نمایش داده می‌شود.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  RewardWallet? _wallet;
  ReferralLink? _referral;
  RevenueShare? _revenue;
  final List<PaymentOrder> _orders = [];
  bool _loading = true;
  String? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      final wallet = await api.rewardWallet();
      // این‌ها اختیاری‌اند؛ نبودشان نباید نمایشِ کیف را بشکند.
      ReferralLink? referral;
      RevenueShare? revenue;
      try {
        referral = await api.referralLink();
      } catch (_) {}
      try {
        revenue = await api.revenueShare();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _referral = referral;
        _revenue = revenue;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ کیف پول ممکن نشد: $e';
        _loading = false;
      });
    }
  }

  String _formatMoney(int amountMinor, String currency) {
    final cur = currency.toUpperCase();
    if (cur == 'IRR') return '${(amountMinor / 10).round()} تومان';
    return '${(amountMinor / 100).toStringAsFixed(2)} $cur';
  }

  Future<void> _openEscrowSheet() async {
    final created = await showModalBottomSheet<PaymentOrder>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _EscrowSheet(),
    );
    if (created != null && mounted) {
      setState(() {
        _orders.insert(0, created);
        _notice = 'سفارشِ امانی ساخته شد. برای تسویه یا برگشت از همان کارت استفاده کنید.';
      });
    }
  }

  Future<void> _updateOrder(PaymentOrder order, String action) async {
    setState(() {
      _error = null;
      _notice = null;
    });
    final api = ApiScope.of(context);
    try {
      final updated = action == 'capture'
          ? await api.capturePayment(order.id)
          : await api.refundPayment(order.id);
      if (!mounted) return;
      setState(() {
        final i = _orders.indexWhere((o) => o.id == order.id);
        if (i >= 0) _orders[i] = updated;
        _notice = action == 'capture' ? 'سفارشِ امانی تسویه شد.' : 'سفارشِ امانی برگشت خورد.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'عملیاتِ سفارش ناموفق بود: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('کیف پول'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تلاشِ مجدد',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_notice != null)
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_notice!),
                      ),
                    ),
                  _balancesCard(),
                  _actionsGrid(),
                  if (_revenue != null) _revenueCard(_revenue!),
                  _referralCard(),
                  if (_orders.isNotEmpty) _ordersCard(),
                ],
              ),
            ),
    );
  }

  Widget _balancesCard() {
    final balances = _wallet?.balances ?? const <RewardBalance>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('موجودیِ پاداش', style: TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text('${_wallet?.pendingCount ?? 0} در انتظار')),
              ],
            ),
            const SizedBox(height: 8),
            if (balances.isEmpty)
              Text(
                'هنوز پاداشی ثبت نشده است. کیف پول فعال است، اما موجودیِ پاداش ندارد.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...balances.map(
                (b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(b.currency),
                      Text(
                        _formatMoney(b.amountMinor, b.currency),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _actionTile(
          icon: Icons.swap_horiz,
          title: 'انتقالِ امن',
          desc: 'ساختِ سفارشِ امانی',
          onTap: _openEscrowSheet,
        ),
        _actionTile(
          icon: Icons.add,
          title: 'شارژِ مستقیم',
          desc: 'در Core فعلی فقط پرداختِ امانی فعال است.',
          onTap: null,
        ),
        _actionTile(
          icon: Icons.remove,
          title: 'برداشت',
          desc: 'نیازمندِ ماژولِ درگاه/تسویه است.',
          onTap: null,
        ),
        _actionTile(
          icon: Icons.pie_chart_outline,
          title: 'درآمد',
          desc: (_revenue?.eligible ?? false) ? 'فعال' : 'غیرفعال',
          onTap: null,
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(desc, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _revenueCard(RevenueShare r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('سهم از درآمد', style: TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text(r.plan)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'سهمِ فعلی: ${(r.entitlementBps / 100).toStringAsFixed(2)}٪ · واحدِ سرمایه‌گذاری: ${r.investmentUnits}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.note, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _referralCard() {
    final ref = _referral;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.link),
        title: const Text('لینکِ دعوت'),
        subtitle: Text(
          ref == null
              ? 'در دسترس نیست'
              : '${ref.url}\nدعوت‌شده‌ها: ${ref.totalReferred}',
        ),
        isThreeLine: ref != null,
      ),
    );
  }

  Widget _ordersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سفارش‌های امانیِ همین نشست', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._orders.map(
              (o) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatMoney(o.amountMinor, o.currency)),
                        Chip(label: Text(o.status)),
                      ],
                    ),
                    Text('مقصد: ${o.payeeEarthId}', style: Theme.of(context).textTheme.bodySmall),
                    if (o.status == 'held')
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _updateOrder(o, 'capture'),
                            child: const Text('تسویه'),
                          ),
                          TextButton(
                            onPressed: () => _updateOrder(o, 'refund'),
                            child: const Text('برگشت'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// فرمِ ساختِ سفارشِ امانی (Escrow) در یک bottom-sheet.
class _EscrowSheet extends StatefulWidget {
  const _EscrowSheet();

  @override
  State<_EscrowSheet> createState() => _EscrowSheetState();
}

class _EscrowSheetState extends State<_EscrowSheet> {
  final _payeeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _currency = 'IRR';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _payeeCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final payee = _payeeCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (payee.isEmpty) {
      setState(() => _error = 'Earth ID مقصد را وارد کنید.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'مبلغِ معتبر وارد کنید.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      final amountMinor = _currency == 'IRR'
          ? (amount * 10).round()
          : (amount * 100).round();
      final order = await api.createEscrow(
        payeeEarthId: payee,
        amountMinor: amountMinor,
        currency: _currency,
      );
      if (mounted) Navigator.of(context).pop(order);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'ساختِ سفارش ناموفق بود: $e';
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('انتقالِ امن (Escrow)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _payeeCtrl,
            decoration: const InputDecoration(labelText: 'Earth ID مقصد (UUID)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'مبلغ (مثلاً ۵۰۰۰۰)'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _currency,
            decoration: const InputDecoration(labelText: 'ارز'),
            items: const [
              DropdownMenuItem(value: 'IRR', child: Text('IRR (ورودی به تومان)')),
              DropdownMenuItem(value: 'USD', child: Text('USD')),
              DropdownMenuItem(value: 'EUR', child: Text('EUR')),
            ],
            onChanged: (v) => setState(() => _currency = v ?? 'IRR'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              child: Text(_sending ? 'در حالِ ساخت…' : 'ساختِ سفارشِ امانی'),
            ),
          ),
        ],
      ),
    );
  }
}
