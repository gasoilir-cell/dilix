import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// کشفِ اطراف: یافتنِ افراد/کسب‌وکارهای نزدیک بر پایهٔ bbox + حرفه، و
/// ارسالِ درخواستِ ارتباط. معادلِ صفحهٔ وبِ `app/services/discovery/page.tsx`.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _professionCtrl = TextEditingController();
  final List<NearbyPerson> _people = [];
  final Set<String> _sentTo = {};
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _professionCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      var people = await ApiScope.of(context).earthUsers();
      // فیلترِ محلیِ اختیاری بر پایهٔ متنِ واردشده (شهر/نام).
      final q = _professionCtrl.text.trim();
      if (q.isNotEmpty) {
        people = people
            .where((p) =>
                (p.profession ?? '').contains(q) ||
                (p.displayName ?? '').contains(q))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _people
          ..clear()
          ..addAll(people);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ فهرستِ اطراف ممکن نشد. ابتدا وارد شوید.';
        _loading = false;
      });
    }
  }

  Future<void> _contact(NearbyPerson person) async {
    try {
      await ApiScope.of(context).createDirectRoom(person.earthId);
      if (!mounted) return;
      setState(() => _sentTo.add(person.earthId));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'شروعِ گفتگو ناموفق بود.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('کشفِ اطراف')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'یافتنِ افراد و کسب‌وکارهای نزدیک بر پایهٔ موقعیت',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _filterCard(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searched && _people.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('کسی در این محدوده یافت نشد.', textAlign: TextAlign.center),
            )
          else
            ..._people.map(_personCard),
        ],
      ),
    );
  }

  Widget _filterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _professionCtrl,
              decoration: const InputDecoration(labelText: 'نام یا شهر (اختیاری)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _search,
                child: Text(_loading ? 'در حال…' : 'جستجو'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personCard(NearbyPerson p) {
    final meta = <String>[
      if (p.profession != null && p.profession!.isNotEmpty) p.profession!,
      if (p.ageRange != null && p.ageRange!.isNotEmpty) p.ageRange!,
      if (p.languages.isNotEmpty) p.languages.join('، '),
    ];
    final sent = _sentTo.contains(p.earthId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  p.displayName ?? 'کاربرِ ناشناس',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Chip(label: Text(p.entityType)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              meta.isEmpty ? '—' : meta.join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: sent ? null : () => _contact(p),
              child: Text(sent ? 'گفتگو باز شد' : 'گفتگو'),
            ),
          ],
        ),
      ),
    );
  }
}
