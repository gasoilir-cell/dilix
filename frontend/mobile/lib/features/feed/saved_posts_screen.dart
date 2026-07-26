import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'post_card.dart';

import '../../core/l10n.dart';
/// پست‌های ذخیره‌شدهٔ خودم (`GET /api/v1/posts/saved`).
class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Post>? _posts;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_posts == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).savedPosts();
      if (mounted) {
        setState(() {
          _posts = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ذخیره‌شده‌ها'))),
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
                          tr('چیزی ذخیره نکرده‌اید.\nبا نشانِ بوکمارک روی هر پست آن را این‌جا نگه دارید.'),
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
                          return PostCard(
                            key: ValueKey(p.id),
                            post: p,
                            onDeleted: () => setState(
                                () => posts.removeWhere((e) => e.id == p.id)),
                          );
                        },
                      ),
                    ),
    );
  }
}
