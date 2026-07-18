import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// بیمه: استعلامِ نرخ (ساختِ بیمه‌نامهٔ در وضعیتِ استعلام) و صدورِ نهایی.
/// مبلغِ پوششِ ورودی به تومان است و به IRR (×۱۰) تبدیل می‌شود.
class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  // برچسبِ فارسیِ وضعیتِ بیمه‌نامه — منطبق با STATUS_LABEL صفحهٔ وب.
  static const _statusLabels = <String, String>{
    'quoted': 'استعلام‌شده',
    'issued': 'صادرشده',
    'active': 'فعال',
    'claimed': 'خسارت',
    'expired': 'منقضی',
    'cancelled': 'لغوشده',
  };

  final _productCtrl = TextEditingController(text: 'motor_third_party');
  final _coverageCtrl = TextEditingController();
  final List<InsurancePolicy> _policies = [];
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _productCtrl.dispose();
    _coverageCtrl.dispose();
    super.dispose();
  }

  String _formatMoney(int amountMinor, String currency) {
    final cur = currency.toUpperCase();
    if (cur == 'IRR') return '${(amountMinor / 10).round()} تومان';
    return '${(amountMinor / 100).toStringAsFixed(2)} $cur';
  }

  Future<void> _quote() async {
    final product = _productCtrl.text.trim();
    final coverage = double.tryParse(_coverageCtrl.text.trim());
    if (product.isEmpty) {
      setState(() => _error = 'کدِ محصولِ بیمه را وارد کنید.');
      return;
    }
    if (coverage == null || coverage <= 0) {
      setState(() => _error = 'مبلغِ پوششِ معتبر (تومان) وارد کنید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final policy = await ApiScope.of(context).createInsuranceQuote(
        productCode: product,
        coverageMinor: (coverage * 10).round(),
      );
      if (!mounted) return;
      setState(() {
        _policies.insert(0, policy);
        _notice = 'استعلام ثبت شد. حقِ بیمه: ${_formatMoney(policy.premiumMinor, policy.currency)}';
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

  Future<void> _issue(InsurancePolicy policy) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final issued = await ApiScope.of(context).issuePolicy(policy.id);
      if (!mounted) return;
      setState(() {
        final i = _policies.indexWhere((p) => p.id == policy.id);
        if (i >= 0) _policies[i] = issued;
        _notice = 'بیمه‌نامه صادر شد.';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'صدور ناموفق بود: $e';
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
          if (_policies.isNotEmpty) _policiesCard(),
        ],
      ),
    );
  }

  Widget _quoteCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('استعلامِ بیمه', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _productCtrl,
              decoration: const InputDecoration(labelText: 'کدِ محصول (مثلاً motor_third_party)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _coverageCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'مبلغِ پوشش (تومان)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _quote,
                child: Text(_busy ? 'در حال…' : 'استعلام'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _policiesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('بیمه‌نامه‌های همین نشست', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._policies.map(
              (p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(p.productCode, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Chip(label: Text(_statusLabels[p.status] ?? p.status)),
                      ],
                    ),
                    Text(
                      'پوشش: ${_formatMoney(p.coverageMinor, p.currency)} · حقِ بیمه: ${_formatMoney(p.premiumMinor, p.currency)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (p.status == 'quoted')
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _busy ? null : () => _issue(p),
                          child: const Text('صدورِ بیمه‌نامه'),
                        ),
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
