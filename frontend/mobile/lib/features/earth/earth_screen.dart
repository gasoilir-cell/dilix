import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';

/// کشفِ افراد/کسب‌وکار روی کره (امضای محصول، سند ۷ §۳).
/// کره‌ی سه‌بعدیِ واقعی داخلِ [WebView] از `dilix.ir/earth` بارگذاری می‌شود
/// (رندرِ روی دستگاه، نه اتوماسیونِ مرورگر). نتایجِ opt-in با حریمِ خصوصی
/// (مختصاتِ fuzzed، فقط سطحِ منطقه) در یک شیتِ کشویی نمایش داده می‌شوند.
class EarthScreen extends StatefulWidget {
  const EarthScreen({super.key});

  @override
  State<EarthScreen> createState() => _EarthScreenState();
}

class _EarthScreenState extends State<EarthScreen> {
  final _countryCtrl = TextEditingController();
  final _queryCtrl = TextEditingController();
  String _entityType = '';
  String _query = '';
  List<NearbyPerson> _results = const [];
  bool _loading = false;
  String? _error;
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    _initWebView();
    // نمایشِ اولیهٔ کاربران بدونِ نیاز به فشردنِ دکمه.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  /// ساختِ کنترلرِ WebView؛ در محیطِ تست یا پلتفرمِ بدونِ WebView به‌آرامی
  /// شکست می‌خورد و نمایِ جایگزین (کره‌ی گرادیانی) استفاده می‌شود.
  void _initWebView() {
    try {
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B1026))
        ..loadRequest(Uri.parse(AppConfig.earthWebUrl));
    } catch (_) {
      _web = null;
    }
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _queryCtrl.dispose();
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

  /// فیلترِ سمتِ کلاینت روی نتایجِ بارگذاری‌شده بر اساسِ نام یا Earth ID.
  List<NearbyPerson> get _filtered {
    if (_query.trim().isEmpty) return _results;
    final q = _query.trim().toLowerCase();
    return _results
        .where((p) =>
            (p.displayName ?? '').toLowerCase().contains(q) ||
            p.earthId.toLowerCase().contains(q))
        .toList();
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

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('فیلترِ کشف',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _search();
                },
                icon: const Icon(Icons.search),
                label: const Text('اعمالِ فیلتر'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _globe()),
          // نوارِ جستجوی شناور + دکمهٔ فیلتر.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _searchBar(),
          ),
          // نتایج در شیتِ کشویی پایین.
          _resultsSheet(),
        ],
      ),
    );
  }

  Widget _globe() {
    if (_web != null) return WebViewWidget(controller: _web!);
    // نمایِ جایگزین وقتی WebView در دسترس نیست.
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [Color(0xFF1B3A6B), Color(0xFF070B1A)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🌍', style: TextStyle(fontSize: 96)),
          const SizedBox(height: 8),
          const Text('کره‌ی سه‌بعدی روی دستگاه بارگذاری می‌شود',
              style: TextStyle(color: Color(0xB3FFFFFF))),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.search),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _queryCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'جستجوی نام یا Earth ID…',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              tooltip: 'فیلتر',
              onPressed: _openFilters,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsSheet() {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        final items = _filtered;
        return Material(
          elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'فقط کاربرانِ opt-in نمایش داده می‌شوند؛ مختصاتِ دقیق هرگز فاش نمی‌شود.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  ),
                ),
              if (!_loading && items.isEmpty && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('کاربری برای نمایش یافت نشد.',
                      textAlign: TextAlign.center),
                ),
              ...items.map(
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
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
