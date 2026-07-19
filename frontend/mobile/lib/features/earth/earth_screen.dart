import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../assistant/assistant_sheet.dart';

/// کشفِ افراد/کسب‌وکار روی کره (امضای محصول، سند ۷ §۳).
/// کره‌ی سه‌بعدیِ واقعی روی خودِ دستگاه با `globe.gl` رندر می‌شود (HTMLِ
/// خودبسنده داخلِ [WebView]، نه بارگذاریِ اپِ وب). پین‌های کاربرانِ opt-in با
/// حریمِ خصوصی (مختصاتِ fuzzed، فقط سطحِ منطقه) روی کره نمایش داده می‌شوند.
class EarthScreen extends StatefulWidget {
  const EarthScreen({super.key});

  @override
  State<EarthScreen> createState() => _EarthScreenState();
}

class _EarthScreenState extends State<EarthScreen> {
  final _countryCtrl = TextEditingController();
  final _queryCtrl = TextEditingController();
  String _entityType = '';
  List<NearbyPerson> _results = const [];
  bool _loading = false;
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    _initWebView();
    // نمایشِ اولیهٔ کاربران بدونِ نیاز به فشردنِ دکمه.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  /// ساختِ کنترلرِ WebView و بارگذاریِ کره‌ی خودبسنده؛ در محیطِ تست یا پلتفرمِ
  /// بدونِ WebView به‌آرامی شکست می‌خورد و نمایِ جایگزین (کره‌ی گرادیانی) می‌ماند.
  void _initWebView() {
    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B1026))
        ..addJavaScriptChannel('DilixGlobe',
            onMessageReceived: (m) => _startChatByEarthId(m.message))
        ..loadHtmlString(_globeHtml(const []));
      _web = c;
    } catch (_) {
      _web = null;
    }
  }

  /// چاپِ دوبارهٔ کره با پین‌های به‌روزشده (بدونِ reloadِ کاملِ HTML، از طریقِ
  /// تابعِ `dilixSetPoints` که در HTML تعریف شده است).
  void _renderGlobe() {
    final w = _web;
    if (w == null) return;
    final data = jsonEncode([
      for (final p in _results)
        {
          'lat': p.lat,
          'lng': p.lon,
          'name': p.displayName ?? p.earthId,
          'earthId': p.earthId,
        }
    ]);
    // اگر تابع هنوز آماده نبود (بارگذاریِ globe.gl)، خطا نادیده گرفته می‌شود.
    w.runJavaScript('window.dilixSetPoints && window.dilixSetPoints($data);');
  }

  void _startChatByEarthId(String earthId) {
    final match = _results.where((p) => p.earthId == earthId);
    if (match.isEmpty) return;
    _startChat(match.first);
  }

  /// HTMLِ خودبسنده‌ی کره با `globe.gl` (بارگذاریِ three از CDN). نقاط از طریقِ
  /// `dilixSetPoints` تزریق می‌شوند و کلیک روی هر پین earthId را به Flutter
  /// (کانالِ `DilixGlobe`) می‌فرستد.
  String _globeHtml(List<Map<String, dynamic>> points) {
    final initial = jsonEncode(points);
    return '''
<!DOCTYPE html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
<style>html,body{margin:0;height:100%;background:#0B1026;overflow:hidden}#globe{width:100vw;height:100vh}</style>
<script src="https://unpkg.com/globe.gl"></script>
</head><body>
<div id="globe"></div>
<script>
  var world = null;
  // مرکزِ تقریبیِ هر کشور برای برچسب‌گذاری (میانگینِ رئوسِ چندضلعی).
  function polyCentroid(geometry){
    var polys = geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates;
    var sx = 0, sy = 0, n = 0;
    polys.forEach(function(poly){
      poly[0].forEach(function(pt){ sx += pt[0]; sy += pt[1]; n++; });
    });
    return n ? { lng: sx / n, lat: sy / n } : { lng: 0, lat: 0 };
  }
  function addCountries(){
    fetch('https://raw.githubusercontent.com/vasturiano/globe.gl/master/example/datasets/ne_110m_admin_0_countries.geojson')
      .then(function(r){ return r.json(); })
      .then(function(geo){
        var feats = geo.features || [];
        // مرزها: چندضلعی‌های شفاف با خطِ مرزیِ روشن (مثلِ نمای وب).
        world.polygonsData(feats)
          .polygonCapColor(function(){ return 'rgba(0,0,0,0)'; })
          .polygonSideColor(function(){ return 'rgba(0,0,0,0)'; })
          .polygonStrokeColor(function(){ return 'rgba(255,255,255,0.35)'; })
          .polygonAltitude(0.006);
        // نامِ کشورها به‌صورتِ برچسبِ سفیدِ کوچک در مرکزِ هر کشور.
        var labels = feats.map(function(f){
          var c = polyCentroid(f.geometry);
          return { lat: c.lat, lng: c.lng, text: (f.properties && (f.properties.NAME || f.properties.name)) || '' };
        });
        world.labelsData(labels)
          .labelLat('lat').labelLng('lng').labelText('text')
          .labelSize(0.42).labelDotRadius(0.0)
          .labelColor(function(){ return 'rgba(255,255,255,0.75)'; })
          .labelResolution(1);
      })
      .catch(function(){ /* بدونِ شبکه، فقط کره و پین‌ها می‌مانند. */ });
  }
  function build(points){
    if(!window.Globe){ setTimeout(function(){build(points)}, 300); return; }
    world = Globe()(document.getElementById('globe'))
      .globeImageUrl('https://unpkg.com/three-globe/example/img/earth-blue-marble.jpg')
      .bumpImageUrl('https://unpkg.com/three-globe/example/img/earth-topology.png')
      .backgroundColor('#0B1026')
      .showAtmosphere(true)
      .atmosphereColor('#5B8DEF')
      .atmosphereAltitude(0.18)
      .pointsData(points)
      .pointLat('lat').pointLng('lng')
      .pointColor(function(){return '#FF7A00'})
      .pointAltitude(0.03).pointRadius(0.5)
      .pointLabel(function(d){return d.name})
      .onPointClick(function(d){ if(window.DilixGlobe){ DilixGlobe.postMessage(d.earthId);} });
    // دوربین روی کلِ کره تنظیم می‌شود (ایران وسط) تا کره کامل و نه فلت دیده شود.
    world.pointOfView({ lat: 32, lng: 53, altitude: 2.5 }, 0);
    var c = world.controls(); if(c){ c.autoRotate=true; c.autoRotateSpeed=0.3; }
    addCountries();
  }
  window.dilixSetPoints = function(points){
    if(world){ world.pointsData(points); } else { build(points); }
  };
  build($initial);
</script>
</body></html>''';
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final res = await ApiScope.of(context).earthUsers(
        type: _entityType,
        country: _countryCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _results = res);
      _renderGlobe();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('جست‌وجو ممکن نشد: $e')),
      );
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
            child: Column(
              children: [
                _searchBar(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
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
