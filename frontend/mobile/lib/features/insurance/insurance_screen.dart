import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// بیمه — parity با جریانِ dilix-api: انتخابِ محصول از کاتالوگ، استعلامِ نرخ
/// (`/quote`) و ثبتِ درخواست (`/requests`). همهٔ مبالغ به تومان‌اند.
class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  // برچسبِ فارسیِ نوعِ پوشش (منطبق با COVERAGE_LABEL بک‌اند).
  static List<(String, String)> get _coverageTypes =>
      _coverageTypesSrc.map((e) => (e.$1, tr(e.$2))).toList();

  static const _coverageTypesSrc = <(String, String)>[
    ('basic', 'پایه'),
    ('comprehensive', 'جامع'),
    ('all_risk', 'تمام‌خطر'),
  ];

  // برچسبِ فارسیِ وضعیتِ درخواست.
  static Map<String, String> get _statusLabels =>
      _statusLabelsSrc.map((k, v) => MapEntry(k, tr(v)));

  static const _statusLabelsSrc = <String, String>{
    'pending': 'در انتظار',
    'quoted': 'استعلام‌شده',
    'submitted': 'ثبت‌شده',
    'issued': 'صادرشده',
    'active': 'فعال',
    'rejected': 'ردشده',
    'cancelled': 'لغوشده',
  };

  /// محصولاتی که سرور برایشان استعلامِ سوابق دارد و کلیدِ ورودیِ لازمشان.
  /// (بقیه `found:false` می‌گیرند، پس فرمِ استعلام را اصلاً نشان نمی‌دهیم.)
  static const _plateProducts = {'third_party', 'auto_body'};
  static const _nidOnlyProducts = {'life', 'health'};

  Future<List<InsuranceProduct>>? _products;
  Future<List<InsuranceRequest>>? _requests;

  final _valueCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _cargoTypeCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _nidCtrl = TextEditingController();

  String? _product;
  String _coverageType = 'basic';
  InsuranceQuote? _quote;
  InsuranceCompare? _compare;

  /// مرکزِ انتخاب‌شده از جدولِ مقایسه؛ هنگامِ ثبت به سرور می‌رود تا بیمه‌نامه
  /// از همان مرکز صادر شود. null یعنی نرخِ پایهٔ داخلی.
  String? _providerId;

  /// خروجیِ استعلام که به‌عنوانِ `form_data` همراهِ درخواست ثبت می‌شود.
  Map<String, String> _prefill = const {};

  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _products ??= ApiScope.of(context).insuranceProducts();
    _requests ??= ApiScope.of(context).insuranceRequests();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _cargoTypeCtrl.dispose();
    _plateCtrl.dispose();
    _nidCtrl.dispose();
    super.dispose();
  }

  String _money(int toman) => tr('{0} تومان', [toman.toString()]);

  int? _readValue() {
    final v = int.tryParse(_valueCtrl.text.trim().replaceAll(',', ''));
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _quoteNow() async {
    final value = _readValue();
    if (_product == null) {
      setState(() => _error = tr('محصولِ بیمه را انتخاب کنید.'));
      return;
    }
    if (value == null) {
      setState(() => _error = tr('مبلغِ سرمایه/ارزش (تومان) معتبر وارد کنید.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final q = await ApiScope.of(context).insuranceQuote(
        product: _product!,
        cargoValue: value,
        coverageType: _coverageType,
        cargoType: _cargoTypeCtrl.text.trim(),
        origin: _originCtrl.text.trim(),
        destination: _destCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _quote = q;
        _notice = tr('حقِ بیمه: {0} (نرخِ پایه {1}٪)', [_money(q.premium), q.baseRatePct]);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('استعلام ناموفق بود: {0}', [e]);
        _busy = false;
      });
    }
  }

  Future<void> _compareNow() async {
    final value = _readValue();
    if (_product == null || value == null) {
      setState(() => _error = tr('ابتدا محصول و مبلغِ سرمایه را کامل کنید.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final c = await ApiScope.of(context).insuranceCompare(
        product: _product!,
        cargoValue: value,
        coverageType: _coverageType,
        cargoType: _cargoTypeCtrl.text.trim(),
        origin: _originCtrl.text.trim(),
        destination: _destCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _compare = c;
        // ارزان‌ترین گزینه پیش‌فرض انتخاب می‌شود.
        _providerId = c.options.isEmpty ? null : c.options.first.providerId;
        _notice = c.providerCount == 0
            ? tr('در حالِ حاضر مرکزِ فعالی پاسخ نداد؛ فقط نرخِ پایهٔ دیلیکس در دسترس است.')
            : tr('{0} مرکز پاسخ دادند.', [c.providerCount]);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('مقایسهٔ نرخ ناموفق بود: {0}', [e]);
        _busy = false;
      });
    }
  }

  Future<void> _inquiryNow() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await ApiScope.of(context).insuranceInquiry(
        product: _product!,
        plate: _plateCtrl.text.trim(),
        nationalId: _nidCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _prefill = r.found ? r.prefill : const {};
        _notice = r.bonusMalus == null
            ? r.message
            : tr('{0} — سطحِ تخفیفِ عدم‌خسارت: {1}', [r.message, r.bonusMalus]);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('استعلامِ سوابق ناموفق بود: {0}', [e]);
        _busy = false;
      });
    }
  }

  Future<void> _submitRequest() async {
    final value = _readValue();
    if (_product == null || value == null) {
      setState(() => _error = tr('ابتدا محصول و مبلغِ سرمایه را کامل کنید.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final req = await ApiScope.of(context).createInsuranceRequest(
        product: _product!,
        cargoValue: value,
        coverageType: _coverageType,
        cargoType: _cargoTypeCtrl.text.trim(),
        origin: _originCtrl.text.trim(),
        destination: _destCtrl.text.trim(),
        providerId: _providerId,
        formData: _prefill,
      );
      if (!mounted) return;
      setState(() {
        _notice = tr('درخواست ثبت شد — کدِ پیگیری: {0}{1}', [req.ref, req.providerName == null ? '' : ' · ${req.providerName}']);
        _requests = ApiScope.of(context).insuranceRequests();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('ثبتِ درخواست ناموفق بود: {0}', [e]);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('بیمه'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            ),
          if (_notice != null)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_notice!)),
            ),
          _quoteCard(),
          _requestsCard(),
        ],
      ),
    );
  }

  Widget _quoteCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<InsuranceProduct>>(
          future: _products,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
            }
            final products = snap.data ?? const <InsuranceProduct>[];
            if (products.isEmpty) {
              return Text(tr('بارگذاریِ محصولاتِ بیمه ممکن نشد.\n{0}', [snap.error ?? '']),
                  style: Theme.of(context).textTheme.bodySmall);
            }
            _product ??= products.first.id;
            final selected =
                products.firstWhere((p) => p.id == _product, orElse: () => products.first);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('استعلامِ بیمه'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _product,
                  decoration: InputDecoration(labelText: tr('محصولِ بیمه')),
                  items: [
                    for (final p in products)
                      DropdownMenuItem(value: p.id, child: Text('${p.emoji} ${p.label}')),
                  ],
                  onChanged: (v) => setState(() {
                    _product = v;
                    _quote = null;
                    // نرخ‌ها و استعلامِ محصولِ قبلی به محصولِ جدید ربطی ندارند.
                    _compare = null;
                    _providerId = null;
                    _prefill = const {};
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('{0} (تومان)', [selected.valueLabel])),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _coverageType,
                  decoration: InputDecoration(labelText: tr('نوعِ پوشش')),
                  items: [
                    for (final c in _coverageTypes)
                      DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                  ],
                  onChanged: (v) => setState(() => _coverageType = v ?? 'basic'),
                ),
                if (selected.needsCargoType) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cargoTypeCtrl,
                    decoration: InputDecoration(labelText: tr('نوعِ کالا')),
                  ),
                ],
                if (selected.needsRoute) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _originCtrl,
                    decoration: InputDecoration(labelText: tr('مبدأ')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _destCtrl,
                    decoration: InputDecoration(labelText: tr('مقصد')),
                  ),
                ],
                _inquirySection(selected),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _quoteNow,
                        child: Text(_busy ? tr('در حال…') : tr('استعلامِ نرخ')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _compareNow,
                        child: Text(tr('مقایسهٔ مراکز')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submitRequest,
                    child: Text(tr('ثبتِ درخواست')),
                  ),
                ),
                _compareSection(),
                if (_quote != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_quote!.productLabel} · ${_quote!.coverageLabel}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(tr('حقِ بیمه: {0}', [_money(_quote!.premium)])),
                          if (_quote!.providerName != null)
                            Text(tr('ارائه‌دهنده: {0}', [_quote!.providerName]),
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// فرمِ استعلامِ سوابق — فقط برای محصولاتی که سرور پشتیبانی می‌کند.
  Widget _inquirySection(InsuranceProduct selected) {
    final needsPlate = _plateProducts.contains(selected.id);
    final needsNid = needsPlate || _nidOnlyProducts.contains(selected.id);
    if (!needsNid) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(),
        Text(tr('استعلامِ سوابق (اختیاری)'),
            style: Theme.of(context).textTheme.titleSmall),
        Text(
          needsPlate
              ? tr('با پلاک یا کد ملی، سوابق و سطحِ تخفیف را می‌آوریم.')
              : tr('با کد ملی، اطلاعاتِ هویتی را می‌آوریم.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (needsPlate) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _plateCtrl,
            decoration: InputDecoration(labelText: tr('پلاکِ خودرو')),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _nidCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('کد ملی')),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _inquiryNow,
            icon: const Icon(Icons.search, size: 18),
            label: Text(tr('استعلام')),
          ),
        ),
        if (_prefill.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            tr('سوابقِ بازیابی‌شده همراهِ درخواست ثبت می‌شود: {0}', [_prefill.keys.join(tr('، '))]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  /// جدولِ مقایسهٔ نرخِ مراکز؛ انتخابِ هر ردیف مرکزِ صادرکننده را تعیین می‌کند.
  Widget _compareSection() {
    final c = _compare;
    if (c == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(tr('مقایسهٔ نرخ — {0} · {1}', [c.productLabel, c.coverageLabel]),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        for (final o in c.options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              o.providerId == _providerId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: Theme.of(context).colorScheme.primary,
            ),
            onTap: () => setState(() => _providerId = o.providerId),
            title: Row(
              children: [
                Expanded(child: Text(o.providerName ?? tr('نرخِ پایهٔ دیلیکس'))),
                if (o.best)
                  Chip(
                    label: Text(tr('ارزان‌ترین')),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            subtitle: Text(
              o.currency == 'IRR'
                  ? _money(o.premium)
                  : '${o.premium} ${o.currency}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _requestsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<InsuranceRequest>>(
          future: _requests,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
            }
            final reqs = snap.data ?? const <InsuranceRequest>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('درخواست‌های من'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (reqs.isEmpty)
                  Text(tr('هنوز درخواستی ثبت نشده.'),
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  ...reqs.map(
                    (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text('${r.productLabel} · ${r.ref}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Chip(label: Text(_statusLabels[r.status] ?? r.status)),
                            ],
                          ),
                          Text(tr('حقِ بیمه: {0}', [_money(r.premium)]),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
