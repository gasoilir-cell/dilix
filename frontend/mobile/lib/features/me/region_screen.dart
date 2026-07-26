import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// زبان، ارز و منطقهٔ **حساب** (`/api/v1/i18n/*`).
///
/// این با «زبانِ برنامه» در تنظیمات فرق دارد: آن ترجیحِ محلیِ همین گوشی است،
/// این روی سرور ذخیره می‌شود و مبنای ارزِ صورت‌حساب و قالب‌بندیِ اعداد است.
class RegionScreen extends StatefulWidget {
  const RegionScreen({super.key});

  @override
  State<RegionScreen> createState() => _RegionScreenState();
}

class _RegionScreenState extends State<RegionScreen> {
  I18nCatalog? _catalog;
  I18nPreferences? _prefs;
  I18nSuggestion? _suggestion;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _catalog == null) _load();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await api.i18nCatalog();
      final prefs = await api.i18nPreferences();
      // پیشنهادِ خودکار صرفاً کمکی است؛ اگر نگرفتیم صفحه نباید بشکند.
      I18nSuggestion? suggestion;
      try {
        suggestion = await api.i18nDetect();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _prefs = prefs;
        _suggestion = suggestion;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ تنظیماتِ منطقه ممکن نشد.\n{0}', [e]);
        _loading = false;
      });
    }
  }

  Future<void> _save({String? locale, String? currency, String? countryCode}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final updated = await ApiScope.of(context).setI18nPreferences(
        locale: locale,
        currency: currency,
        countryCode: countryCode,
      );
      if (!mounted) return;
      setState(() {
        _prefs = updated;
        _saving = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(tr('ذخیره شد.'))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('ذخیره نشد: {0}', [e]))));
    }
  }

  Future<void> _pickLocale() async {
    final c = _catalog!;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in c.locales)
              ListTile(
                leading: Text(l.flag ?? '🏳', style: const TextStyle(fontSize: 22)),
                title: Text(l.native),
                subtitle: Text(tr('{0} · {1}', [l.english, l.isRtl ? tr('راست‌به‌چپ') : tr('چپ‌به‌راست')])),
                trailing: _prefs?.locale == l.code ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, l.code),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _save(locale: chosen);
  }

  Future<void> _pickCurrency() async {
    final c = _catalog!;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final cur in c.currencies)
              ListTile(
                leading: Text(cur.symbol, style: const TextStyle(fontSize: 18)),
                title: Text('${cur.nameFa} (${cur.code})'),
                subtitle: cur.subunit != null
                    ? Text(tr('واحدِ نمایش: {0}', [cur.subunit]))
                    : Text(cur.nameEn),
                trailing:
                    _prefs?.currency == cur.code ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, cur.code),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _save(currency: chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('زبان و ارزِ حساب'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_saving) const LinearProgressIndicator(),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.translate),
                            title: Text(tr('زبانِ حساب')),
                            subtitle: Text(_localeLabel()),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: _saving ? null : _pickLocale,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.payments_outlined),
                            title: Text(tr('ارزِ نمایش')),
                            subtitle: Text(_currencyLabel()),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: _saving ? null : _pickCurrency,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.flag_outlined),
                            title: Text(tr('کشور')),
                            subtitle: Text(_prefs?.countryCode ?? tr('ثبت نشده')),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.schedule),
                            title: Text(tr('منطقهٔ زمانی')),
                            subtitle: Text(_prefs?.timezone ?? tr('ثبت نشده')),
                          ),
                        ],
                      ),
                    ),
                    if (_suggestion != null) _suggestionCard(_suggestion!),
                  ],
                ),
    );
  }

  Widget _suggestionCard(I18nSuggestion s) {
    final same = _prefs?.locale == s.locale && _prefs?.currency == s.currency;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('پیشنهادِ خودکار'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              tr('بر اساسِ {0}: زبانِ {1} و ارزِ {2}{3}', [_sourceLabel(s.source), s.locale.toUpperCase(), s.currency, s.country != null ? tr(' (کشورِ {0})', [s.country]) : '']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: same || _saving
                    ? null
                    : () => _save(
                          locale: s.locale,
                          currency: s.currency,
                          countryCode: s.country,
                        ),
                child: Text(same ? tr('همین حالا اعمال شده') : tr('اعمالِ پیشنهاد')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _localeLabel() {
    final code = _prefs?.locale;
    final l = _catalog?.locales.where((e) => e.code == code).firstOrNull;
    if (l == null) return code ?? '—';
    return '${l.flag ?? ''} ${l.native}'.trim();
  }

  String _currencyLabel() {
    final code = _prefs?.currency;
    final c = _catalog?.currencies.where((e) => e.code == code).firstOrNull;
    if (c == null) return code ?? '—';
    return '${c.nameFa} (${c.code})';
  }

  static String _sourceLabel(String? s) => switch (s) {
        'geoip' => tr('موقعیتِ شبکه'),
        'accept-language' => tr('زبانِ دستگاه'),
        _ => tr('پیش‌فرض'),
      };
}
