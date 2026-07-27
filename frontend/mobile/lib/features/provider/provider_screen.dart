import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../models/models.dart';
import '../admin/insurance_commissions_screen.dart';

import '../../core/l10n.dart';
/// پورتالِ ارائه‌دهنده — parity با `app/provider/page.tsx` وب:
/// ثبت‌نامِ KYB، ثبتِ API، تستِ sandbox، webhook و صدورِ کلید (خودسرویس).
class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key});

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  // نوعِ ارائه‌دهنده → برچسبِ فارسی. اگر کاتالوگِ سرور بیاید جایگزین می‌شود؛
  // این فقط fallbackِ آفلاین است.
  static List<(String, String)> get _fallbackTypes =>
      _fallbackTypesSrc.map((e) => (e.$1, tr(e.$2))).toList();

  static const _fallbackTypesSrc = <(String, String)>[
    ('psp', 'شرکتِ پرداخت (PSP)'),
    ('insurer', 'شرکتِ بیمه'),
    ('bank', 'بانک'),
    ('broker', 'کارگزاری'),
    ('other', 'سایرِ خدمات‌دهنده'),
  ];

  Provider? _provider;
  final List<ProviderApi> _apis = [];
  // نتیجهٔ آخرین تستِ هر API (نسخهٔ به‌روزشدهٔ APIOut با status: tested/failed).
  final Map<String, ProviderApi> _sandbox = {};
  List<Credential> _credentials = const [];
  List<Webhook> _webhooks = const [];
  List<WebhookEvent> _events = const [];
  List<CatalogEntry> _types = const [];
  List<CatalogEntry> _productCatalog = const [];

  /// انتخابِ فعلیِ محصولاتِ پوشش‌داده‌شده؛ خالی یعنی «همه».
  Set<String> _products = {};

  Webhook? _webhook;
  Credential? _credential;
  String? _error;
  bool _busy = false;
  bool _loading = true;

  // فرم‌ها
  final _legalNameCtrl = TextEditingController();
  final _licenseNoCtrl = TextEditingController();
  String _providerType = 'psp';
  bool _agreementAccepted = false;
  final _apiNameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _specUrlCtrl = TextEditingController();
  final _webhookUrlCtrl = TextEditingController();
  final _credLabelCtrl = TextEditingController();
  final _credSecretCtrl = TextEditingController();
  String _credEnv = 'sandbox';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _bootstrap();
  }

  /// تا الان صفحه همیشه فرمِ ثبت‌نام را نشان می‌داد؛ حالا اول از سرور می‌پرسیم
  /// آیا کاربر مرکزی دارد و اگر دارد مستقیم پورتال را با داده‌های واقعی می‌آوریم.
  Future<void> _bootstrap() async {
    final api = ApiScope.of(context);
    List<CatalogEntry> types = const [];
    Provider? mine;
    try {
      types = await api.providerTypes();
    } catch (_) {
      // کاتالوگ اختیاری است؛ fallback سخت‌کدشده کار می‌کند.
    }
    try {
      final list = await api.myProviders();
      if (list.isNotEmpty) mine = list.first;
    } catch (_) {
      // کاربرِ ناواردشده یا بدونِ مرکز → فرمِ ثبت‌نام.
    }
    // کاتالوگِ محصولات به نوعِ مرکز وابسته است؛ اگر بدونِ نوع بخوانیم سرور
    // کاتالوگِ بیمه را می‌دهد و یک بانک، محصولاتِ بیمه‌ای می‌بیند.
    var type = mine?.providerType ?? _providerType;
    if (mine == null && types.isNotEmpty && !types.any((t) => t.id == type)) {
      type = types.first.id;
    }
    List<CatalogEntry> catalog = const [];
    try {
      catalog = await api.providerProductCatalog(providerType: type);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _types = types;
      _productCatalog = catalog;
      _provider = mine;
      _products = {...?mine?.products};
      if (mine == null) _providerType = type;
      _loading = false;
    });
    if (mine != null) await _hydrate(mine.id);
  }

  /// نوعِ مرکز در فرمِ ثبت‌نام عوض شد → کاتالوگِ محصولات باید دوباره خوانده شود.
  Future<void> _onTypeChanged(String type) async {
    setState(() {
      _providerType = type;
      _products = {};
    });
    try {
      final catalog =
          await ApiScope.of(context).providerProductCatalog(providerType: type);
      if (!mounted) return;
      setState(() => _productCatalog = catalog);
    } catch (_) {}
  }

  /// متنِ توافق‌نامه را از سرور می‌گیرد و در یک شیت نشان می‌دهد.
  Future<void> _showAgreement() async {
    final messenger = ScaffoldMessenger.of(context);
    ProviderAgreement agreement;
    try {
      agreement = await ApiScope.of(context).providerAgreement();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('دریافتِ متنِ توافق‌نامه ممکن نشد: {0}', [e]))),
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(agreement.title,
                style: Theme.of(ctx).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(tr('نسخهٔ {0}', [agreement.version]),
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final s in agreement.sections) ...[
              Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(s.body, style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// فهرست‌های وابسته به یک مرکز. هرکدام جدا try می‌شود تا خطای یکی بقیه را
  /// از بین نبرد.
  Future<void> _hydrate(String providerId) async {
    final api = ApiScope.of(context);
    List<ProviderApi> apis = const [];
    List<Credential> creds = const [];
    List<Webhook> hooks = const [];
    List<WebhookEvent> events = const [];
    try {
      apis = await api.providerApis(providerId);
    } catch (_) {}
    try {
      creds = await api.providerCredentials(providerId);
    } catch (_) {}
    try {
      hooks = await api.providerWebhooks(providerId);
    } catch (_) {}
    try {
      events = await api.providerWebhookEvents(providerId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _apis
        ..clear()
        ..addAll(apis);
      _credentials = creds;
      _webhooks = hooks;
      _events = events;
    });
  }

  @override
  void dispose() {
    _legalNameCtrl.dispose();
    _licenseNoCtrl.dispose();
    _apiNameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _specUrlCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _credLabelCtrl.dispose();
    _credSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } catch (_) {
      if (mounted) setState(() => _error = tr('عملیات ناموفق بود. ابتدا وارد شوید.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() => _run(() async {
        final name = _legalNameCtrl.text.trim();
        final license = _licenseNoCtrl.text.trim();
        if (name.length < 2) {
          setState(() => _error = tr('نامِ حقوقی را وارد کنید.'));
          return;
        }
        if (license.length < 2) {
          setState(() => _error = tr('کدِ مجوز/بیمه‌ای را وارد کنید.'));
          return;
        }
        if (!_agreementAccepted) {
          setState(() => _error = tr('برای ثبت‌نام باید توافق‌نامهٔ همکاری را بپذیرید.'));
          return;
        }
        final p = await ApiScope.of(context).registerProvider(
          legalName: name,
          providerType: _providerType,
          licenseNo: license,
          agreementAccepted: _agreementAccepted,
        );
        if (mounted) setState(() => _provider = p);
      });

  Future<void> _addApi() => _run(() async {
        final name = _apiNameCtrl.text.trim();
        final baseUrl = _baseUrlCtrl.text.trim();
        if (name.length < 2 || _provider == null) {
          setState(() => _error = tr('نامِ سرویس را وارد کنید.'));
          return;
        }
        if (baseUrl.length < 4) {
          setState(() => _error = tr('آدرسِ پایهٔ API را وارد کنید.'));
          return;
        }
        final api = await ApiScope.of(context).registerProviderApi(
          _provider!.id,
          name: name,
          baseUrl: baseUrl,
          specUrl: _specUrlCtrl.text.trim(),
        );
        if (mounted) {
          setState(() {
            _apis.add(api);
            _apiNameCtrl.clear();
            _baseUrlCtrl.clear();
            _specUrlCtrl.clear();
          });
        }
      });

  Future<void> _runSandbox(String apiId) => _run(() async {
        final res = await ApiScope.of(context).providerSandboxTest(_provider!.id, apiId);
        if (mounted) setState(() => _sandbox[apiId] = res);
      });

  Future<void> _addWebhook() => _run(() async {
        final url = _webhookUrlCtrl.text.trim();
        if (url.length < 8 || _provider == null) {
          setState(() => _error = tr('آدرسِ webhook معتبر نیست.'));
          return;
        }
        final w = await ApiScope.of(context).registerProviderWebhook(_provider!.id, url: url);
        if (mounted) {
          setState(() {
            _webhook = w;
            _webhooks = [..._webhooks, w];
            _webhookUrlCtrl.clear();
          });
        }
      });

  Future<void> _saveProducts() => _run(() async {
        final p = await ApiScope.of(context)
            .updateProviderProducts(_provider!.id, _products.toList());
        if (mounted) setState(() => _provider = p);
      });

  Future<void> _revokeCredential(Credential c) => _run(() async {
        final updated = await ApiScope.of(context)
            .revokeProviderCredential(_provider!.id, c.id);
        if (mounted) {
          setState(() {
            _credentials = [
              for (final x in _credentials) x.id == c.id ? updated : x,
            ];
          });
        }
      });

  Future<void> _refreshEvents() => _run(() async {
        final list =
            await ApiScope.of(context).providerWebhookEvents(_provider!.id);
        if (mounted) setState(() => _events = list);
      });

  Future<void> _addCredential() => _run(() async {
        final label = _credLabelCtrl.text.trim();
        final secret = _credSecretCtrl.text.trim();
        if (label.length < 2 || _provider == null) {
          setState(() => _error = tr('نامِ کلید (label) را وارد کنید.'));
          return;
        }
        if (secret.length < 4) {
          setState(() => _error = tr('رازِ کلید حداقل ۴ نویسه است.'));
          return;
        }
        final c = await ApiScope.of(context).addProviderCredential(
          _provider!.id,
          label: label,
          secret: secret,
          env: _credEnv,
        );
        if (mounted) {
          setState(() {
            _credential = c;
            _credentials = [..._credentials, c];
            _credLabelCtrl.clear();
            _credSecretCtrl.clear();
          });
        }
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('پورتالِ ارائه‌دهنده'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('پورتالِ ارائه‌دهنده'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            tr('ثبتِ سرویس، تستِ sandbox، webhook و کلیدها — خودسرویس (Provider Adapter Framework).'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            ),
          if (_provider == null) _registerCard() else ..._portal(),
        ],
      ),
    );
  }

  Widget _registerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('ثبت‌نامِ ارائه‌دهنده (KYB)'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _legalNameCtrl,
              decoration: InputDecoration(labelText: tr('نامِ حقوقی')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _licenseNoCtrl,
              decoration: InputDecoration(labelText: tr('کدِ مجوز / بیمه‌ای / کارگزاری')),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _providerType,
              decoration: InputDecoration(labelText: tr('نوعِ ارائه‌دهنده')),
              items: _types.isNotEmpty
                  ? [
                      for (final t in _types)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.emoji ?? ''} ${t.label}'.trim()),
                        ),
                    ]
                  : [
                      for (final t in _fallbackTypes)
                        DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                    ],
              onChanged: (v) => _onTypeChanged(v ?? 'psp'),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreementAccepted,
              onChanged: (v) => setState(() => _agreementAccepted = v ?? false),
              title: Text(tr('توافق‌نامهٔ همکاری را می‌پذیرم.')),
              subtitle: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: Text(tr('خواندنِ متنِ توافق‌نامه')),
                  onPressed: _showAgreement,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _register,
                child: Text(_busy ? tr('در حال…') : tr('ثبت‌نام')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _portal() {
    final p = _provider!;
    return [
      // هدرِ ارائه‌دهنده
      Card(
        child: ListTile(
          title: Text(p.legalName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            tr('{0} · {1}{2} · {3} · کمیسیون {4}٪', [p.providerTypeLabel.isEmpty ? p.providerType : p.providerTypeLabel, p.countryFlag, p.country, p.currency, p.commissionRate]),
          ),
          trailing: Chip(
            label: Text(
                'KYB: ${p.kybStatusLabel.isEmpty ? p.kybStatus : p.kybStatusLabel}'),
          ),
        ),
      ),
      if (!p.isVerified)
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              tr('تا وقتی KYB تأیید نشود، نرخِ شما در مقایسهٔ کاربران نشان داده نمی‌شود. می‌توانید در همین فاصله سرویس و کلیدها را آماده کنید.'),
            ),
          ),
        ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(tr('صورت‌حسابِ کارمزد')),
          subtitle: Text(_statementSubtitle(p.providerType)),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => InsuranceCommissionsScreen(
                providerId: p.id,
                title: tr('کارمزدِ {0}', [p.legalName]),
              ),
            ),
          ),
        ),
      ),
      _productsCard(p),
      // ثبتِ API
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('ثبتِ API'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _apiNameCtrl,
                decoration: InputDecoration(labelText: tr('نامِ سرویس/API')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _baseUrlCtrl,
                decoration: InputDecoration(labelText: tr('آدرسِ پایهٔ API (base URL)')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _specUrlCtrl,
                decoration: InputDecoration(labelText: tr('آدرسِ OpenAPI spec (اختیاری)')),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _addApi,
                  child: Text(tr('افزودنِ API')),
                ),
              ),
            ],
          ),
        ),
      ),
      // فهرستِ APIها + تستِ sandbox
      for (final a in _apis) _apiCard(a),
      // Webhook
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Webhook', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _webhookUrlCtrl,
                decoration: const InputDecoration(hintText: 'https://example.com/webhooks/dilix'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _addWebhook,
                  child: Text(tr('ثبتِ webhook')),
                ),
              ),
              if (_webhook?.secret != null) ...[
                const SizedBox(height: 8),
                _secretBox(tr('secretِ امضای HMAC (فقط همین یک‌بار):'), _webhook!.secret!),
              ],
            ],
          ),
        ),
      ),
      // کلیدهای API (رازِ فراخوانیِ Dilix→Provider؛ خودتان راز را تعیین می‌کنید)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('کلیدهای API'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                tr('رازِ فراخوانیِ سرویسِ شما را وارد کنید؛ رمزنگاری‌شده ذخیره می‌شود و دیگر نمایش داده نمی‌شود.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _credLabelCtrl,
                decoration: InputDecoration(labelText: tr('نامِ کلید (label)')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _credSecretCtrl,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('رازِ کلید (secret)')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _credEnv,
                decoration: InputDecoration(labelText: tr('محیط')),
                items: const [
                  DropdownMenuItem(value: 'sandbox', child: Text('sandbox')),
                  DropdownMenuItem(value: 'production', child: Text('production')),
                ],
                onChanged: (v) => setState(() => _credEnv = v ?? 'sandbox'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _addCredential,
                  child: Text(tr('ثبتِ کلید')),
                ),
              ),
              if (_credential != null) ...[
                const SizedBox(height: 8),
                _secretBox(
                  tr('کلیدِ ثبت‌شده «{0}» ({1} · {2}):', [_credential!.label, _credential!.env, _credential!.status]),
                  tr('{0}… (ذخیره‌شدهٔ رمزنگاری)', [_credential!.keyPrefix]),
                ),
              ],
              if (_credentials.isNotEmpty) ...[
                const Divider(height: 24),
                Text(tr('کلیدهای موجود'),
                    style: Theme.of(context).textTheme.titleSmall),
                for (final c in _credentials)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.label),
                    subtitle: Text(
                      tr('{0} · {1}… · {2}', [c.env, c.keyPrefix, c.isActive ? tr('فعال') : tr('ابطال‌شده')]),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: c.isActive
                        ? TextButton(
                            onPressed: _busy ? null : () => _revokeCredential(c),
                            child: Text(tr('ابطال')),
                          )
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ),
      _eventsCard(),
    ];
  }

  /// محصولاتی که این مرکز پوشش می‌دهد؛ خالی یعنی «همه».
  /// توضیحِ صورت‌حساب بسته به نوعِ مرکز؛ «بیمه‌نامهٔ صادرشده» برای بانک بی‌معناست.
  String _statementSubtitle(String providerType) {
    switch (providerType) {
      case 'insurer':
        return tr('کارمزدِ بیمه‌نامه‌های صادرشده از این مرکز');
      case 'bank':
        return tr('کارمزدِ خدماتِ بانکیِ ارائه‌شده از این مرکز');
      case 'psp':
        return tr('کارمزدِ تراکنش‌های پرداختِ این مرکز');
      case 'broker':
        return tr('کارمزدِ معامله‌ها و صدور/ابطالِ این کارگزاری');
      default:
        return tr('کارمزدِ سرویس‌های ارائه‌شده از این مرکز');
    }
  }

  Widget _productsCard(Provider p) {
    if (_productCatalog.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('محصولاتِ تحتِ پوشش'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              _products.isEmpty
                  ? tr('هیچ‌کدام انتخاب نشده — یعنی همهٔ محصولات.')
                  : tr('{0} محصول انتخاب شده.', [_products.length]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final e in _productCatalog)
                  FilterChip(
                    label: Text(e.label),
                    selected: _products.contains(e.id),
                    onSelected: _busy
                        ? null
                        : (on) => setState(() =>
                            on ? _products.add(e.id) : _products.remove(e.id)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _saveProducts,
                child: Text(tr('ذخیرهٔ محصولات')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// رویدادهای دریافتیِ webhook — تنها ابزارِ عیب‌یابیِ اتصال در موبایل.
  Widget _eventsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr('رویدادهای دریافتی'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: _busy ? null : _refreshEvents,
                  child: Text(tr('به‌روزرسانی')),
                ),
              ],
            ),
            if (_webhooks.isNotEmpty) ...[
              for (final w in _webhooks)
                Text('• ${w.url} (${w.status})',
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
            ],
            if (_events.isEmpty)
              Text(tr('هنوز رویدادی دریافت نشده است.'),
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final e in _events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.eventType),
                  subtitle: Text(
                    e.receivedAt?.toIso8601String() ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _apiCard(ProviderApi a) {
    // پس از تست، نسخهٔ به‌روزشدهٔ API (status: tested/failed) جایگزین می‌شود.
    final tested = _sandbox[a.id];
    final status = tested?.status ?? a.status;
    final reachable = status == 'tested';
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${a.env} · $status', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _runSandbox(a.id),
                  child: Text(tr('تستِ sandbox')),
                ),
              ],
            ),
            if (tested != null) ...[
              const SizedBox(height: 8),
              Text(
                reachable ? tr('✓ اتصال برقرار شد (tested)') : tr('✕ اتصال ناموفق (failed)'),
                style: TextStyle(
                  color: reachable
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _secretBox(String label, String value) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            SelectableText(value, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
