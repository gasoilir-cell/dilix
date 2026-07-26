import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// بیمه — parity با جریانِ dilix-api: انتخابِ محصول از کاتالوگ، استعلامِ نرخ
/// (`/quote`) و ثبتِ درخواست (`/requests`). همهٔ مبالغ به تومان‌اند.
class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  // برچسبِ فارسیِ نوعِ پوشش (منطبق با COVERAGE_LABEL بک‌اند).
  static const _coverageTypes = <(String, String)>[
    ('basic', 'پایه'),
    ('comprehensive', 'جامع'),
    ('all_risk', 'تمام‌خطر'),
  ];

  // برچسبِ فارسیِ وضعیتِ درخواست.
  static const _statusLabels = <String, String>{
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

  String _money(int toman) => '${toman.toString()} تومان';

  int? _readValue() {
    final v = int.tryParse(_valueCtrl.text.trim().replaceAll(',', ''));
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _quoteNow() async {
    final value = _readValue();
    if (_product == null) {
      setState(() => _error = 'محصولِ بیمه را انتخاب کنید.');
      return;
    }
    if (value == null) {
      setState(() => _error = 'مبلغِ سرمایه/ارزش (تومان) معتبر وارد کنید.');
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
        _notice = 'حقِ بیمه: ${_money(q.premium)} (نرخِ پایه ${q.baseRatePct}٪)';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'استعلام ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  Future<void> _compareNow() async {
    final value = _readValue();
    if (_product == null || value == null) {
      setState(() => _error = 'ابتدا محصول و مبلغِ سرمایه را کامل کنید.');
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
            ? 'در حالِ حاضر مرکزِ فعالی پاسخ نداد؛ فقط نرخِ پایهٔ دیلیکس در دسترس است.'
            : '${c.providerCount} مرکز پاسخ دادند.';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'مقایسهٔ نرخ ناموفق بود: $e';
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
            : '${r.message} — سطحِ تخفیفِ عدم‌خسارت: ${r.bonusMalus}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'استعلامِ سوابق ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  Future<void> _submitRequest() async {
    final value = _readValue();
    if (_product == null || value == null) {
      setState(() => _error = 'ابتدا محصول و مبلغِ سرمایه را کامل کنید.');
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
        _notice = 'درخواست ثبت شد — کدِ پیگیری: ${req.ref}'
            '${req.providerName == null ? '' : ' · ${req.providerName}'}';
        _requests = ApiScope.of(context).insuranceRequests();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ثبتِ درخواست ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بیمه')),
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
              return Text('بارگذاریِ محصولاتِ بیمه ممکن نشد.\n${snap.error ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall);
            }
            _product ??= products.first.id;
            final selected =
                products.firstWhere((p) => p.id == _product, orElse: () => products.first);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('استعلامِ بیمه', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _product,
                  decoration: const InputDecoration(labelText: 'محصولِ بیمه'),
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
                  decoration: InputDecoration(labelText: '${selected.valueLabel} (تومان)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _coverageType,
                  decoration: const InputDecoration(labelText: 'نوعِ پوشش'),
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
                    decoration: const InputDecoration(labelText: 'نوعِ کالا'),
                  ),
                ],
                if (selected.needsRoute) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _originCtrl,
                    decoration: const InputDecoration(labelText: 'مبدأ'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _destCtrl,
                    decoration: const InputDecoration(labelText: 'مقصد'),
                  ),
                ],
                _inquirySection(selected),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _quoteNow,
                        child: Text(_busy ? 'در حال…' : 'استعلامِ نرخ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _compareNow,
                        child: const Text('مقایسهٔ مراکز'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submitRequest,
                    child: const Text('ثبتِ درخواست'),
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
                          Text('حقِ بیمه: ${_money(_quote!.premium)}'),
                          if (_quote!.providerName != null)
                            Text('ارائه‌دهنده: ${_quote!.providerName}',
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
        Text('استعلامِ سوابق (اختیاری)',
            style: Theme.of(context).textTheme.titleSmall),
        Text(
          needsPlate
              ? 'با پلاک یا کد ملی، سوابق و سطحِ تخفیف را می‌آوریم.'
              : 'با کد ملی، اطلاعاتِ هویتی را می‌آوریم.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (needsPlate) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _plateCtrl,
            decoration: const InputDecoration(labelText: 'پلاکِ خودرو'),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _nidCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'کد ملی'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _inquiryNow,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('استعلام'),
          ),
        ),
        if (_prefill.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'سوابقِ بازیابی‌شده همراهِ درخواست ثبت می‌شود: '
            '${_prefill.keys.join('، ')}',
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
        Text('مقایسهٔ نرخ — ${c.productLabel} · ${c.coverageLabel}',
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
                Expanded(child: Text(o.providerName ?? 'نرخِ پایهٔ دیلیکس')),
                if (o.best)
                  const Chip(
                    label: Text('ارزان‌ترین'),
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
                const Text('درخواست‌های من', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (reqs.isEmpty)
                  Text('هنوز درخواستی ثبت نشده.',
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
                          Text('حقِ بیمه: ${_money(r.premium)}',
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
