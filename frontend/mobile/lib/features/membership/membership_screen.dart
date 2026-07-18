// `Badge` مدلِ ماست؛ ویجتِ هم‌نامِ Material را پنهان می‌کنیم تا ابهام نشود.
import 'package:flutter/material.dart' hide Badge;

import '../../app.dart';
import '../../models/models.dart';

/// عضویت + گیمیفیکیشن (نشان‌ها) + اعتبار (امتیاز/نظرها).
/// معادلِ صفحه‌هایِ وبِ `app/membership`, `app/gamification`, `app/reputation`.
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  static const _plans = ['free', 'standard', 'premium'];

  Membership? _membership;
  List<Badge> _badges = const [];
  List<ReputationScore> _scores = const [];
  List<Review> _reviews = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

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
      final membership = await api.membership();
      // بخش‌های زیر اختیاری‌اند؛ نبودشان نباید صفحه را بشکند.
      List<Badge> badges = const [];
      List<ReputationScore> scores = const [];
      List<Review> reviews = const [];
      try {
        badges = await api.gamificationBadges();
      } catch (_) {}
      try {
        final me = await api.me();
        scores = await api.reputationScores(me.earthId);
        reviews = await api.reputationReviews(me.earthId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _membership = membership;
        _badges = badges;
        _scores = scores;
        _reviews = reviews;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ عضویت ممکن نشد: $e';
        _loading = false;
      });
    }
  }

  Future<void> _upgrade(String plan) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await ApiScope.of(context).upgradeMembership(plan);
      if (!mounted) return;
      setState(() {
        _membership = updated;
        _notice = 'پلن به «$plan» تغییر کرد.';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تغییرِ پلن ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await ApiScope.of(context).cancelMembership();
      if (!mounted) return;
      setState(() {
        _membership = updated;
        _notice = 'عضویت لغو شد و به پلنِ رایگان بازگشتید.';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'لغوِ عضویت ناموفق بود: $e';
        _busy = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عضویت و اعتبار'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تلاشِ مجدد',
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
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_notice != null)
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_notice!),
                      ),
                    ),
                  _membershipCard(),
                  _plansCard(),
                  _badgesCard(),
                  _reputationCard(),
                ],
              ),
            ),
    );
  }

  Widget _membershipCard() {
    final m = _membership;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('عضویتِ فعلی', style: TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text(m?.plan ?? 'free')),
              ],
            ),
            const SizedBox(height: 6),
            Text('وضعیت: ${m?.status ?? '—'}', style: Theme.of(context).textTheme.bodySmall),
            Text(
              'بازگشتِ نقدی: ${((m?.cashbackBps ?? 0) / 100).toStringAsFixed(2)}٪',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (m?.expiresAt != null)
              Text(
                'انقضا: ${_formatDate(m!.expiresAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (m != null && m.plan != 'free') ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _cancel,
                child: const Text('لغوِ عضویت'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _plansCard() {
    final current = _membership?.plan ?? 'free';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('پلن‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._plans.map(
              (plan) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(plan),
                    plan == current
                        ? const Chip(label: Text('فعال'))
                        : FilledButton.tonal(
                            onPressed: _busy ? null : () => _upgrade(plan),
                            child: const Text('انتخاب'),
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
              Text('هنوز نشانی کسب نشده است.', style: Theme.of(context).textTheme.bodySmall)
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

  Widget _reputationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اعتبار', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_scores.isEmpty)
              Text('هنوز امتیازِ اعتباری ثبت نشده است.',
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
                        '${s.score}/10 · ${s.reviewCount} نظر',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            if (_reviews.isNotEmpty) ...[
              const Divider(height: 20),
              const Text('نظرهای اخیر', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ..._reviews.take(5).map(
                    (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${'⭐' * r.rating} · ${r.domain}'),
                          if (r.comment != null && r.comment!.isNotEmpty)
                            Text(r.comment!, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
