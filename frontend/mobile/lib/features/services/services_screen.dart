import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// هابِ verticalها (سند ۷ §۲): حمل‌ونقل، بیمه، ارتباطات، بازارگاه.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <_Service>[
      _Service(Icons.local_shipping_outlined, 'حمل‌ونقل', 'اسنپِ بار', const FreightScreen()),
      _Service(Icons.shield_outlined, 'بیمه', 'استعلام و صدور', null),
      _Service(Icons.signal_cellular_alt, 'ارتباطات', 'اینترنت و eSIM', null),
      _Service(Icons.storefront_outlined, 'بازارگاه', 'خدمات و فریلنسری', null),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('خدمات')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(12),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: tiles
            .map((s) => Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: s.screen == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => s.screen!),
                            ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(s.icon, size: 32),
                          const SizedBox(height: 8),
                          Text(s.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(s.desc, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Service {
  _Service(this.icon, this.title, this.desc, this.screen);
  final IconData icon;
  final String title;
  final String desc;
  final Widget? screen;
}

/// فهرستِ بارهای باز (اسنپِ بار) — سند ۷ §۵.
class FreightScreen extends StatefulWidget {
  const FreightScreen({super.key});

  @override
  State<FreightScreen> createState() => _FreightScreenState();
}

class _FreightScreenState extends State<FreightScreen> {
  late Future<List<CargoPost>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = ApiScope.of(context).listCargo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بارهای باز')),
      body: FutureBuilder<List<CargoPost>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('بارگذاری ممکن نشد.\n${snap.error}', textAlign: TextAlign.center));
          }
          final cargo = snap.data ?? const [];
          if (cargo.isEmpty) {
            return const Center(child: Text('باری برای نمایش نیست.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: cargo.length,
            itemBuilder: (context, i) {
              final c = cargo[i];
              return Card(
                child: ListTile(
                  title: Text(c.title),
                  subtitle: Text('${c.origin} ← ${c.destination}'),
                  trailing: Chip(label: Text(c.status)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
