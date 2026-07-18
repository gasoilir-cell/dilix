import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../discovery/discovery_screen.dart';
import '../insurance/insurance_screen.dart';
import '../investment/investment_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../membership/membership_screen.dart';
import '../notifications/notifications_screen.dart';
import '../provider/provider_screen.dart';
import '../reels/reels_screen.dart';
import '../stories/stories_screen.dart';
import '../telecom/telecom_screen.dart';
import '../wallet/wallet_screen.dart';

/// هابِ verticalها (سند ۷ §۲): حمل‌ونقل، بیمه، ارتباطات، بازارگاه.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <_Service>[
      _Service(Icons.movie_creation_outlined, 'ریلز', 'ویدیوهای کوتاه', const ReelsScreen()),
      _Service(Icons.auto_stories_outlined, 'داستان‌ها', 'داستانِ ۲۴ساعته', const StoriesScreen()),
      _Service(Icons.local_shipping_outlined, 'حمل‌ونقل', 'اسنپِ بار', const FreightScreen()),
      _Service(Icons.shield_outlined, 'بیمه', 'استعلام و صدور', const InsuranceScreen()),
      _Service(Icons.signal_cellular_alt, 'ارتباطات', 'اینترنت و eSIM', const TelecomScreen()),
      _Service(Icons.storefront_outlined, 'بازارگاه', 'خدمات و فریلنسری', const MarketplaceScreen()),
      _Service(Icons.travel_explore, 'کشفِ اطراف', 'افراد و کسب‌وکارِ نزدیک', const DiscoveryScreen()),
      _Service(Icons.trending_up, 'سرمایه‌گذاری', 'صندوق و NAV', const InvestmentScreen()),
      _Service(Icons.workspace_premium_outlined, 'عضویت', 'پلن، نشان و اعتبار', const MembershipScreen()),
      _Service(Icons.hub_outlined, 'ارائه‌دهنده', 'KYB، API، sandbox و کلید', const ProviderScreen()),
      _Service(Icons.account_balance_wallet_outlined, 'کیف پول', 'پاداش و پرداختِ امن', const WalletScreen()),
      _Service(Icons.notifications_outlined, 'اعلان‌ها', 'رویدادها و پیام‌ها', const NotificationsScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('خدمات')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(12),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: tiles
            .map((s) => Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: s.screen == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => s.screen!),
                            ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(s.icon, size: 32),
                          const SizedBox(height: 8),
                          Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(s.desc, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Service {
  _Service(this.icon, this.title, this.desc, this.screen);
  final IconData icon;
  final String title;
  final String desc;
  final Widget? screen;
}

/// فهرست + ثبتِ بار (اسنپِ بار) — سند ۷ §۵. معادلِ صفحهٔ وبِ
/// `app/services/freight/page.tsx`: نمایشِ فهرست + فرمِ ثبتِ بار.
class FreightScreen extends StatefulWidget {
  const FreightScreen({super.key});

  @override
  State<FreightScreen> createState() => _FreightScreenState();
}

class _FreightScreenState extends State<FreightScreen> {
  // برچسبِ فارسیِ وضعیت‌ها — منطبق با STATUS_LABEL صفحهٔ وب.
  static const _statusLabels = <String, String>{
    'open': 'باز',
    'matched': 'تطبیق‌یافته',
    'in_transit': 'در مسیر',
    'delivered': 'تحویل‌شده',
    'settled': 'تسویه‌شده',
    'cancelled': 'لغوشده',
  };

  final List<CargoPost> _cargo = [];
  bool _loading = true;
  bool _showForm = false;
  bool _submitting = false;
  String? _error;

  final _titleCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cargo = await ApiScope.of(context).listCargo();
      if (!mounted) return;
      setState(() {
        _cargo
          ..clear()
          ..addAll(cargo);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ فهرستِ بار ممکن نشد.\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final origin = _originCtrl.text.trim();
    final dest = _destCtrl.text.trim();
    final weightKg = double.tryParse(_weightCtrl.text.trim());
    if (title.isEmpty || origin.isEmpty || dest.isEmpty) {
      setState(() => _error = 'عنوان، مبدأ و مقصد را وارد کنید.');
      return;
    }
    if (weightKg == null || weightKg <= 0) {
      setState(() => _error = 'وزنِ معتبر (کیلوگرم) وارد کنید.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await ApiScope.of(context).createCargo(
        title: title,
        origin: origin,
        destination: dest,
        weightGrams: (weightKg * 1000).round(),
      );
      if (!mounted) return;
      setState(() {
        _cargo.insert(0, created);
        _showForm = false;
        _submitting = false;
        _titleCtrl.clear();
        _originCtrl.clear();
        _destCtrl.clear();
        _weightCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ثبتِ بار ناموفق بود. ابتدا وارد شوید.';
        _submitting = false;
      });
    }
  }

  String _formatWeight(int grams) {
    final kg = grams / 1000;
    final text = kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1);
    return '$text کیلوگرم';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اسنپِ بار'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تازه‌سازی',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        icon: Icon(_showForm ? Icons.close : Icons.add),
        label: Text(_showForm ? 'بستن' : 'ثبتِ بار'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    'ثبتِ بار، تطبیقِ راننده، بارنامه و ردیابیِ زنده',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_showForm) _formCard(),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_cargo.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('باری برای نمایش نیست.', textAlign: TextAlign.center),
                    )
                  else
                    ..._cargo.map(_cargoCard),
                ],
              ),
            ),
    );
  }

  Widget _formCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'عنوانِ بار'),
            ),
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
            const SizedBox(height: 8),
            TextField(
              controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'وزن (کیلوگرم)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'در حال…' : 'ثبت'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cargoCard(CargoPost c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    c.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(label: Text(_statusLabels[c.status] ?? c.status)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${c.origin} ← ${c.destination} · ${_formatWeight(c.weightGrams)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
