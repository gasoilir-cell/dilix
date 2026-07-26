import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// کارمزدِ بیمه — یک صفحه با دو حالت:
///
/// * [providerId] = null → دیدِ ادمین: جمع‌بندیِ همهٔ مراکز + تسویهٔ دسته‌ای
///   (`/insurance/admin/commissions/*`).
/// * [providerId] پر → صورت‌حسابِ همان مرکز برای مالکش
///   (`/insurance/provider/{id}/statement` و `/commissions`).
class InsuranceCommissionsScreen extends StatefulWidget {
  const InsuranceCommissionsScreen({super.key, this.providerId, this.title});

  final String? providerId;
  final String? title;

  @override
  State<InsuranceCommissionsScreen> createState() =>
      _InsuranceCommissionsScreenState();
}

class _InsuranceCommissionsScreenState
    extends State<InsuranceCommissionsScreen> {
  List<InsuranceCommissionSummary>? _summaries;
  List<InsuranceCommission> _rows = const [];
  String? _error;
  bool _busy = false;

  bool get _isAdmin => widget.providerId == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_summaries == null && _error == null) _load();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    try {
      if (_isAdmin) {
        final s = await api.adminCommissionsSummary();
        final rows = await api.adminCommissions();
        if (!mounted) return;
        setState(() {
          _summaries = s;
          _rows = rows;
          _error = null;
        });
      } else {
        final s = await api.providerStatement(widget.providerId!);
        final rows = await api.providerCommissions(widget.providerId!);
        if (!mounted) return;
        setState(() {
          _summaries = [s];
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _settleAll(InsuranceCommissionSummary s) async {
    final pid = s.providerId;
    if (pid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسویهٔ کارمزد'),
        content: Text(
          '${_money(s.accruedCommission)} کارمزدِ تسویه‌نشدهٔ '
          '«${s.providerName ?? 'این مرکز'}» تسویه‌شده علامت می‌خورد.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تسویه')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final (count, amount) =
          await ApiScope.of(context).settleProviderCommissions(pid);
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$count ردیف · ${_money(amount)} تسویه شد.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تسویه ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settleOne(InsuranceCommission c) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await ApiScope.of(context).settleCommission(c.id);
      if (!mounted) return;
      setState(() {
        _rows = [for (final x in _rows) x.id == c.id ? updated : x];
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('تسویه ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(int toman) => '$toman تومان';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'کارمزدِ بیمه')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!.contains('403')
                ? 'دسترسیِ لازم برای دیدنِ این صورت‌حساب را ندارید.'
                : 'بارگذاری ممکن نشد.\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final summaries = _summaries;
    if (summaries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (summaries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('هنوز کارمزدی ثبت نشده است.'),
            )
          else
            for (final s in summaries) _summaryCard(s),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('ردیف‌های کارمزد',
                style: Theme.of(context).textTheme.titleSmall),
            for (final c in _rows) _rowTile(c),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(InsuranceCommissionSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.providerName ?? 'مجموع',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${s.policies} بیمه‌نامه · حقِ بیمه ${_money(s.totalPremium)}'),
            Text('کارمزدِ کل: ${_money(s.totalCommission)}'),
            Text('تسویه‌نشده: ${_money(s.accruedCommission)}'),
            Text('تسویه‌شده: ${_money(s.settledCommission)}'),
            if (_isAdmin && s.accruedCommission > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : () => _settleAll(s),
                  child: const Text('تسویهٔ همه'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowTile(InsuranceCommission c) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(c.requestRef ?? c.product ?? c.id),
      subtitle: Text(
        '${_money(c.commissionAmount)} از ${_money(c.premium)}'
        ' (${c.commissionRate}٪) · ${c.isSettled ? 'تسویه‌شده' : 'تسویه‌نشده'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: _isAdmin && !c.isSettled
          ? TextButton(
              onPressed: _busy ? null : () => _settleOne(c),
              child: const Text('تسویه'),
            )
          : null,
    );
  }
}
