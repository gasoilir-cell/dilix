import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../models/models.dart';

/// شبکه و درآمدِ بازاریابیِ چندسطحی — `GET /api/v1/referral/stats` و
/// `GET /api/v1/referral/network`. دعوت‌شدگانِ مستقیم، سطوح و پاداشِ کسب‌شده.
class MarketingNetworkScreen extends StatefulWidget {
  const MarketingNetworkScreen({super.key});

  @override
  State<MarketingNetworkScreen> createState() => _MarketingNetworkScreenState();
}

class _MarketingNetworkScreenState extends State<MarketingNetworkScreen> {
  ReferralLink? _link;
  ReferralNetwork? _network;
  CommissionLedger? _ledger;
  bool _loading = true;
  String? _error;

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
    try {
      final api = ApiScope.of(context);
      final link = await api.referralLink();
      // شبکه و لِجِر تکمیلی‌اند؛ نبودشان نباید کلِ صفحه را خطا کند.
      ReferralNetwork? network;
      try {
        network = await api.referralNetwork();
      } catch (_) {}
      CommissionLedger? ledger;
      try {
        ledger = await api.referralCommissions();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _link = link;
        _network = network;
        _ledger = ledger;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ شبکه ممکن نشد: $e';
        _loading = false;
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label کپی شد.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('شبکه و درآمد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summary(),
                      const SizedBox(height: 16),
                      _inviteCard(),
                      const SizedBox(height: 16),
                      _applyCard(),
                      const SizedBox(height: 16),
                      _commissionsCard(),
                      const SizedBox(height: 16),
                      if (_network != null && _network!.levels.isNotEmpty) ...[
                        Text('سطوحِ شبکه',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ..._network!.levels.map(_levelTile),
                        const SizedBox(height: 16),
                      ],
                      Text('دعوت‌شدگانِ مستقیم',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _directList(),
                    ],
                  ),
                ),
    );
  }

  Widget _summary() {
    final theme = Theme.of(context);
    final toman = _link?.totalRewardToman ?? 0;
    final referred = _link?.totalReferred ?? 0;
    final network = _link?.totalNetwork ?? _network?.totalNetwork ?? 0;
    return Row(
      children: [
        _box('$toman', 'تومان پاداش', theme.colorScheme.primaryContainer),
        const SizedBox(width: 8),
        _box('$referred', 'دعوتِ مستقیم', theme.colorScheme.secondaryContainer),
        const SizedBox(width: 8),
        _box('$network', 'کلِ شبکه', theme.colorScheme.tertiaryContainer),
      ],
    );
  }

  Widget _box(String value, String label, Color bg) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(label,
                style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _inviteCard() {
    final theme = Theme.of(context);
    final link = _link?.url ?? '';
    final code = _link?.code ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لینکِ دعوت',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (code.isNotEmpty)
              InkWell(
                onTap: () => _copy('کدِ دعوت', code),
                child: Row(
                  children: [
                    Text('کد: $code',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy, size: 14),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _copy('لینکِ دعوت', link),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link.isEmpty ? 'لینکِ دعوت در دسترس نیست' : link,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ثبتِ معرف. فقط یک‌بار در عمرِ حساب ممکن است و سرور خودش حلقه را رد می‌کند،
  /// پس اینجا فقط خطای سرور را نشان می‌دهیم.
  Widget _applyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معرفِ من', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'اگر کسی شما را به دیلیکس دعوت کرده، Earth ID او را ثبت کنید. '
              'این کار فقط یک‌بار ممکن است.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _applyReferral,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('ثبتِ کدِ معرف'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyReferral() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('کدِ معرف'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'مثلاً EID-XXXXXX'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = await ApiScope.of(context).applyReferral(code);
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text('معرفِ شما ثبت شد: $name')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('ثبت نشد: $e')));
    }
  }

  Widget _commissionsCard() {
    final ledger = _ledger;
    if (ledger == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('کمیسیون‌های من',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (ledger.totals.isEmpty)
              Text('هنوز کمیسیونی ثبت نشده است.', style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in ledger.totals.entries)
                    Chip(label: Text('${_money(e.value)} ${e.key}')),
                ],
              ),
            if (ledger.items.isNotEmpty) ...[
              const Divider(height: 24),
              // فقط ۱۰ ردیفِ آخر؛ سرور هم بیش از ۱۰۰ ردیف نمی‌دهد.
              for (final c in ledger.items.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 14, child: Text('${c.level}')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_money(c.amount)} ${c.currency}'),
                            Text(
                              'سطحِ ${c.level} · ٪${c.ratePercent.toStringAsFixed(
                                c.rateBps % 100 == 0 ? 0 : 1,
                              )}'
                              '${c.sourceType != null ? ' · ${c.sourceType}' : ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _money(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('،');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _levelTile(ReferralLevel l) {
    final rate = (l.rateBps / 100).toStringAsFixed(l.rateBps % 100 == 0 ? 0 : 1);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${l.level}')),
        title: Text('سطحِ ${l.level}'),
        subtitle: Text('نرخِ پاداش: ٪$rate'),
        trailing: Text('${l.count} نفر',
            style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Widget _directList() {
    final direct = _network?.direct ?? const [];
    if (direct.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('هنوز کسی را مستقیماً دعوت نکرده‌اید.'),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final m in direct)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(m.name.isEmpty ? m.earthId : m.name),
              subtitle: m.joinedAt != null ? Text('عضویت: ${m.joinedAt}') : null,
            ),
        ],
      ),
    );
  }
}
