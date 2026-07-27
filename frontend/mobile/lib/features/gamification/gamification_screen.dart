import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';

/// دستاوردها: امتیاز، سطح، ورودِ روزانه، نشان‌ها و تابلوی رتبه.
/// معادلِ صفحهٔ وبِ `/rewards` و روی همان اندپوینت‌های زندهٔ
/// `/api/v1/gamification` می‌نشیند (نه سرویسِ `core`).
class GamificationScreen extends StatefulWidget {
  const GamificationScreen({super.key});

  @override
  State<GamificationScreen> createState() => _GamificationScreenState();
}

enum _Tab { badges, board, history }

class _GamificationScreenState extends State<GamificationScreen> {
  GameProfile? _profile;
  Leaderboard? _board;
  List<PointEvent> _history = const [];

  _Tab _tab = _Tab.badges;
  String _period = 'all';

  bool _loading = true;
  bool _busy = false;
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
    try {
      final profile = await ApiScope.of(context).gameProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ امتیازها ممکن نشد. ابتدا وارد شوید.');
        _loading = false;
      });
    }
  }

  /// تابلوی رتبه و دفتر فقط وقتی تبشان باز می‌شود بار می‌شوند.
  Future<void> _loadTab(_Tab tab) async {
    final api = ApiScope.of(context);
    try {
      if (tab == _Tab.board) {
        final board = await api.gameLeaderboard(period: _period);
        if (mounted) setState(() => _board = board);
      } else if (tab == _Tab.history) {
        final rows = await api.gameHistory(limit: 60);
        if (mounted) setState(() => _history = rows);
      }
    } catch (_) {
      if (mounted) _snack(tr('دریافتِ اطلاعات ممکن نشد.'));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      final r = await ApiScope.of(context).gameCheckIn();
      _snack(r.already
          ? tr('امروز قبلاً وارد شده‌اید.')
          : tr('+{0} امتیاز — زنجیرهٔ {1} روزه', [r.gained, r.streakDays]));
      await _load();
    } catch (_) {
      _snack(tr('ثبتِ ورودِ روزانه ناموفق بود.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final r = await ApiScope.of(context).gameSyncBadges();
      _snack(r.awarded.isEmpty
          ? tr('نشانِ تازه‌ای آماده نیست.')
          : tr('{0} نشانِ تازه — +{1} امتیاز', [r.awarded.length, r.gained]));
      await _load();
    } catch (_) {
      _snack(tr('دریافتِ نشان‌ها ممکن نشد.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('دستاوردها')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: tr('تازه‌سازی'),
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
                  if (_profile != null) ...[
                    _levelCard(_profile!),
                    const SizedBox(height: 8),
                    SegmentedButton<_Tab>(
                      segments: [
                        ButtonSegment(value: _Tab.badges, label: Text(tr('نشان‌ها'))),
                        ButtonSegment(value: _Tab.board, label: Text(tr('رتبه‌ها'))),
                        ButtonSegment(value: _Tab.history, label: Text(tr('دفتر'))),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) {
                        setState(() => _tab = s.first);
                        _loadTab(s.first);
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_tab == _Tab.badges) ..._profile!.badges.map(_badgeTile),
                    if (_tab == _Tab.board) ..._boardSection(),
                    if (_tab == _Tab.history) ..._historySection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _levelCard(GameProfile p) {
    final lv = p.level;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    tr('سطحِ {0} — {1}', [lv.level, lv.title]),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (p.rank != null) Chip(label: Text(tr('رتبهٔ {0}', [p.rank!]))),
              ],
            ),
            const SizedBox(height: 4),
            Text('${p.points}', style: Theme.of(context).textTheme.headlineSmall),
            Text(tr('امتیاز'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: lv.progressPct / 100,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              lv.nextAt == null
                  ? tr('به بالاترین سطح رسیده‌اید.')
                  : tr('تا سطحِ بعد: {0} امتیاز', [lv.toNext]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.local_fire_department_outlined, size: 18),
                  label: Text(tr('زنجیره: {0}', [p.streakDays])),
                ),
                Chip(
                  avatar: const Icon(Icons.military_tech_outlined, size: 18),
                  label: Text(tr('بیشینه: {0}', [p.longestStreak])),
                ),
                Chip(
                  avatar: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: Text(tr('نشان: {0} از {1}', [p.badgesEarned, p.badgesTotal])),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_busy || p.checkedInToday) ? null : _checkIn,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(p.checkedInToday
                        ? tr('امروز ثبت شد')
                        : tr('ورودِ روزانه')),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _sync,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(tr('دریافتِ نشان')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeTile(GameBadge b) {
    return Card(
      child: ListTile(
        leading: Icon(
          b.earned ? Icons.emoji_events : Icons.emoji_events_outlined,
          color: b.earned ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(b.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.description, style: Theme.of(context).textTheme.bodySmall),
            if (!b.earned) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: b.ratio, minHeight: 6),
              ),
              const SizedBox(height: 4),
              Text('${b.progress} / ${b.target}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        trailing: Text('+${b.points}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        isThreeLine: !b.earned,
      ),
    );
  }

  List<Widget> _boardSection() {
    final board = _board;
    return [
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'all', label: Text(tr('کلِ زمان'))),
          ButtonSegment(value: 'week', label: Text(tr('این هفته'))),
        ],
        selected: {_period},
        onSelectionChanged: (s) {
          setState(() => _period = s.first);
          _loadTab(_Tab.board);
        },
      ),
      const SizedBox(height: 8),
      if (board == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (board.rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('هنوز کسی امتیازی نگرفته است.'), textAlign: TextAlign.center),
        )
      else ...[
        ...board.rows.map((r) => Card(
              color: r.isMe ? Theme.of(context).colorScheme.primaryContainer : null,
              child: ListTile(
                leading: CircleAvatar(child: Text('${r.rank}')),
                title: Text(r.name),
                subtitle: Text(tr('سطحِ {0}', [r.level])),
                trailing: Text('${r.points}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            )),
        if (board.myRank != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              tr('رتبهٔ شما: {0} — {1} امتیاز', [board.myRank!, board.myPoints]),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ];
  }

  List<Widget> _historySection() {
    if (_history.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('هنوز امتیازی ثبت نشده است.'), textAlign: TextAlign.center),
        ),
      ];
    }
    return _history
        .map((h) => Card(
              child: ListTile(
                dense: true,
                title: Text(h.note ?? h.kindLabel),
                subtitle: Text(h.kindLabel,
                    style: Theme.of(context).textTheme.bodySmall),
                trailing: Text('+${h.delta}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ))
        .toList();
  }
}
