import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/dilix_webview.dart';
import '../assistant/assistant_sheet.dart';

/// کشفِ افراد/کسب‌وکار روی کره (امضای محصول، سند ۷ §۳).
/// کره‌ی واقعیِ اپِ وب (dilix.ir/earth) داخلِ [DilixWebView] با توکنِ نشستِ موبایل
/// بارگذاری می‌شود تا همان تجربهٔ کاملِ وب در دسترس باشد. نوارِ جستجو و دکمه‌های
/// بومی روی کره باقی می‌مانند و کوئری/فیلتر را به صفحهٔ وب می‌دهند.
class EarthScreen extends StatefulWidget {
  const EarthScreen({super.key});

  @override
  State<EarthScreen> createState() => _EarthScreenState();
}

class _EarthScreenState extends State<EarthScreen> {
  final _countryCtrl = TextEditingController();
  final _queryCtrl = TextEditingController();
  String _entityType = '';
  // مسیرِ فعلیِ صفحهٔ وب؛ با تغییرِ جستجو/فیلتر عوض می‌شود و WebView دوباره
  // به آن مسیر می‌رود (کلیدِ ولیو برای بازسازیِ نما).
  String _path = '/earth';

  @override
  void dispose() {
    _countryCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  /// ساختِ مسیرِ وب بر پایهٔ کوئری و فیلترها و اعمالِ آن روی WebView.
  void _search() {
    final params = <String, String>{};
    final q = _queryCtrl.text.trim();
    if (q.isNotEmpty) params['q'] = q;
    if (_entityType.isNotEmpty) params['type'] = _entityType;
    final country = _countryCtrl.text.trim();
    if (country.isNotEmpty) params['country'] = country;
    final qs = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    setState(() => _path = '/earth$qs');
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
    final api = ApiScope.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DilixWebView(
              key: ValueKey(_path),
              api: api,
              path: _path,
              fallbackBuilder: _fallbackGlobe,
            ),
          ),
          // نوارِ جستجوی شناور + دکمهٔ فیلتر.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _searchBar(),
          ),
          // FABِ دستیارِ هوشمند در پایین‌چپ (مثلِ نمای وب).
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            child: FloatingActionButton(
              heroTag: 'earth-assistant',
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              onPressed: _openAssistant,
              child: const Icon(Icons.smart_toy),
            ),
          ),
        ],
      ),
    );
  }

  /// گشودنِ دستیارِ هوشمندِ سراسری به‌صورتِ شیتِ پایین.
  void _openAssistant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AssistantSheet(),
    );
  }

  /// نمایِ جایگزین وقتی WebView در دسترس نیست (تست یا بدونِ شبکه).
  Widget _fallbackGlobe(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [Color(0xFF1B3A6B), Color(0xFF070B1A)],
        ),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🌍', style: TextStyle(fontSize: 96)),
          SizedBox(height: 8),
          Text('کره‌ی سه‌بعدی روی دستگاه بارگذاری می‌شود',
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
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'جستجوی نام یا Earth ID…',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              tooltip: 'تصویر',
              onPressed: _search,
              icon: const Icon(Icons.image),
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
}
