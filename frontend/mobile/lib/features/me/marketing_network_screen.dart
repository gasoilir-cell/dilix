import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
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
        _error = tr('بارگذاریِ شبکه ممکن نشد: {0}', [e]);
        _loading = false;
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('{0} کپی شد.', [label]))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('شبکه و درآمد'))),
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
                        Text(tr('سطوحِ شبکه'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ..._network!.levels.map(_levelTile),
                        const SizedBox(height: 16),
                      ],
                      Text(tr('دعوت‌شدگانِ مستقیم'),
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
        _box('$toman', tr('تومان پاداش'), theme.colorScheme.primaryContainer),
        const SizedBox(width: 8),
        _box('$referred', tr('دعوتِ مستقیم'), theme.colorScheme.secondaryContainer),
        const SizedBox(width: 8),
        _box('$network', tr('کلِ شبکه'), theme.colorScheme.tertiaryContainer),
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
            Text(tr('لینکِ دعوت'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (code.isNotEmpty)
              InkWell(
                onTap: () => _copy(tr('کدِ دعوت'), code),
                child: Row(
                  children: [
                    Text(tr('کد: {0}', [code]),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy, size: 14),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _copy(tr('لینکِ دعوت'), link),
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
                        link.isEmpty ? tr('لینکِ دعوت در دسترس نیست') : link,
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
            Text(tr('معرفِ من'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              tr('اگر کسی شما را به دیلیکس دعوت کرده، Earth ID او را ثبت کنید. این کار فقط یک‌بار ممکن است.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _applyReferral,
                icon: const Icon(Icons.person_add_alt),
                label: Text(tr('ثبتِ کدِ معرف')),
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
        title: Text(tr('کدِ معرف')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: tr('مثلاً EID-XXXXXX')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('انصراف'))),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: Text(tr('ثبت')),
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
          SnackBar(content: Text(tr('معرفِ شما ثبت شد: {0}', [name]))));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('ثبت نشد: {0}', [e]))));
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
            Text(tr('کمیسیون‌های من'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (ledger.totals.isEmpty)
              Text(tr('هنوز کمیسیونی ثبت نشده است.'), style: theme.textTheme.bodySmall)
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
                              tr('سطحِ {0} · ٪{1}{2}', [c.level, c.ratePercent.toStringAsFixed(
                                c.rateBps % 100 == 0 ? 0 : 1,
                              ), c.sourceType != null ? ' · ${c.sourceType}' : '']),
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
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(tr('،'));
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _levelTile(ReferralLevel l) {
    final rate = (l.rateBps / 100).toStringAsFixed(l.rateBps % 100 == 0 ? 0 : 1);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${l.level}')),
        title: Text(tr('سطحِ {0}', [l.level])),
        subtitle: Text(tr('نرخِ پاداش: ٪{0}', [rate])),
        trailing: Text(tr('{0} نفر', [l.count]),
            style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Widget _directList() {
    final direct = _network?.direct ?? const [];
    if (direct.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(tr('هنوز کسی را مستقیماً دعوت نکرده‌اید.')),
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
              subtitle: m.joinedAt != null ? Text(tr('عضویت: {0}', [m.joinedAt])) : null,
            ),
        ],
      ),
    );
  }
}
