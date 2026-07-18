import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../earth/earth_screen.dart';
import '../services/services_screen.dart';
import '../wallet/wallet_screen.dart';

/// داشبوردِ نقش‌محور — parity با `app/dashboard/page.tsx` وب:
/// سلامِ زمان‌محور + هویت/نقش + کیفِ پاداش + پنل‌های میان‌برِ مخصوصِ نقش
/// + میان‌برِ کره و همهٔ خدمات.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // برچسبِ فارسیِ نقش‌ها — منطبق با ROLE_LABELS صفحهٔ وب.
  static const _roleLabels = <String, String>{
    'individual': 'کاربر',
    'driver': 'راننده',
    'cargo_owner': 'صاحبِ بار',
    'freelancer': 'فریلنسر',
  };

  // پنل‌های میان‌برِ مخصوصِ نقش — منطبق با PANELS_BY_ROLE صفحهٔ وب.
  // (title, subtitle, هدف). هدف: 'freight' → FreightScreen، 'services' → ServicesScreen.
  static const _panelsByRole = <String, List<(String, String, String)>>{
    'driver': [
      ('پنلِ راننده', 'بارهای موجود، ثبتِ پیشنهاد و سفرهای فعال', 'freight'),
    ],
    'cargo_owner': [
      ('پنلِ صاحبِ بار', 'ثبتِ بار، پذیرشِ پیشنهاد و پیگیریِ محموله', 'freight'),
    ],
    'freelancer': [
      ('پنلِ فریلنسر', 'ارائهٔ خدمات و جذبِ مشتری', 'services'),
    ],
  };

  bool _loading = true;
  Identity? _me;
  RewardWallet? _wallet;
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
    final api = ApiScope.of(context);
    try {
      final me = await api.me();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'بارگذاریِ حساب ممکن نشد.');
    }
    try {
      final wallet = await api.rewardWallet();
      if (!mounted) return;
      setState(() => _wallet = wallet);
    } catch (_) {
      // کیفِ پاداش اختیاری است؛ خطایش داشبورد را متوقف نمی‌کند.
    }
    if (mounted) setState(() => _loading = false);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'شب بخیر';
    if (h < 12) return 'صبح بخیر';
    if (h < 17) return 'ظهر بخیر';
    if (h < 21) return 'عصر بخیر';
    return 'شب بخیر';
  }

  void _openTarget(String target) {
    final Widget screen = target == 'freight' ? const FreightScreen() : const ServicesScreen();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final role = _me?.entityType ?? 'individual';
    final panels = _panelsByRole[role] ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('نمای کلی'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تازه‌سازی',
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
                      child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
                    ),
                  _greetingCard(role),
                  _walletTile(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('خدماتِ من', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final p in panels)
                    _tile(Icons.dashboard_customize_outlined, p.$1, p.$2, () => _openTarget(p.$3)),
                  _tile(
                    Icons.public,
                    'کرهٔ زمین',
                    'اکتشافِ جهانیِ افراد و کسب‌وکارها روی نقشهٔ سه‌بعدی',
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EarthScreen()),
                    ),
                  ),
                  _tile(
                    Icons.grid_view,
                    'همهٔ خدمات',
                    'حمل‌ونقل، بیمه، بازار، ارتباطات و بیشتر',
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServicesScreen()),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _greetingCard(String role) {
    final name = _me?.displayName ?? 'کاربرِ دیلیکس';
    final earthId = _me?.earthId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_greeting()}،', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text('$name 👋', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(_roleLabels[role] ?? 'کاربر'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (earthId != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Earth ID', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    '${earthId.length > 12 ? earthId.substring(0, 12) : earthId}…',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _walletTile() {
    final balances = _wallet?.balances ?? const [];
    final String subtitle;
    if (balances.isNotEmpty) {
      final parts = balances
          .map((b) => '${(b.amountMinor / 100).toStringAsFixed(2)} ${b.currency}')
          .join(' · ');
      final pending = (_wallet?.pendingCount ?? 0) > 0 ? ' · ${_wallet!.pendingCount} در انتظار' : '';
      subtitle = '$parts$pending';
    } else {
      subtitle = 'مالی، escrow و پرداخت‌ها';
    }
    return _tile(
      Icons.account_balance_wallet_outlined,
      'کیفِ پول',
      subtitle,
      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
