// `Badge` مدلِ ماست؛ ویجتِ هم‌نامِ Material را پنهان می‌کنیم تا ابهام نشود.
import 'package:flutter/material.dart' hide Badge;

import '../../app.dart';
import '../../models/models.dart';

/// دستاوردها: امتیازِ پاداش + نوارِ پیشرفت + نشان‌ها.
/// معادلِ صفحهٔ وبِ `app/gamification` (امتیازِ من + فهرستِ نشان‌ها).
class GamificationScreen extends StatefulWidget {
  const GamificationScreen({super.key});

  @override
  State<GamificationScreen> createState() => _GamificationScreenState();
}

class _GamificationScreenState extends State<GamificationScreen> {
  // پله‌ی امتیاز برای محاسبه‌ی نوارِ پیشرفت (نمایشی، مشتق از موجودی).
  static const _tierSize = 1000;

  int? _points;
  List<Badge> _badges = const [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      final points = await api.rewardPoints();
      // نشان‌ها اختیاری‌اند؛ نبودشان نباید صفحه را بشکند.
      List<Badge> badges = const [];
      try {
        badges = await api.gamificationBadges();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _points = points;
        _badges = badges;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ امتیازها ممکن نشد. ابتدا وارد شوید.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دستاوردها'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تازه‌سازی',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    'امتیازهای فعالیت و نشان‌های کسب‌شده',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  _pointsCard(),
                  _badgesCard(),
                ],
              ),
            ),
    );
  }

  Widget _pointsCard() {
    final points = _points ?? 0;
    final tierProgress = (points % _tierSize) / _tierSize;
    final nextTier = ((points ~/ _tierSize) + 1) * _tierSize;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('امتیازِ من', style: TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text('$points')),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: tierProgress,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'تا پله‌ی بعدی: ${nextTier - points} امتیاز',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('نشان‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_badges.isEmpty)
              Text('هنوز نشانی کسب نشده است.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _badges
                    .map((b) => Chip(
                          avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                          label: Text(b.description ?? b.badgeCode),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
