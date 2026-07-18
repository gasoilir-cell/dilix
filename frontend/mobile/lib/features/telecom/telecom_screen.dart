import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// ارتباطات: شارژ/بستهٔ اینترنت (top-up) و فعال‌سازیِ eSIM.
/// دو تبِ ساده روی endpointهایِ `/v1/telecom`.
class TelecomScreen extends StatefulWidget {
  const TelecomScreen({super.key});

  @override
  State<TelecomScreen> createState() => _TelecomScreenState();
}

class _TelecomScreenState extends State<TelecomScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  final _msisdnCtrl = TextEditingController();
  final _productCtrl = TextEditingController(text: 'data_5gb');
  final _amountCtrl = TextEditingController();
  final _iccidCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'IR');

  final List<TopUp> _topUps = [];
  final List<Esim> _esims = [];
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _tab.dispose();
    _msisdnCtrl.dispose();
    _productCtrl.dispose();
    _amountCtrl.dispose();
    _iccidCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  String _formatMoney(int amountMinor, String currency) {
    final cur = currency.toUpperCase();
    if (cur == 'IRR') return '${(amountMinor / 10).round()} تومان';
    return '${(amountMinor / 100).toStringAsFixed(2)} $cur';
  }

  Future<void> _topUp() async {
    final msisdn = _msisdnCtrl.text.trim();
    final product = _productCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (msisdn.length < 10) {
      setState(() => _error = 'شمارهٔ موبایل معتبر (حداقل ۱۰ رقم) وارد کنید.');
      return;
    }
    if (product.isEmpty) {
      setState(() => _error = 'کدِ محصول را وارد کنید.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'مبلغِ معتبر (تومان) وارد کنید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await ApiScope.of(context).telecomTopUp(
        msisdn: msisdn,
        productCode: product,
        amountMinor: (amount * 10).round(),
      );
      if (!mounted) return;
      setState(() {
        _topUps.insert(0, result);
        _notice = 'شارژ ثبت شد (${result.status}).';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'شارژ ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  Future<void> _activateEsim() async {
    final iccid = _iccidCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    if (iccid.length < 18) {
      setState(() => _error = 'ICCID معتبر (حداقل ۱۸ رقم) وارد کنید.');
      return;
    }
    if (country.length < 2) {
      setState(() => _error = 'کدِ کشور را وارد کنید (مثلاً IR).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await ApiScope.of(context).activateEsim(
        iccid: iccid,
        countryCode: country,
      );
      if (!mounted) return;
      setState(() {
        _esims.insert(0, result);
        _notice = 'eSIM فعال شد (${result.status}).';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'فعال‌سازیِ eSIM ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ارتباطات'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'شارژ / اینترنت'),
            Tab(text: 'eSIM'),
          ],
        ),
      ),
      body: Column(
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
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _topUpTab(),
                _esimTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topUpTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _msisdnCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'شمارهٔ موبایل'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _productCtrl,
                  decoration: const InputDecoration(labelText: 'کدِ محصول (مثلاً data_5gb)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _topUp,
                    child: Text(_busy ? 'در حال…' : 'ثبتِ شارژ'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_topUps.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('شارژهای همین نشست', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._topUps.map(
                    (t) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.msisdn, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${t.productCode} · ${_formatMoney(t.amountMinor, t.currency)}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                          Chip(label: Text(t.status)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _esimTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _iccidCtrl,
                  decoration: const InputDecoration(labelText: 'ICCID (۱۸ تا ۲۲ رقم)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _countryCtrl,
                  decoration: const InputDecoration(labelText: 'کدِ کشور (مثلاً IR)'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _activateEsim,
                    child: Text(_busy ? 'در حال…' : 'فعال‌سازیِ eSIM'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_esims.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('eSIMهای همین نشست', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._esims.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.iccid, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(e.countryCode, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                          Chip(label: Text(e.status)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
