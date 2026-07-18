import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// پورتالِ ارائه‌دهنده — parity با `app/provider/page.tsx` وب:
/// ثبت‌نامِ KYB، ثبتِ API، تستِ sandbox، webhook و صدورِ کلید (خودسرویس).
class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key});

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  // نوعِ ارائه‌دهنده → برچسبِ فارسی (منطبق با optionهای صفحهٔ وب).
  static const _providerTypes = <(String, String)>[
    ('psp', 'PSP (پرداخت)'),
    ('insurer', 'بیمه‌گر'),
    ('carrier', 'حمل‌کننده / راهداری'),
    ('telecom', 'اپراتورِ ارتباطات'),
    ('third_party', 'شخصِ ثالث'),
  ];

  Provider? _provider;
  final List<ProviderApi> _apis = [];
  final Map<String, SandboxResult> _sandbox = {};
  Webhook? _webhook;
  Credential? _credential;
  String? _error;
  bool _busy = false;

  // فرم‌ها
  final _legalNameCtrl = TextEditingController();
  String _providerType = 'psp';
  final _apiNameCtrl = TextEditingController();
  final _specUrlCtrl = TextEditingController();
  final _webhookUrlCtrl = TextEditingController();

  @override
  void dispose() {
    _legalNameCtrl.dispose();
    _apiNameCtrl.dispose();
    _specUrlCtrl.dispose();
    _webhookUrlCtrl.dispose();
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
        if (name.length < 2) {
          setState(() => _error = 'نامِ حقوقی را وارد کنید.');
          return;
        }
        final p = await ApiScope.of(context).registerProvider(
          legalName: name,
          providerType: _providerType,
        );
        if (mounted) setState(() => _provider = p);
      });

  Future<void> _addApi() => _run(() async {
        final name = _apiNameCtrl.text.trim();
        if (name.length < 2 || _provider == null) {
          setState(() => _error = 'نامِ سرویس را وارد کنید.');
          return;
        }
        final api = await ApiScope.of(context).registerProviderApi(
          _provider!.id,
          name: name,
          specUrl: _specUrlCtrl.text.trim(),
        );
        if (mounted) {
          setState(() {
            _apis.add(api);
            _apiNameCtrl.clear();
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

  Future<void> _issueKey(String env) => _run(() async {
        final c = await ApiScope.of(context).issueProviderCredential(_provider!.id, env);
        if (mounted) setState(() => _credential = c);
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
            DropdownButtonFormField<String>(
              value: _providerType,
              decoration: const InputDecoration(labelText: 'نوعِ ارائه‌دهنده'),
              items: [
                for (final t in _providerTypes)
                  DropdownMenuItem(value: t.$1, child: Text(t.$2)),
              ],
              onChanged: (v) => setState(() => _providerType = v ?? 'psp'),
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
      // کلیدهای API
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('کلیدهای API', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _issueKey('sandbox'),
                      child: const Text('کلیدِ sandbox'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _issueKey('production'),
                      child: const Text('کلیدِ production'),
                    ),
                  ),
                ],
              ),
              if (_credential?.apiKey != null) ...[
                const SizedBox(height: 8),
                _secretBox('کلیدِ خام (${_credential!.env}) — فقط همین یک‌بار:', _credential!.apiKey!),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _apiCard(ProviderApi a) {
    final s = _sandbox[a.id];
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
                      Text('${a.env} · ${a.status}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _runSandbox(a.id),
                  child: const Text('تستِ sandbox'),
                ),
              ],
            ),
            if (s != null) ...[
              const SizedBox(height: 8),
              Text(
                '${s.reachable ? '✓ در دسترس' : '✕ ناموفق'} — ${s.detail}'
                '${s.latencyMs != null ? ' (${s.latencyMs}ms)' : ''}',
                style: TextStyle(
                  color: s.reachable
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
