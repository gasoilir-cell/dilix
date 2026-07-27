import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';

/// حسابِ کسب‌وکار/سازنده — معادلِ صفحهٔ وبِ `app/(main)/business/page.tsx`.
///
/// سه بخش: نمایه (ساخت/ویرایش)، آمارِ واقعی، و پلن‌های اشتراکِ پولی.
/// نشانِ تأیید (`verified`) اینجا قابلِ تغییر نیست؛ سرور آن را از سطحِ احرازِ
/// هویت محاسبه می‌کند و هر ویرایشی دوباره بازمحاسبه‌اش می‌کند.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  final _nameCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  final _siteCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  final _tierNameCtrl = TextEditingController();
  final _tierPriceCtrl = TextEditingController();
  final _tierPerksCtrl = TextEditingController();

  String _kind = 'business';
  String _category = 'other';

  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  List<BizCategory> _categories = const [];
  List<BizKind> _kinds = const [];
  BizProfile? _profile;
  BizInsights? _insights;
  List<SubTier> _tiers = const [];
  List<Subscription> _subscribers = const [];
  List<Subscription> _mySubs = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadAll();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _aboutCtrl.dispose();
    _siteCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _tierNameCtrl.dispose();
    _tierPriceCtrl.dispose();
    _tierPerksCtrl.dispose();
    super.dispose();
  }

  /// سرور ریال می‌دهد و کاربرِ ایرانی تومان می‌خواند.
  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  String _date(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  void _fill(BizProfile p) {
    _kind = p.kind;
    _category = p.category;
    _nameCtrl.text = p.displayName;
    _aboutCtrl.text = p.about ?? '';
    _siteCtrl.text = p.website ?? '';
    _phoneCtrl.text = p.contactPhone ?? '';
    _emailCtrl.text = p.contactEmail ?? '';
    _addressCtrl.text = p.address ?? '';
  }

  /// هر بخش مستقل بارگیری می‌شود؛ نبودِ حسابِ کسب‌وکار (۴۰۴) خطا نیست.
  Future<void> _loadAll() async {
    final api = ApiScope.of(context);
    var categories = _categories;
    var kinds = _kinds;
    BizProfile? profile;
    BizInsights? insights;
    var tiers = _tiers;
    var subscribers = _subscribers;
    var mySubs = _mySubs;

    try {
      categories = await api.bizCategories();
    } catch (_) {}
    try {
      kinds = await api.bizKinds();
    } catch (_) {}
    try {
      profile = await api.myBusiness();
    } catch (_) {}
    if (profile != null) {
      try {
        insights = await api.bizInsights();
      } catch (_) {}
    }
    try {
      tiers = await api.myTiers();
    } catch (_) {}
    try {
      subscribers = await api.mySubscribers();
    } catch (_) {}
    try {
      mySubs = await api.mySubscriptions();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _kinds = kinds;
      _profile = profile;
      _insights = insights;
      _tiers = tiers;
      _subscribers = subscribers;
      _mySubs = mySubs;
      if (profile != null) _fill(profile);
    });
  }

  Future<void> _run(Future<void> Function() body, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await body();
    } on ApiException catch (e) {
      // پیامِ سرور دقیق است (مثلِ «برای حسابِ رسمی احرازِ هویتِ کامل لازم است»).
      if (mounted) {
        setState(() => _error = e.detail.isNotEmpty ? e.detail : failure);
      }
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _profileBody() {
    String? v(TextEditingController c) {
      final s = c.text.trim();
      return s.isEmpty ? null : s;
    }

    return {
      'kind': _kind,
      'display_name': _nameCtrl.text.trim(),
      'category': _category,
      'about': v(_aboutCtrl),
      'website': v(_siteCtrl),
      'contact_phone': v(_phoneCtrl),
      'contact_email': v(_emailCtrl),
      'address': v(_addressCtrl),
    };
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().length < 2) {
      setState(() => _error = tr('نامِ نمایشی خیلی کوتاه است.'));
      return;
    }
    final existing = _profile != null;
    await _run(() async {
      final api = ApiScope.of(context);
      final p = existing
          ? await api.updateBusiness(_profileBody())
          : await api.createBusiness(_profileBody());
      if (!mounted) return;
      setState(() {
        _profile = p;
        _fill(p);
        _notice = existing
            ? tr('تغییرات ذخیره شد.')
            : tr('حسابِ کسب‌وکار ساخته شد.');
      });
      await _loadAll();
    }, tr('ذخیرهٔ حسابِ کسب‌وکار ناموفق بود'));
  }

  Future<void> _deleteProfile() async {
    final yes = await _confirm(
      tr('حسابِ کسب‌وکار حذف شود؟'),
      tr('پست‌ها و دنبال‌کننده‌ها دست‌نخورده می‌مانند.'),
    );
    if (!yes) return;
    await _run(() async {
      await ApiScope.of(context).deleteBusiness();
      if (!mounted) return;
      setState(() {
        _profile = null;
        _insights = null;
        _notice = tr('حساب به شخصی برگشت.');
      });
    }, tr('حذفِ حسابِ کسب‌وکار ناموفق بود'));
  }

  Future<void> _addTier() async {
    final name = _tierNameCtrl.text.trim();
    // ورودیِ کاربر تومان است و سرور ریال می‌خواهد.
    final toman = int.tryParse(_tierPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (name.isEmpty || toman == null || toman <= 0) {
      setState(() => _error = tr('نام و قیمتِ پلن را کامل کنید.'));
      return;
    }
    final perks = _tierPerksCtrl.text.trim();
    await _run(() async {
      await ApiScope.of(context).createTier(
        name: name,
        price: toman * 10,
        perks: perks.isEmpty ? null : perks,
      );
      if (!mounted) return;
      _tierNameCtrl.clear();
      _tierPriceCtrl.clear();
      _tierPerksCtrl.clear();
      setState(() => _notice = tr('پلن ساخته شد.'));
      await _loadAll();
    }, tr('ساختِ پلن ناموفق بود'));
  }

  Future<void> _deactivateTier(SubTier t) async {
    final yes = await _confirm(
      tr('پلن «{0}» غیرفعال شود؟', [t.name]),
      tr('مشترکانِ فعلی دست‌نخورده می‌مانند.'),
    );
    if (!yes) return;
    await _run(() async {
      await ApiScope.of(context).deactivateTier(t.id);
      if (!mounted) return;
      setState(() => _notice = tr('پلن غیرفعال شد.'));
      await _loadAll();
    }, tr('غیرفعال‌سازیِ پلن ناموفق بود'));
  }

  Future<void> _cancelSub(Subscription s) async {
    final yes = await _confirm(
      tr('اشتراک لغو شود؟'),
      tr('تا پایانِ دورهٔ پرداخت‌شده فعال می‌ماند و پول برنمی‌گردد.'),
    );
    if (!yes) return;
    await _run(() async {
      await ApiScope.of(context).cancelSubscription(s.id);
      if (!mounted) return;
      setState(() => _notice = tr('اشتراک لغو شد.'));
      await _loadAll();
    }, tr('لغوِ اشتراک ناموفق بود'));
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('تأیید')),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  String _statusLabel(String s) => switch (s) {
        'active' => tr('فعال'),
        'cancelled' => tr('لغوشده'),
        _ => tr('منقضی'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('حسابِ کسب‌وکار')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: tr('نمایه')),
            Tab(text: tr('آمار')),
            Tab(text: tr('پلن‌ها')),
            Tab(text: tr('اشتراک‌های من')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_profileTab(), _insightsTab(), _tiersTab(), _subsTab()],
      ),
    );
  }

  Widget? _banner() {
    if (_error != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_error!),
        ),
      );
    }
    if (_notice != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(_notice!),
        ),
      );
    }
    return null;
  }

  // ── تبِ نمایه ──
  Widget _profileTab() {
    final p = _profile;
    final banner = _banner();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (banner != null) ...[banner, const SizedBox(height: 8)],
        if (p != null)
          Card(
            child: ListTile(
              leading: Text(p.kindEmoji, style: const TextStyle(fontSize: 26)),
              title: Row(
                children: [
                  Flexible(child: Text(p.displayName)),
                  if (p.verified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 16, color: Colors.lightBlue),
                  ],
                ],
              ),
              subtitle: Text(
                '${p.categoryEmoji} ${p.categoryLabel} · ${p.kindLabel} · '
                '${tr('{0} دنبال‌کننده', [p.followerCount])}',
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tr(
                'با ساختِ حسابِ کسب‌وکار، آمارِ واقعیِ نمایه و امکانِ اشتراکِ پولی فعال می‌شود.',
              )),
            ),
          ),
        const SizedBox(height: 12),
        Text(tr('نوعِ حساب'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final k in _kinds)
              ChoiceChip(
                label: Text(k.minKyc > 0
                    ? '${k.emoji} ${k.label} · ${tr('نیازمندِ سطحِ {0}', [k.minKyc])}'
                    : '${k.emoji} ${k.label}'),
                selected: _kind == k.key,
                onSelected: (_) => setState(() => _kind = k.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: tr('نامِ نمایشی'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Text(tr('دسته‌بندی'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final c in _categories)
              ChoiceChip(
                label: Text('${c.emoji} ${c.label}'),
                selected: _category == c.key,
                onSelected: (_) => setState(() => _category = c.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _aboutCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: tr('درباره'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _siteCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: tr('وب‌سایت'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: tr('تلفنِ تماس'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: tr('ایمیلِ تماس'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressCtrl,
          decoration: InputDecoration(
            labelText: tr('نشانی'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _saveProfile,
          child: Text(p == null ? tr('ساختِ حساب') : tr('ذخیرهٔ تغییرات')),
        ),
        if (p != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _deleteProfile,
            child: Text(tr('حذفِ حسابِ کسب‌وکار')),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          tr('نشانِ تأیید خریدنی نیست؛ خودکار از سطحِ احرازِ هویتِ شما محاسبه می‌شود.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ── تبِ آمار ──
  Widget _insightsTab() {
    if (_profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('برای دیدنِ آمار ابتدا حسابِ کسب‌وکار بسازید.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final i = _insights;
    if (i == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.1,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            _stat(tr('دنبال‌کننده'), '${i.followersTotal}',
                tr('+{0} در ۷ روز', [i.followers7d])),
            _stat(tr('بازدیدِ ۳۰ روز'), '${i.views30d}',
                tr('{0} در ۷ روز', [i.views7d])),
            _stat(tr('نرخِ تعامل'), '${i.engagementRate.toStringAsFixed(1)}٪',
                tr('{0} پست', [i.postsTotal])),
            _stat(tr('درآمدِ ۳۰ روز'), _toman(i.revenue30d),
                tr('{0} مشترکِ فعال', [i.subscribersActive])),
          ],
        ),
        const SizedBox(height: 12),
        _chartCard(tr('بازدیدِ نمایه در ۳۰ روزِ گذشته'), i.viewsSeries,
            Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        _chartCard(tr('دنبال‌کنندهٔ تازه در ۳۰ روزِ گذشته'), i.followersSeries,
            Theme.of(context).colorScheme.tertiary),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _stat(tr('لایک'), '${i.likesTotal}', null)),
            const SizedBox(width: 8),
            Expanded(child: _stat(tr('دیدگاه'), '${i.commentsTotal}', null)),
            const SizedBox(width: 8),
            Expanded(child: _stat(tr('ذخیره'), '${i.savesTotal}', null)),
          ],
        ),
        if (i.topPosts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('پرتعامل‌ترین پست‌ها'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (var n = 0; n < i.topPosts.length; n++)
            Card(
              child: ListTile(
                leading: Text('${n + 1}'),
                title: Text(
                  i.topPosts[n].caption?.trim().isNotEmpty == true
                      ? i.topPosts[n].caption!
                      : tr('بدونِ توضیح'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('❤️ ${i.topPosts[n].likeCount}  '
                    '💬 ${i.topPosts[n].commentCount}  '
                    '🔖 ${i.topPosts[n].saveCount}'),
                trailing: Text('${i.topPosts[n].engagement}'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _stat(String label, String value, String? hint) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            if (hint != null)
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  /// نمودارِ ستونیِ ساده — داده فقط ۳۰ نقطه است و به کتابخانهٔ نمودار نیازی نیست.
  Widget _chartCard(String title, List<BizDayPoint> data, Color color) {
    final max = data.fold<int>(1, (a, b) => b.value > a ? b.value : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in data)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: (d.value / max * 76).clamp(3, 76).toDouble(),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── تبِ پلن‌ها ──
  Widget _tiersTab() {
    final banner = _banner();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (banner != null) ...[banner, const SizedBox(height: 8)],
        Text(tr('پلنِ اشتراکِ تازه'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _tierNameCtrl,
          decoration: InputDecoration(
            labelText: tr('نامِ پلن'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tierPriceCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('قیمتِ ماهانه (تومان)'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tierPerksCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: tr('مزایای پلن'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _addTier,
          child: Text(tr('افزودنِ پلن')),
        ),
        const SizedBox(height: 16),
        if (_tiers.isEmpty)
          Text(tr('هنوز پلنِ اشتراکی نساخته‌اید.'))
        else
          for (final t in _tiers)
            Card(
              child: ListTile(
                title: Text(t.isActive
                    ? t.name
                    : '${t.name} · ${tr('غیرفعال')}'),
                subtitle: Text(
                  '${_toman(t.price)} ${tr('ماهانه')} · '
                  '${tr('{0} مشترک', [t.subscriberCount])}'
                  '${t.perks != null && t.perks!.isNotEmpty ? '\n${t.perks}' : ''}',
                ),
                isThreeLine: t.perks != null && t.perks!.isNotEmpty,
                trailing: t.isActive
                    ? IconButton(
                        icon: const Icon(Icons.block),
                        tooltip: tr('غیرفعال‌سازی'),
                        onPressed: _busy ? null : () => _deactivateTier(t),
                      )
                    : null,
              ),
            ),
        if (_subscribers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(tr('مشترکانِ من'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final s in _subscribers)
            Card(
              child: ListTile(
                title: Text(s.subscriberName?.trim().isNotEmpty == true
                    ? s.subscriberName!
                    : s.subscriberEarthId),
                subtitle: Text(
                  '${s.tierName} · ${tr('{0} دوره', [s.periodsPaid])} · '
                  '${_toman(s.totalPaid)}',
                ),
                trailing: Text(_statusLabel(s.status)),
              ),
            ),
        ],
      ],
    );
  }

  // ── تبِ اشتراک‌های من ──
  Widget _subsTab() {
    final banner = _banner();
    if (_mySubs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('هنوز مشترکِ هیچ حسابی نیستید.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (banner != null) ...[banner, const SizedBox(height: 8)],
        for (final s in _mySubs)
          Card(
            child: ListTile(
              title: Text(s.ownerName?.trim().isNotEmpty == true
                  ? s.ownerName!
                  : s.ownerEarthId),
              subtitle: Text(
                '${s.tierName} · ${_toman(s.price)} ${tr('ماهانه')}\n'
                '${tr('تا {0}', [_date(s.currentPeriodEnd)])} · '
                '${tr('{0} دوره', [s.periodsPaid])} · '
                '${s.autoRenew ? tr('تمدیدِ خودکار روشن') : tr('تمدیدِ خودکار خاموش')}',
              ),
              isThreeLine: true,
              trailing: s.status == 'active'
                  ? TextButton(
                      onPressed: _busy ? null : () => _cancelSub(s),
                      child: Text(tr('لغو')),
                    )
                  : Text(_statusLabel(s.status)),
            ),
          ),
      ],
    );
  }
}
