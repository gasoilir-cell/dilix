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
      ReferralNetwork? network;
      try {
        network = await api.referralNetwork();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _link = link;
        _network = network;
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
