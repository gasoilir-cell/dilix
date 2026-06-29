import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Post>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = ApiScope.of(context).feed();
  }

  Future<void> _refresh() async {
    setState(() => _future = ApiScope.of(context).feed());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خانه')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Post>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Message(text: 'بارگذاری فید ممکن نشد.\n${snap.error}');
            }
            final posts = snap.data ?? const [];
            if (posts.isEmpty) {
              return const _Message(text: 'هنوز پستی نیست.');
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: posts.length,
              itemBuilder: (context, i) {
                final p = posts[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${p.authorEarthId.substring(0, 8)}…',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(p.postType, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        if (p.content != null) ...[
                          const SizedBox(height: 8),
                          Text(p.content!),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.thumb_up_alt_outlined, size: 18),
                            const SizedBox(width: 4),
                            Text('${p.reactionCounts['like'] ?? 0}'),
                            const SizedBox(width: 16),
                            const Icon(Icons.mode_comment_outlined, size: 18),
                            const SizedBox(width: 4),
                            Text('${p.commentCount}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
