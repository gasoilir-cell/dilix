import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'post_card.dart';

import '../../core/l10n.dart';
/// کشفِ پست‌ها: «کشف» (عمومی)، «برای تو» (بر پایهٔ علاقه‌مندی‌ها)، جستجوی متنی
/// و هشتگ‌های پرتکرار.
///
/// جستجو با تایپ debounce می‌شود و پاسخ‌های دیررسِ عبارتِ قبلی دور ریخته می‌شوند
/// (همان الگوی `PeopleScreen`).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<Post>? _posts;
  List<Topic>? _topics;
  String? _error;
  bool _forYou = false;
  String? _activeTag;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_posts == null && _error == null) {
      _load();
      _loadTopics();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    try {
      final t = await ApiScope.of(context).topics(limit: 12);
      if (mounted) setState(() => _topics = t);
    } catch (_) {
      if (mounted) setState(() => _topics = const []);
    }
  }

  /// بارگذاریِ فهرست بر اساسِ وضعیتِ جاری (جستجو > هشتگ > تب).
  Future<void> _load() async {
    final api = ApiScope.of(context);
    final q = _ctrl.text.trim();
    final tag = _activeTag;
    setState(() => _error = null);
    try {
      final list = q.isNotEmpty
          ? await api.searchPosts(q)
          : tag != null
              ? await api.topicPosts(tag)
              : _forYou
                  ? await api.interestPosts()
                  : await api.explorePosts();
      // اگر کاربر در این فاصله عبارت را عوض کرده، پاسخ کهنه است.
      if (!mounted || _ctrl.text.trim() != q || _activeTag != tag) return;
      setState(() => _posts = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onQueryChanged(String _) {
    setState(() {}); // برای نمایش/حذفِ دکمهٔ پاک‌کردن
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() => _activeTag = null);
        _load();
      }
    });
  }

  void _selectTab(bool forYou) {
    if (_forYou == forYou && _activeTag == null && _ctrl.text.isEmpty) return;
    setState(() {
      _forYou = forYou;
      _activeTag = null;
      _posts = null;
      _ctrl.clear();
    });
    _load();
  }

  void _selectTag(String? tag) {
    setState(() {
      _activeTag = tag;
      _posts = null;
      _ctrl.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('کشف'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _ctrl,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: tr('جستجو در پست‌ها…'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _ctrl.clear();
                          _load();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          if (_ctrl.text.trim().isEmpty) _filters(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _filters() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            ChoiceChip(
              label: Text(tr('کشف')),
              selected: !_forYou && _activeTag == null,
              onSelected: (_) => _selectTab(false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(tr('برای تو')),
              selected: _forYou && _activeTag == null,
              onSelected: (_) => _selectTab(true),
            ),
            for (final t in _topics ?? const <Topic>[]) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('#${t.tag} (${t.postCount})'),
                selected: _activeTag == t.tag,
                onSelected: (sel) => _selectTag(sel ? t.tag : null),
              ),
            ],
          ],
        ),
      );

  Widget _body() {
    if (_error != null) {
      return _Centered(
        text: tr('بارگذاری ممکن نشد.\n{0}', [_error]),
        onRetry: _load,
      );
    }
    final posts = _posts;
    if (posts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return _Centered(
        text: _ctrl.text.trim().isEmpty
            ? tr('اینجا هنوز پستی نیست.')
            : tr('برای «{0}» چیزی پیدا نشد.', [_ctrl.text.trim()]),
        onRetry: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length,
        itemBuilder: (_, i) {
          final p = posts[i];
          return PostCard(
            key: ValueKey(p.id),
            post: p,
            onDeleted: () =>
                setState(() => posts.removeWhere((e) => e.id == p.id)),
          );
        },
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              if (onRetry != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                      onPressed: onRetry, child: Text(tr('تلاشِ دوباره'))),
                ),
            ],
          ),
        ),
      );
}
