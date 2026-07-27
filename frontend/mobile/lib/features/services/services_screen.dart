import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../bills/bills_screen.dart';
import '../business/business_screen.dart';
import '../discovery/discovery_screen.dart';
import '../freight/cargo_detail_screen.dart';
import '../gamification/gamification_screen.dart';
import '../insurance/insurance_screen.dart';
import '../investment/investment_screen.dart';
import '../live/live_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../membership/membership_screen.dart';
import '../notifications/notifications_screen.dart';
import '../provider/provider_screen.dart';
import '../reputation/reputation_screen.dart';
import '../reels/reels_screen.dart';
import '../shop/shop_screen.dart';
import '../stories/stories_screen.dart';
import '../telecom/telecom_screen.dart';
import '../wallet/wallet_screen.dart';

import '../../core/l10n.dart';
/// هابِ verticalها (سند ۷ §۲): حمل‌ونقل، بیمه، ارتباطات، بازارگاه.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <_Service>[
      _Service(Icons.movie_creation_outlined, tr('ریلز'), tr('ویدیوهای کوتاه'), const ReelsScreen()),
      _Service(Icons.auto_stories_outlined, tr('داستان‌ها'), tr('داستانِ ۲۴ساعته'), const StoriesScreen()),
      _Service(Icons.podcasts, tr('پخشِ زنده'), tr('تماشا یا شروعِ پخش'), const LiveScreen()),
      _Service(Icons.local_shipping_outlined, tr('حمل‌ونقل'), tr('اسنپِ بار'), const FreightScreen()),
      _Service(Icons.shield_outlined, tr('بیمه'), tr('استعلام و صدور'), const InsuranceScreen()),
      _Service(Icons.signal_cellular_alt, tr('ارتباطات'), tr('اینترنت و eSIM'), const TelecomScreen()),
      _Service(Icons.storefront_outlined, tr('بازارگاه'), tr('خدمات و فریلنسری'), const MarketplaceScreen()),
      _Service(Icons.travel_explore, tr('کشفِ اطراف'), tr('افراد و کسب‌وکارِ نزدیک'), const DiscoveryScreen()),
      _Service(Icons.trending_up, tr('سرمایه‌گذاری'), tr('صندوق و NAV'), const InvestmentScreen()),
      _Service(Icons.workspace_premium_outlined, tr('عضویت'), tr('پلن، نشان و اعتبار'), const MembershipScreen()),
      _Service(Icons.emoji_events_outlined, tr('دستاوردها'), tr('امتیاز و نشان‌ها'), const GamificationScreen()),
      _Service(Icons.verified_outlined, tr('اعتبار'), tr('امتیازِ اعتماد و نظرها'), const ReputationScreen()),
      _Service(Icons.hub_outlined, tr('ارائه‌دهنده'), tr('KYB، API، sandbox و کلید'), const ProviderScreen()),
      _Service(Icons.receipt_long_outlined, tr('قبوض'), tr('آب، برق، گاز و عوارض'), const BillsScreen()),
      _Service(Icons.insights_outlined, tr('حسابِ کسب‌وکار'), tr('آمارِ نمایه و اشتراک'), const BusinessScreen()),
      _Service(Icons.shopping_bag_outlined, tr('فروشگاه'), tr('خرید و فروش با وجهِ امانی'), const ShopScreen()),
      _Service(Icons.account_balance_wallet_outlined, tr('کیف پول'), tr('پاداش و پرداختِ امن'), const WalletScreen()),
      _Service(Icons.notifications_outlined, tr('اعلان‌ها'), tr('رویدادها و پیام‌ها'), const NotificationsScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('خدمات'))),
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
  final List<CargoPost> _cargo = [];
  bool _loading = true;
  bool _showForm = false;
  bool _submitting = false;
  String? _error;

  /// false = بارهای باز (دیدِ راننده)، true = بارهای خودم (دیدِ صاحبِ بار).
  bool _mine = false;

  /// کاتالوگِ ناوگان از سرور؛ اگر نیاید فرم بدونِ این فیلد کار می‌کند چون
  /// `vehicle_type` در سرور اختیاری است.
  List<VehicleType> _vehicles = const [];
  String? _vehicle;

  final _titleCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

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
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiScope.of(context);
      final cargo = await api.listCargo(mine: _mine);
      var vehicles = _vehicles;
      if (vehicles.isEmpty) {
        try {
          vehicles = await api.vehicleTypes();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _cargo
          ..clear()
          ..addAll(cargo);
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ فهرستِ بار ممکن نشد.\n{0}', [e]);
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(CargoPost c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CargoDetailScreen(postId: c.id)),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final origin = _originCtrl.text.trim();
    final dest = _destCtrl.text.trim();
    final weightKg = double.tryParse(_weightCtrl.text.trim());
    final price = int.tryParse(_priceCtrl.text.trim().replaceAll(tr('،'), ''));
    if (title.isEmpty || origin.isEmpty || dest.isEmpty) {
      setState(() => _error = tr('عنوان، مبدأ و مقصد را وارد کنید.'));
      return;
    }
    if (weightKg == null || weightKg <= 0) {
      setState(() => _error = tr('وزنِ معتبر (کیلوگرم) وارد کنید.'));
      return;
    }
    // سرور `price > 0` را الزامی می‌کند و همین مبلغ هنگامِ پذیرشِ راننده از
    // کیفِ صاحبِ بار امانی می‌شود.
    if (price == null || price <= 0) {
      setState(() => _error = tr('کرایهٔ پیشنهادی را وارد کنید.'));
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
        budgetMinor: price,
        vehicleType: _vehicle,
      );
      if (!mounted) return;
      setState(() {
        // بارِ تازه `open` است؛ در دیدِ «بارهای من» هم دیده می‌شود.
        _cargo.insert(0, created);
        _showForm = false;
        _submitting = false;
        _titleCtrl.clear();
        _originCtrl.clear();
        _destCtrl.clear();
        _weightCtrl.clear();
        _priceCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('ثبتِ بار ناموفق بود. ابتدا وارد شوید.');
        _submitting = false;
      });
    }
  }

  String _formatWeight(int grams) {
    final kg = grams / 1000;
    final text = kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1);
    return tr('{0} کیلوگرم', [text]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('اسنپِ بار')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: tr('تازه‌سازی'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        icon: Icon(_showForm ? Icons.close : Icons.add),
        label: Text(_showForm ? tr('بستن') : tr('ثبتِ بار')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    tr('ثبتِ بار، تطبیقِ راننده، بارنامه و ردیابیِ زنده'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(tr('بارهای باز'))),
                      ButtonSegment(value: true, label: Text(tr('بارهای من'))),
                    ],
                    selected: {_mine},
                    onSelectionChanged: (s) {
                      setState(() => _mine = s.first);
                      _load();
                    },
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
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(tr('باری برای نمایش نیست.'), textAlign: TextAlign.center),
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
              decoration: InputDecoration(labelText: tr('عنوانِ بار')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _originCtrl,
              decoration: InputDecoration(labelText: tr('مبدأ')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _destCtrl,
              decoration: InputDecoration(labelText: tr('مقصد')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('وزن (کیلوگرم)')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('کرایهٔ پیشنهادی (تومان)'),
                helperText: tr('هنگامِ پذیرشِ راننده از کیفِ شما امانی می‌شود'),
              ),
            ),
            if (_vehicles.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _vehicle,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('نوعِ ناوگان (اختیاری)'),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(tr('فرقی نمی‌کند')),
                  ),
                  for (final v in _vehicles)
                    DropdownMenuItem<String>(
                      value: v.code,
                      child: Text(v.maxWeightKg == null
                          ? v.nameFa
                          : tr('{0} — تا {1} کیلوگرم', [v.nameFa, v.maxWeightKg!.round()])),
                    ),
                ],
                onChanged: (v) => setState(() => _vehicle = v),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? tr('در حال…') : tr('ثبت')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cargoCard(CargoPost c) {
    return Card(
      child: InkWell(
        onTap: () => _openDetail(c),
        borderRadius: BorderRadius.circular(12),
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
                  Chip(label: Text(cargoStatusLabels[c.status] ?? c.status)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${c.origin} ← ${c.destination} · ${_formatWeight(c.weightGrams)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (c.offersCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr('{0} پیشنهادِ در انتظار', [c.offersCount]),
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
