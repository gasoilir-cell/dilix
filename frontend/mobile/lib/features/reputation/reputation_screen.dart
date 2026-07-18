import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// اعتبار: امتیازِ اعتماد به‌تفکیکِ حوزه + ستاره‌ها + نظرهای دریافتی.
/// معادلِ صفحهٔ وبِ `app/reputation` (بر پایه‌ی تراکنش‌های واقعی).
class ReputationScreen extends StatefulWidget {
  const ReputationScreen({super.key});

  @override
  State<ReputationScreen> createState() => _ReputationScreenState();
}

class _ReputationScreenState extends State<ReputationScreen> {
  List<ReputationScore> _scores = const [];
  List<Review> _reviews = const [];
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
      final me = await api.me();
      // هر دو اختیاری‌اند؛ نبودشان نباید صفحه را بشکند.
      List<ReputationScore> scores = const [];
      List<Review> reviews = const [];
      try {
        scores = await api.reputationScores(me.earthId);
      } catch (_) {}
      try {
        reviews = await api.reputationReviews(me.earthId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _scores = scores;
        _reviews = reviews;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ اعتبار ممکن نشد. ابتدا وارد شوید.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اعتبار'),
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
                    'امتیازِ اعتبار و نظرهای دریافتی (بر پایه‌ی تراکنش‌های واقعی)',
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
                  _scoresCard(),
                  _reviewsCard(),
                ],
              ),
            ),
    );
  }

  Widget _scoresCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('امتیازِ اعتبار', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_scores.isEmpty)
              Text('هنوز امتیازی ثبت نشده است.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ..._scores.map(
                (s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.domain),
                      Text(
                        '${(s.score / 10).toStringAsFixed(1)}/۱۰ · ${s.reviewCount} نظر',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reviewsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('نظرهای دریافتی', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_reviews.isEmpty)
              Text('هنوز نظری ثبت نشده است.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ..._reviews.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('⭐' * r.rating),
                          Text(r.domain, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      if (r.comment != null && r.comment!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(r.comment!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
