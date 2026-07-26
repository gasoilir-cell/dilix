import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'post_card.dart';

import '../../core/l10n.dart';
/// «لحظه‌ها» — پست‌های دارای موقعیت روی کره (`GET /api/v1/posts/moments`).
///
/// اگر [bounds] داده شود فقط لحظه‌های همان محدوده خوانده می‌شوند؛ وگرنه
/// جدیدترین لحظه‌های کلِ کره.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key, this.bounds});

  /// `(minLat, maxLat, minLng, maxLng)`.
  final (double, double, double, double)? bounds;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  List<Post>? _posts;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_posts == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final b = widget.bounds;
      final list = await ApiScope.of(context).moments(
        minLat: b?.$1,
        maxLat: b?.$2,
        minLng: b?.$3,
        maxLng: b?.$4,
      );
      if (!mounted) return;
      setState(() {
        _posts = list;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('لحظه‌ها')),
        actions: [
          IconButton(
            tooltip: tr('تازه‌سازی'),
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('بارگذاری ممکن نشد.\n{0}', [_error]),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _load, child: Text(tr('تلاشِ دوباره'))),
                  ],
                ),
              ),
            )
          : posts == null
              ? const Center(child: CircularProgressIndicator())
              : posts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          tr('هنوز لحظه‌ای روی کره ثبت نشده.\nهنگامِ انتشارِ پست موقعیت را اضافه کنید تا این‌جا دیده شود.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: posts.length,
                        itemBuilder: (_, i) {
                          final p = posts[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (p.placeName != null || p.hasLocation)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 0, 4, 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.place_outlined, size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          p.placeName ?? _coords(p),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              PostCard(
                                key: ValueKey(p.id),
                                post: p,
                                onDeleted: () => setState(() =>
                                    posts.removeWhere((e) => e.id == p.id)),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
    );
  }

  static String _coords(Post p) =>
      '${p.lat!.toStringAsFixed(3)}, ${p.lng!.toStringAsFixed(3)}';
}
