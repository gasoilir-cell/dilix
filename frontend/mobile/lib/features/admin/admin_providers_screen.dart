import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// کنسولِ KYBِ مراکزِ خدمات — `GET /providers/admin/all` و
/// `POST /providers/{id}/kyb`. سرور نقشِ `admin`/`super_admin` می‌خواهد.
class AdminProvidersScreen extends StatefulWidget {
  const AdminProvidersScreen({super.key});

  @override
  State<AdminProvidersScreen> createState() => _AdminProvidersScreenState();
}

class _AdminProvidersScreenState extends State<AdminProvidersScreen> {
  static const _kybLabels = <String, String>{
    'pending': 'در انتظار',
    'verified': 'تأییدشده',
    'rejected': 'ردشده',
  };

  List<Provider>? _items;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).adminAllProviders();
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _decide(Provider p, String status) async {
    final note = await _askNote(status);
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await ApiScope.of(context)
          .reviewProviderKyb(p.id, status: status, note: note);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final x in _items ?? const <Provider>[])
            x.id == p.id ? updated : x,
        ];
      });
      messenger.showSnackBar(
        SnackBar(content: Text('وضعیتِ «${p.legalName}» ثبت شد.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('ثبتِ تصمیم ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `null` = انصراف، `''` = بدونِ یادداشت.
  Future<String?> _askNote(String status) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'verified' ? 'تأییدِ مرکز' : 'ردِ مرکز'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('احرازِ مراکزِ خدمات (KYB)')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!.contains('403')
                ? 'این بخش فقط برای مدیرانِ پلتفرم است.'
                : 'بارگذاری ممکن نشد.\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return const Center(child: Text('مرکزی ثبت نشده است.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) => _card(items[i]),
      ),
    );
  }

  Widget _card(Provider p) {
    final pending = p.kybStatus == 'pending';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.legalName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Chip(
                label: Text(_kybLabels[p.kybStatus] ?? p.kybStatus),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(
            '${p.providerTypeLabel.isEmpty ? p.providerType : p.providerTypeLabel}'
            ' · ${p.countryFlag}${p.country} · ${p.currency}'
            ' · کمیسیون ${p.commissionRate}٪',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (p.productsLabels.isNotEmpty)
            Text('محصولات: ${p.productsLabels.join('، ')}',
                style: Theme.of(context).textTheme.bodySmall),
          if (pending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide(p, 'rejected'),
                    child: const Text('رد'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _decide(p, 'verified'),
                    child: const Text('تأیید'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
