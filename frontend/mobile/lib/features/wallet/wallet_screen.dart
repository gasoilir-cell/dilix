import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'holdings_screen.dart';
import 'qr_receive_sheet.dart';
import 'qr_scan_pay_screen.dart';
import 'topup_screen.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
/// کیفِ پول: کیفِ پاداش + پرداختِ امانی (escrow) + سهم از درآمد و لینکِ دعوت.
/// معادلِ صفحهٔ وبِ `app/wallet/page.tsx`. شارژ از درگاهِ پرداخت و جیب‌های ارزی
/// در صفحه‌های جداگانه (`TopupScreen` / `HoldingsScreen`) باز می‌شوند.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  RewardWallet? _wallet;
  ReferralLink? _referral;
  RevenueShare? _revenue;
  List<WalletTransaction> _transactions = const [];
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
      var transactions = const <WalletTransaction>[];
      try {
        referral = await api.referralLink();
      } catch (_) {}
      try {
        revenue = await api.revenueShare();
      } catch (_) {}
      try {
        transactions = await api.walletTransactions(limit: 20);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _referral = referral;
        _revenue = revenue;
        _transactions = transactions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ کیف پول ممکن نشد: {0}', [e]);
        _loading = false;
      });
    }
  }

  String _formatMoney(int amountMinor, String currency) {
    final cur = currency.toUpperCase();
    if (cur == 'IRR') return tr('{0} تومان', [(amountMinor / 10).round()]);
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
        _notice = tr('سفارشِ امانی ساخته شد. برای تسویه یا برگشت از همان کارت استفاده کنید.');
      });
    }
  }

  Future<void> _openTransferSheet() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TransferSheet(),
    );
    if (done == true && mounted) {
      setState(() => _notice = tr('انتقال انجام شد.'));
      await _load();
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
        _notice = action == 'capture' ? tr('سفارشِ امانی تسویه شد.') : tr('سفارشِ امانی برگشت خورد.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('عملیاتِ سفارش ناموفق بود: {0}', [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('کیف پول')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: tr('تلاشِ مجدد'),
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
                  if (_transactions.isNotEmpty) _transactionsCard(),
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
                Text(tr('موجودیِ پاداش'), style: const TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text(tr('{0} در انتظار', [_wallet?.pendingCount ?? 0]))),
              ],
            ),
            const SizedBox(height: 8),
            if (balances.isEmpty)
              Text(
                tr('هنوز پاداشی ثبت نشده است. کیف پول فعال است، اما موجودیِ پاداش ندارد.'),
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

  Future<void> _openScanPay() async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const QrScanPayScreen()),
    );
    if (paid == true && mounted) {
      setState(() => _notice = tr('پرداخت انجام شد.'));
      await _load();
    }
  }

  Future<void> _openTopup() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TopupScreen()),
    );
    if (done == true && mounted) await _load();
  }

  Future<void> _openHoldings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HoldingsScreen()),
    );
    if (mounted) await _load();
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
          icon: Icons.qr_code_scanner,
          title: tr('اسکن و پرداخت'),
          desc: tr('کدِ QRِ گیرنده را بخوانید'),
          onTap: _openScanPay,
        ),
        _actionTile(
          icon: Icons.qr_code_2,
          title: tr('دریافت با QR'),
          desc: tr('کدِ «به من پرداخت کن» با مبلغِ دلخواه'),
          onTap: () => showReceiveQr(context),
        ),
        _actionTile(
          icon: Icons.swap_horiz,
          title: tr('انتقالِ امن'),
          desc: tr('ساختِ سفارشِ امانی'),
          onTap: _openEscrowSheet,
        ),
        _actionTile(
          icon: Icons.send_to_mobile,
          title: tr('انتقال به کاربر'),
          desc: tr('پرداختِ مستقیم از کیف به کیف با Earth ID'),
          onTap: _openTransferSheet,
        ),
        _actionTile(
          icon: Icons.add_card,
          title: tr('شارژِ مستقیم'),
          desc: tr('افزایشِ موجودی از درگاهِ پرداخت'),
          onTap: _openTopup,
        ),
        _actionTile(
          icon: Icons.account_balance_wallet_outlined,
          title: tr('جیب‌های ارزی و رمزارز'),
          desc: tr('تبدیل، آدرسِ واریز و برداشت — BTC، ETH، TON، TRX'),
          onTap: _openHoldings,
        ),
        _actionTile(
          icon: Icons.pie_chart_outline,
          title: tr('درآمد'),
          desc: (_revenue?.eligible ?? false) ? tr('فعال') : tr('غیرفعال'),
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

  Widget _transactionsCard() {
    final currency = _wallet?.balances.isNotEmpty ?? false
        ? _wallet!.balances.first.currency
        : 'IRR';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(tr('گردشِ حساب'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final t in _transactions)
              ListTile(
                dense: true,
                leading: Icon(
                  t.isOutgoing ? Icons.north_east : Icons.south_west,
                  color: t.isOutgoing
                      ? Theme.of(context).colorScheme.error
                      : DilixSemanticColors.from(context).success,
                  size: 20,
                ),
                title: Text(
                  (t.description ?? '').isEmpty ? t.type : t.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (t.createdAt != null) _formatDate(t.createdAt!),
                    t.status,
                  ].join(' • '),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  '${t.isOutgoing ? '−' : '+'} ${_formatMoney(t.amountMinor, currency)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = d.toLocal();
    return '${l.year}/${two(l.month)}/${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
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
                Text(tr('سهم از درآمد'), style: const TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text(r.plan)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr('سهمِ فعلی: {0}٪ · واحدِ سرمایه‌گذاری: {1}', [(r.entitlementBps / 100).toStringAsFixed(2), r.investmentUnits]),
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

  Future<void> _copyInvite(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('لینکِ دعوت کپی شد.'))));
  }

  Future<void> _shareInvite(String url) async {
    await Share.share(
      tr('با این لینک به دیلیکس بپیوند: {0}', [url]),
      subject: tr('دعوت به دیلیکس'),
    );
  }

  Widget _referralCard() {
    final ref = _referral;
    final url = ref?.url ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('لینکِ دعوت'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (ref != null)
                  Text(tr('دعوت‌شده‌ها: {0}', [ref.totalReferred]),
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              url.isEmpty ? tr('در دسترس نیست') : url,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: url.isEmpty ? null : () => _copyInvite(url),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('کپی')),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: url.isEmpty ? null : () => _shareInvite(url),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(tr('اشتراک‌گذاری')),
                ),
              ],
            ),
          ],
        ),
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
            Text(tr('سفارش‌های امانیِ همین نشست'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    Text(tr('مقصد: {0}', [o.payeeEarthId]), style: Theme.of(context).textTheme.bodySmall),
                    if (o.status == 'held')
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _updateOrder(o, 'capture'),
                            child: Text(tr('تسویه')),
                          ),
                          TextButton(
                            onPressed: () => _updateOrder(o, 'refund'),
                            child: Text(tr('برگشت')),
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
/// انتقالِ مستقیمِ موجودی به کیفِ پولِ کاربرِ دیگر. مبلغ به تومان گرفته و به ریال
/// (واحدِ خردِ کیف) ارسال می‌شود — همان قراردادی که هدیهٔ نقدی هم دارد.
class _TransferSheet extends StatefulWidget {
  const _TransferSheet();

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _toCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _toCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final to = _toCtrl.text.trim();
    final toman = int.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    if (to.length < 3) {
      setState(() => _error = tr('Earth ID مقصد را وارد کنید.'));
      return;
    }
    if (toman == null || toman <= 0) {
      setState(() => _error = tr('مبلغِ معتبر (تومان) وارد کنید.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).walletTransfer(
        toEarthId: to,
        amountMinor: toman * 10,
        description: _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('انتقال ناموفق بود: {0}', [e]);
        _sending = false;
      });
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
          Text(tr('انتقال به کیفِ کاربرِ دیگر'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _toCtrl,
            decoration: InputDecoration(labelText: tr('Earth ID مقصد')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: tr('مبلغ (تومان)'), hintText: tr('مثلاً ۵۰۰۰۰')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(labelText: tr('توضیح (اختیاری)')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              child: Text(_sending ? tr('در حالِ انتقال…') : tr('انتقال')),
            ),
          ),
        ],
      ),
    );
  }
}

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
      setState(() => _error = tr('Earth ID مقصد را وارد کنید.'));
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = tr('مبلغِ معتبر وارد کنید.'));
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
          _error = tr('ساختِ سفارش ناموفق بود: {0}', [e]);
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
          Text(tr('انتقالِ امن (Escrow)'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _payeeCtrl,
            decoration: InputDecoration(labelText: tr('Earth ID مقصد (UUID)')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('مبلغ (مثلاً ۵۰۰۰۰)')),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: InputDecoration(labelText: tr('ارز')),
            items: [
              DropdownMenuItem(value: 'IRR', child: Text(tr('IRR (ورودی به تومان)'))),
              const DropdownMenuItem(value: 'USD', child: Text('USD')),
              const DropdownMenuItem(value: 'EUR', child: Text('EUR')),
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
              child: Text(_sending ? tr('در حالِ ساخت…') : tr('ساختِ سفارشِ امانی')),
            ),
          ),
        ],
      ),
    );
  }
}
