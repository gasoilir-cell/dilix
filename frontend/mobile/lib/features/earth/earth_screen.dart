import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// کشفِ افراد/کسب‌وکار روی کره (امضای محصول، سند ۷ §۳).
/// کره‌ی 3D واقعی هنگامِ بیلد افزوده می‌شود؛ این صفحه نمایِ فهرستیِ opt-in را
/// با حریمِ خصوصی (مختصاتِ fuzzed، فقط سطحِ منطقه) ارائه می‌دهد.
class EarthScreen extends StatefulWidget {
  const EarthScreen({super.key});

  @override
  State<EarthScreen> createState() => _EarthScreenState();
}

class _EarthScreenState extends State<EarthScreen> {
  final _countryCtrl = TextEditingController();
  String _entityType = '';
  List<NearbyPerson> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // نمایشِ اولیهٔ کاربران بدونِ نیاز به فشردنِ دکمه.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiScope.of(context).earthUsers(
        type: _entityType,
        country: _countryCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _results = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'جست‌وجو ممکن نشد: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startChat(NearbyPerson p) async {
    try {
      await ApiScope.of(context).createDirectRoom(p.earthId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('گفتگو با ${p.displayName ?? p.earthId} در تبِ پیام‌ها باز شد.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شروعِ گفتگو ممکن نشد.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('کشف روی کره')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'فقط کاربرانِ opt-in نمایش داده می‌شوند؛ مختصاتِ دقیق هرگز فاش نمی‌شود.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🌍', style: TextStyle(fontSize: 56)),
                    Text('کره‌ی سه‌بعدی هنگام اجرا بارگذاری می‌شود',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _entityType,
                    decoration: const InputDecoration(labelText: 'نوع'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('همه')),
                      DropdownMenuItem(value: 'person', child: Text('افراد')),
                      DropdownMenuItem(value: 'driver', child: Text('راننده')),
                      DropdownMenuItem(value: 'business', child: Text('کسب‌وکار')),
                    ],
                    onChanged: (v) => setState(() => _entityType = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _countryCtrl,
                    decoration: const InputDecoration(labelText: 'کشور (کدِ ISO-3، اختیاری)'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.search),
                      label: const Text('جست‌وجو'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
          if (!_loading && _results.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('کاربری برای نمایش یافت نشد.', textAlign: TextAlign.center),
            ),
          ..._results.map(
            (p) => Card(
              child: ListTile(
                title: Text(p.displayName ?? 'کاربر'),
                subtitle: Text('${p.entityType} · ${p.profession ?? '—'}'),
                trailing: FilledButton.tonal(
                  onPressed: () => _startChat(p),
                  child: const Text('گفتگو'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
