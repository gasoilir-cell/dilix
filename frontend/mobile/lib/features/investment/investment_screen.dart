import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// صفحهٔ سرمایه‌گذاری: استعلامِ NAVِ صندوق، خریدِ واحد، و فهرستِ موقعیت‌ها.
/// معادلِ صفحهٔ وبِ `app/investment/page.tsx`. مبلغِ ورودی به تومان است و
/// به کوچک‌ترین واحدِ IRR (×۱۰) تبدیل می‌شود.
class InvestmentScreen extends StatefulWidget {
  const InvestmentScreen({super.key});

  @override
  State<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<InvestmentScreen> {
  final _fundCtrl = TextEditingController(text: 'DILIX_GROWTH');
  final _amountCtrl = TextEditingController();
  NavQuote? _nav;
  List<InvestmentPosition> _positions = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _fundCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final positions = await ApiScope.of(context).investmentPositions();
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ موقعیت‌ها ممکن نشد: $e';
        _loading = false;
      });
    }
  }

  Future<void> _fetchNav() async {
    final fund = _fundCtrl.text.trim();
    if (fund.isEmpty) {
      setState(() => _error = 'کدِ صندوق را وارد کنید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final nav = await ApiScope.of(context).investmentNav(fund);
      if (!mounted) return;
      setState(() {
        _nav = nav;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'استعلامِ NAV ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  Future<void> _buy() async {
    final fund = _fundCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (fund.isEmpty) {
      setState(() => _error = 'کدِ صندوق را وارد کنید.');
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
      final position = await ApiScope.of(context).buyFund(
        fundCode: fund,
        amountMinor: (amount * 10).round(),
      );
      if (!mounted) return;
      setState(() {
        _positions = [
          position,
          for (final p in _positions)
            if (p.id != position.id) p,
        ];
        _notice = 'خریدِ ${position.units} واحد از ${position.fundCode} ثبت شد.';
        _amountCtrl.clear();
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خرید ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  String _navText(NavQuote nav) => '${(nav.navMinor / 10).round()} تومان به‌ازای هر واحد';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سرمایه‌گذاری'),
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
                  _buyCard(),
                  const SizedBox(height: 8),
                  _positionsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('خریدِ واحدِ صندوق', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _fundCtrl,
              decoration: const InputDecoration(labelText: 'کدِ صندوق'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
            ),
            if (_nav != null) ...[
              const SizedBox(height: 8),
              Text(
                'NAVِ ${_nav!.fundCode}: ${_navText(_nav!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _fetchNav,
                    child: const Text('استعلامِ NAV'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _buy,
                    child: Text(_busy ? 'در حال…' : 'خرید'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _positionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('موقعیت‌های من', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_positions.isEmpty)
              Text(
                'هنوز موقعیتی ندارید. با خریدِ واحد، اولین موقعیت‌تان ساخته می‌شود.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ..._positions.map(
                (p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.fundCode, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${p.units} واحد', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      Chip(label: Text(p.status)),
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
