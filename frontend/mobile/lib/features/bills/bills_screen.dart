import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';

/// قبوض و خدماتِ شهری — معادلِ صفحهٔ وبِ `app/(main)/bills/page.tsx`.
///
/// نکتهٔ کلیدی: مبلغ و نوعِ سازمان از خودِ شناسه‌های قبض **رمزگشایی** می‌شود
/// (رقم‌های کنترلیِ استانداردِ قبوضِ ایران)، پس استعلام آفلاین و بدونِ سرویسِ
/// بیرونی انجام می‌شود. سرور همان محاسبه را دوباره و مستقل انجام می‌دهد؛ این‌جا
/// فقط ورودی گرفته می‌شود.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  final _billCtrl = TextEditingController();
  final _payCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  /// true = ورودیِ بارکدِ ۲۶رقمی، false = دو شناسهٔ جدا.
  bool _byBarcode = false;

  bool _busy = false;
  String? _error;
  String? _notice;

  BillInquiry? _found;
  BillReceipt? _receipt;

  List<BillReceipt> _history = const [];
  List<SavedBill> _saved = const [];
  bool _loadedLists = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedLists) {
      _loadedLists = true;
      _loadLists();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _billCtrl.dispose();
    _payCtrl.dispose();
    _barcodeCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  /// تومانِ خوانا از مبلغِ ریالیِ سرور.
  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  String _date(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  /// هر دو فهرست اختیاری‌اند؛ خطای یکی نباید دیگری را از کار بیندازد.
  Future<void> _loadLists() async {
    final api = ApiScope.of(context);
    var history = _history;
    var saved = _saved;
    try {
      history = await api.billHistory();
    } catch (_) {}
    try {
      saved = await api.savedBills();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _history = history;
      _saved = saved;
    });
  }

  /// اجرایِ یک عملیاتِ شبکه‌ای با مدیریتِ متمرکزِ خطا و قفلِ دکمه‌ها.
  Future<void> _run(Future<void> Function() body, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await body();
    } on ApiException catch (e) {
      // پیامِ سرور فارسی و دقیق است (مثلِ «این قبض قبلاً پرداخت شده»)؛
      // بازنویسی‌اش اطلاعات را از کاربر می‌گیرد.
      if (mounted) setState(() => _error = e.detail.isNotEmpty ? e.detail : failure);
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({String? billId, String? paymentId, String? barcode}) _input() {
    if (_byBarcode) {
      return (billId: null, paymentId: null, barcode: _barcodeCtrl.text.trim());
    }
    return (
      billId: _billCtrl.text.trim(),
      paymentId: _payCtrl.text.trim(),
      barcode: null,
    );
  }

  Future<void> _inquire() async {
    final v = _input();
    await _run(() async {
      final found = await ApiScope.of(context).billInquiry(
        billId: v.billId,
        paymentId: v.paymentId,
        barcode: v.barcode,
      );
      if (!mounted) return;
      setState(() {
        _found = found;
        _receipt = null;
      });
    }, tr('استعلامِ قبض ناموفق بود'));
  }

  Future<void> _pay() async {
    final v = _input();
    final title = _titleCtrl.text.trim();
    await _run(() async {
      final receipt = await ApiScope.of(context).payBill(
        billId: v.billId,
        paymentId: v.paymentId,
        barcode: v.barcode,
        title: title.isEmpty ? null : title,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _found = null;
        _notice = tr('✅ قبض پرداخت شد. کدِ رهگیری: {0}', [receipt.ref]);
      });
      await _loadLists();
    }, tr('پرداختِ قبض ناموفق بود'));
  }

  /// ذخیرهٔ شناسهٔ قبضِ استعلام‌شده برای دوره‌های بعد.
  Future<void> _saveCurrent() async {
    final billId = _found?.billId ?? _receipt?.billId;
    if (billId == null) return;
    final title = _titleCtrl.text.trim();
    await _run(() async {
      await ApiScope.of(context).saveBill(
        title: title.isEmpty ? tr('قبضِ من') : title,
        billId: billId,
      );
      if (!mounted) return;
      setState(() => _notice = tr('شناسهٔ قبض ذخیره شد.'));
      await _loadLists();
    }, tr('ذخیرهٔ قبض ناموفق بود'));
  }

  Future<void> _removeSaved(SavedBill s) async {
    await _run(() async {
      await ApiScope.of(context).deleteSavedBill(s.id);
      await _loadLists();
    }, tr('حذفِ قبضِ ذخیره‌شده ناموفق بود'));
  }

  /// شناسهٔ ذخیره‌شده را در فرم می‌گذارد؛ شناسهٔ پرداخت هر دوره تازه است پس
  /// خالی می‌ماند تا کاربر از قبضِ جدید واردش کند.
  void _useSaved(SavedBill s) {
    setState(() {
      _byBarcode = false;
      _billCtrl.text = s.billId;
      _payCtrl.clear();
      _titleCtrl.text = s.title;
      _found = null;
      _receipt = null;
      _error = null;
      _notice = null;
    });
    _tabs.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('قبوض و خدماتِ شهری')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: tr('پرداخت')),
            Tab(text: tr('تاریخچه')),
            Tab(text: tr('ذخیره‌شده')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_payTab(), _historyTab(), _savedTab()],
      ),
    );
  }

  // ── تبِ پرداخت ──
  Widget _payTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('دو شناسه'))),
            ButtonSegment(value: true, label: Text(tr('بارکد'))),
          ],
          selected: {_byBarcode},
          onSelectionChanged: (s) => setState(() {
            _byBarcode = s.first;
            _found = null;
            _receipt = null;
          }),
        ),
        const SizedBox(height: 12),
        if (_byBarcode)
          TextField(
            controller: _barcodeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
            decoration: InputDecoration(
              labelText: tr('بارکدِ قبض (۲۶ رقم)'),
              helperText: tr('همان عددِ بلندِ زیرِ بارکدِ چاپ‌شده روی قبض'),
              border: const OutlineInputBorder(),
            ),
          )
        else ...[
          TextField(
            controller: _billCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('شناسهٔ قبض'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _payCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('شناسهٔ پرداخت'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: tr('نامِ دلخواه (اختیاری)'),
            hintText: tr('مثلاً برقِ خانه'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _inquire,
            icon: const Icon(Icons.search),
            label: Text(_busy ? tr('در حال…') : tr('استعلام')),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!),
            ),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_notice!),
            ),
          ),
        ],
        if (_found != null) ...[
          const SizedBox(height: 12),
          _inquiryCard(_found!),
        ],
        if (_receipt != null) ...[
          const SizedBox(height: 12),
          _receiptCard(_receipt!, showSave: true),
        ],
      ],
    );
  }

  Widget _inquiryCard(BillInquiry b) {
    final blocked = b.alreadyPaid || !b.balanceEnough;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(b.typeEmoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(b.typeLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_toman(b.amount),
                style: Theme.of(context).textTheme.headlineSmall),
            if (b.period != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('دورهٔ {0}', [b.period!]),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (b.alreadyPaid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('این قبض قبلاً پرداخت شده است.'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (!b.alreadyPaid && !b.balanceEnough)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('موجودیِ کیفِ پول کافی نیست.'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || blocked ? null : _pay,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(tr('پرداخت')),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _saveCurrent,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(tr('ذخیره')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptCard(BillReceipt r, {bool showSave = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(r.typeEmoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.title?.isNotEmpty == true ? r.title! : r.typeLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(_date(r.paidAt),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(_toman(r.amount),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(tr('کدِ رهگیری: {0}', [r.ref]),
                style: Theme.of(context).textTheme.bodySmall),
            Text(tr('شناسهٔ قبض: {0}', [r.billId]),
                style: Theme.of(context).textTheme.bodySmall),
            if (showSave) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _saveCurrent,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(tr('ذخیرهٔ این شناسه')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── تبِ تاریخچه ──
  Widget _historyTab() {
    if (_history.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadLists,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr('هنوز قبضی پرداخت نکرده‌اید.'),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLists,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [for (final r in _history) _receiptCard(r)],
      ),
    );
  }

  // ── تبِ ذخیره‌شده ──
  Widget _savedTab() {
    return RefreshIndicator(
      onRefresh: _loadLists,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_saved.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr('شناسهٔ ذخیره‌شده‌ای ندارید.'),
                  textAlign: TextAlign.center),
            )
          else
            for (final s in _saved)
              Card(
                child: ListTile(
                  leading: Text(s.typeEmoji, style: const TextStyle(fontSize: 20)),
                  title: Text(s.title),
                  subtitle: Text('${s.typeLabel} · ${s.billId}'),
                  onTap: () => _useSaved(s),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tr('حذف'),
                    onPressed: _busy ? null : () => _removeSaved(s),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
