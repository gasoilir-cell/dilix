import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../models/models.dart';

/// پورتالِ ارائه‌دهنده — parity با `app/provider/page.tsx` وب:
/// ثبت‌نامِ KYB، ثبتِ API، تستِ sandbox، webhook و صدورِ کلید (خودسرویس).
class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key});

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  // نوعِ ارائه‌دهنده → برچسبِ فارسی (منطبق با انواعِ مجازِ dilix-api).
  static const _providerTypes = <(String, String)>[
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
  Webhook? _webhook;
  Credential? _credential;
  String? _error;
  bool _busy = false;

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
      if (mounted) setState(() => _error = 'عملیات ناموفق بود. ابتدا وارد شوید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() => _run(() async {
        final name = _legalNameCtrl.text.trim();
        final license = _licenseNoCtrl.text.trim();
        if (name.length < 2) {
          setState(() => _error = 'نامِ حقوقی را وارد کنید.');
          return;
        }
        if (license.length < 2) {
          setState(() => _error = 'کدِ مجوز/بیمه‌ای را وارد کنید.');
          return;
        }
        if (!_agreementAccepted) {
          setState(() => _error = 'برای ثبت‌نام باید توافق‌نامهٔ همکاری را بپذیرید.');
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
          setState(() => _error = 'نامِ سرویس را وارد کنید.');
          return;
        }
        if (baseUrl.length < 4) {
          setState(() => _error = 'آدرسِ پایهٔ API را وارد کنید.');
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
          setState(() => _error = 'آدرسِ webhook معتبر نیست.');
          return;
        }
        final w = await ApiScope.of(context).registerProviderWebhook(_provider!.id, url: url);
        if (mounted) {
          setState(() {
            _webhook = w;
            _webhookUrlCtrl.clear();
          });
        }
      });

  Future<void> _addCredential() => _run(() async {
        final label = _credLabelCtrl.text.trim();
        final secret = _credSecretCtrl.text.trim();
        if (label.length < 2 || _provider == null) {
          setState(() => _error = 'نامِ کلید (label) را وارد کنید.');
          return;
        }
        if (secret.length < 4) {
          setState(() => _error = 'رازِ کلید حداقل ۴ نویسه است.');
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
            _credLabelCtrl.clear();
            _credSecretCtrl.clear();
          });
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پورتالِ ارائه‌دهنده')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'ثبتِ سرویس، تستِ sandbox، webhook و کلیدها — خودسرویس (Provider Adapter Framework).',
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
            const Text('ثبت‌نامِ ارائه‌دهنده (KYB)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _legalNameCtrl,
              decoration: const InputDecoration(labelText: 'نامِ حقوقی'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _licenseNoCtrl,
              decoration: const InputDecoration(labelText: 'کدِ مجوز / بیمه‌ای / کارگزاری'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _providerType,
              decoration: const InputDecoration(labelText: 'نوعِ ارائه‌دهنده'),
              items: [
                for (final t in _providerTypes)
                  DropdownMenuItem(value: t.$1, child: Text(t.$2)),
              ],
              onChanged: (v) => setState(() => _providerType = v ?? 'psp'),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreementAccepted,
              onChanged: (v) => setState(() => _agreementAccepted = v ?? false),
              title: const Text('توافق‌نامهٔ همکاری را می‌پذیرم.'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _register,
                child: Text(_busy ? 'در حال…' : 'ثبت‌نام'),
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
          subtitle: Text('${p.providerType} · ${p.country}'),
          trailing: Chip(label: Text('KYB: ${p.kybStatus}')),
        ),
      ),
      // ثبتِ API
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ثبتِ API', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _apiNameCtrl,
                decoration: const InputDecoration(labelText: 'نامِ سرویس/API'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _baseUrlCtrl,
                decoration: const InputDecoration(labelText: 'آدرسِ پایهٔ API (base URL)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _specUrlCtrl,
                decoration: const InputDecoration(labelText: 'آدرسِ OpenAPI spec (اختیاری)'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _addApi,
                  child: const Text('افزودنِ API'),
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
                  child: const Text('ثبتِ webhook'),
                ),
              ),
              if (_webhook?.secret != null) ...[
                const SizedBox(height: 8),
                _secretBox('secretِ امضای HMAC (فقط همین یک‌بار):', _webhook!.secret!),
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
              const Text('کلیدهای API', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'رازِ فراخوانیِ سرویسِ شما را وارد کنید؛ رمزنگاری‌شده ذخیره می‌شود و دیگر نمایش داده نمی‌شود.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _credLabelCtrl,
                decoration: const InputDecoration(labelText: 'نامِ کلید (label)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _credSecretCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'رازِ کلید (secret)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _credEnv,
                decoration: const InputDecoration(labelText: 'محیط'),
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
                  child: const Text('ثبتِ کلید'),
                ),
              ),
              if (_credential != null) ...[
                const SizedBox(height: 8),
                _secretBox(
                  'کلیدِ ثبت‌شده «${_credential!.label}» (${_credential!.env} · ${_credential!.status}):',
                  '${_credential!.keyPrefix}… (ذخیره‌شدهٔ رمزنگاری)',
                ),
              ],
            ],
          ),
        ),
      ),
    ];
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
                  child: const Text('تستِ sandbox'),
                ),
              ],
            ),
            if (tested != null) ...[
              const SizedBox(height: 8),
              Text(
                reachable ? '✓ اتصال برقرار شد (tested)' : '✕ اتصال ناموفق (failed)',
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
