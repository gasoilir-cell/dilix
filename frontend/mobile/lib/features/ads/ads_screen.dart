import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';

/// تبلیغاتِ خودخدمت — معادلِ صفحهٔ وبِ `app/(main)/ads/page.tsx`.
///
/// بودجه هنگامِ فعال‌سازی از کیفِ پول **بلوکه** می‌شود و فقط بابتِ کلیک خرج
/// می‌شود؛ باقی‌مانده با توقف یا پایانِ کمپین برمی‌گردد. دکمه‌ها از پرچم‌های
/// `can*`ِ سرور می‌آیند تا ماشینِ وضعیت دوباره در کلاینت پیاده نشود.
class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

const _placements = <String, String>{
  'feed': 'خوراک',
  'explore': 'کاوش',
  'story': 'استوری',
  'search': 'جستجو',
};

// کمینه‌های سرور، به تومان — تا کاربر پیش از ارسال بداند مرز کجاست.
const _bidMinToman = 100;
const _budgetMinToman = 10000;

class _AdsScreenState extends State<AdsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _ctaCtrl = TextEditingController();
  final _bidCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _countriesCtrl = TextEditingController();

  String _placement = 'feed';
  bool _showForm = false;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  List<AdCampaign> _campaigns = const [];
  String? _statsFor;
  AdStats? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _urlCtrl.dispose();
    _ctaCtrl.dispose();
    _bidCtrl.dispose();
    _budgetCtrl.dispose();
    _countriesCtrl.dispose();
    super.dispose();
  }

  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  Future<void> _load() async {
    await _run(() async {
      final rows = await ApiScope.of(context).adCampaigns();
      if (mounted) setState(() => _campaigns = rows);
    }, tr('بارگیریِ کمپین‌ها ناموفق بود'));
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
      if (mounted) {
        setState(() => _error = e.detail.isNotEmpty ? e.detail : failure);
      }
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final bid = int.tryParse(_bidCtrl.text.trim()) ?? 0;
    final budget = int.tryParse(_budgetCtrl.text.trim()) ?? 0;
    if (title.length < 2) {
      setState(() => _error = tr('عنوان دستِ‌کم دو نویسه باشد'));
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = tr('نشانیِ مقصد باید با http یا https شروع شود'));
      return;
    }
    if (bid < _bidMinToman) {
      setState(() =>
          _error = tr('کمینهٔ هزینهٔ هر کلیک {0} تومان است', [_bidMinToman]));
      return;
    }
    if (budget < _budgetMinToman) {
      setState(() =>
          _error = tr('کمینهٔ بودجه {0} تومان است', [_budgetMinToman]));
      return;
    }
    if (budget < bid) {
      setState(() => _error = tr('بودجه باید دستِ‌کم به یک کلیک برسد'));
      return;
    }
    final countries = _countriesCtrl.text
        .split(RegExp(r'[,،\s]+'))
        .map((c) => c.trim().toUpperCase())
        .where((c) => c.isNotEmpty)
        .toList();

    await _run(() async {
      final api = ApiScope.of(context);
      await api.createAdCampaign(
        title: title,
        targetUrl: url,
        bidCpc: bid * 10,
        budgetTotal: budget * 10,
        placement: _placement,
        body: _bodyCtrl.text.trim(),
        cta: _ctaCtrl.text.trim(),
        targetCountries: countries,
      );
      final rows = await api.adCampaigns();
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _urlCtrl.clear();
      _ctaCtrl.clear();
      _bidCtrl.clear();
      _budgetCtrl.clear();
      _countriesCtrl.clear();
      setState(() {
        _campaigns = rows;
        _showForm = false;
        _notice = tr('کمپین ساخته شد');
      });
    }, tr('ساختِ کمپین ناموفق بود'));
  }

  Future<void> _act(AdCampaign c, String kind) async {
    if (kind == 'activate') {
      final yes = await _confirm(
        tr('فعال‌سازیِ کمپین'),
        tr('{0} از موجودیِ در دسترس بلوکه شود؟ فقط بابتِ کلیک خرج می‌شود و '
            'باقی‌مانده با توقف برمی‌گردد.', [_toman(c.remaining)]),
      );
      if (!yes) return;
    }
    if (kind == 'stop') {
      final yes = await _confirm(
        tr('پایانِ کمپین'),
        tr('کمپین برای همیشه بسته شود؟ بودجهٔ خرج‌نشده برمی‌گردد.'),
      );
      if (!yes) return;
    }
    await _run(() async {
      final api = ApiScope.of(context);
      switch (kind) {
        case 'activate':
          await api.activateAdCampaign(c.id);
        case 'pause':
          await api.pauseAdCampaign(c.id);
        default:
          await api.stopAdCampaign(c.id);
      }
      final rows = await api.adCampaigns();
      if (!mounted) return;
      setState(() {
        _campaigns = rows;
        _notice = tr('انجام شد');
      });
    }, tr('انجامِ عملیات ناموفق بود'));
  }

  Future<void> _toggleStats(AdCampaign c) async {
    if (_statsFor == c.id) {
      setState(() {
        _statsFor = null;
        _stats = null;
      });
      return;
    }
    await _run(() async {
      final s = await ApiScope.of(context).adCampaignStats(c.id);
      if (!mounted) return;
      setState(() {
        _statsFor = c.id;
        _stats = s;
      });
    }, tr('بارگیریِ آمار ناموفق بود'));
  }

  Color _statusColor(String s) => switch (s) {
        'active' => Colors.green,
        'paused' => Colors.amber,
        'completed' => Colors.lightBlue,
        'rejected' => Colors.redAccent,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final banner = _banner();
    return Scaffold(
      appBar: AppBar(title: Text(tr('تبلیغات'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (banner != null) ...[banner, const SizedBox(height: 12)],
            Card(
              child: ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(tr('تبلیغِ خودخدمت')),
                subtitle: Text(tr('بودجه هنگامِ فعال‌سازی بلوکه می‌شود و فقط '
                    'بابتِ کلیک خرج می‌شود؛ باقی‌مانده برمی‌گردد.')),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _showForm = !_showForm),
                icon: const Icon(Icons.add),
                label: Text(tr('کمپینِ تازه')),
              ),
            ),
            if (_showForm) ...[const SizedBox(height: 12), _form()],
            const SizedBox(height: 12),
            if (_campaigns.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text(tr('هنوز کمپینی نساخته‌اید'))),
              ),
            ..._campaigns.map(_card),
          ],
        ),
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
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(_notice!),
        ),
      );
    }
    return null;
  }

  Widget _form() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: tr('عنوانِ تبلیغ')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyCtrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('متنِ کوتاه')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: tr('نشانیِ مقصد')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ctaCtrl,
                decoration: InputDecoration(labelText: tr('متنِ دکمه')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _placement,
                decoration: InputDecoration(labelText: tr('جایگاه')),
                items: _placements.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(tr(e.value)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _placement = v ?? 'feed'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: tr('هزینهٔ هر کلیک (تومان)')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _budgetCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: tr('کلِ بودجه (تومان)')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _countriesCtrl,
                decoration: InputDecoration(
                  labelText: tr('کشورهای هدف'),
                  helperText: tr('مثلاً IRN, DEU — خالی یعنی همه'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: Text(tr('ساختِ کمپین')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('کمپین پیش‌نویس ساخته می‌شود و تا فعال‌سازی هیچ پولی '
                    'برداشته نمی‌شود.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );

  Widget _card(AdCampaign c) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.title, style: theme.textTheme.titleSmall),
                ),
                Chip(
                  label:
                      Text(c.statusLabel, style: const TextStyle(fontSize: 11)),
                  backgroundColor: _statusColor(c.status).withValues(alpha: .15),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(tr(_placements[c.placement] ?? c.placement),
                style: theme.textTheme.bodySmall),
            if ((c.body ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.body!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _stat(tr('خرج‌شده'), _toman(c.spent)),
                _stat(tr('باقی‌مانده'), _toman(c.remaining)),
                _stat(tr('هر کلیک'), _toman(c.bidCpc)),
                _stat(tr('نمایش'), '${c.impressions}'),
                _stat(tr('کلیک'), '${c.clicks}'),
                _stat(tr('نرخِ کلیک'), '${c.ctr}٪'),
              ],
            ),
            if (c.targetCountries.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.targetCountries.join(' · '),
                  style: theme.textTheme.bodySmall),
            ],
            if ((c.reviewNote ?? '').isNotEmpty)
              Text(tr('یادداشتِ بازبینی: {0}', [c.reviewNote!]),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.canActivate)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _act(c, 'activate'),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(tr('فعال‌سازی')),
                  ),
                if (c.canPause)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _act(c, 'pause'),
                    icon: const Icon(Icons.pause, size: 18),
                    label: Text(tr('توقف')),
                  ),
                if (c.canStop)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _act(c, 'stop'),
                    icon: const Icon(Icons.stop, size: 18),
                    label: Text(tr('پایان')),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _toggleStats(c),
                  icon: const Icon(Icons.bar_chart, size: 18),
                  label: Text(tr('آمار')),
                ),
              ],
            ),
            if (_statsFor == c.id && _stats != null) _statsBox(_stats!),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      );

  Widget _statsBox(AdStats s) {
    // سرور روزهای خالی را با صفر پر می‌کند، پس نمودار حفره ندارد.
    final peak = s.series.fold<int>(1, (m, p) => p.impressions > m ? p.impressions : m);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            tr('۱۴ روزِ گذشته · میانگینِ هر کلیک: {0}', [_toman(s.avgCpc)]),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: s.series
                  .map((p) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Container(
                            height: 64 * (p.impressions / peak),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .6),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(2)),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
