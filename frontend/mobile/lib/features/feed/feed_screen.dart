import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// فیدِ اجتماعی: نمایشِ پست‌ها + رسانه، ساختِ پست (متن + رسانه با URL)،
/// لایک و نظر. معادلِ صفحهٔ وبِ `app/social/page.tsx`.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final List<Post> _posts = [];
  bool _loading = true;
  bool _publishing = false;
  String? _error;
  final _draftCtrl = TextEditingController();
  final List<Map<String, dynamic>> _draftMedia = [];
  final Map<String, TextEditingController> _commentCtrls = {};
  String? _commentFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    for (final c in _commentCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await ApiScope.of(context).feed();
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاری فید ممکن نشد.\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _publish() async {
    final content = _draftCtrl.text.trim();
    if (content.isEmpty && _draftMedia.isEmpty) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    final postType = _draftMedia.any((m) => (m['type'] as String?) == 'video')
        ? 'video'
        : _draftMedia.isNotEmpty
            ? 'image'
            : 'text';
    try {
      final post = await ApiScope.of(context).createPost(
        postType: postType,
        content: content.isEmpty ? null : content,
        media: List<Map<String, dynamic>>.from(_draftMedia),
      );
      if (!mounted) return;
      setState(() {
        _posts.insert(0, post);
        _draftCtrl.clear();
        _draftMedia.clear();
        _publishing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ارسال پست ناموفق بود. ابتدا وارد شوید.';
        _publishing = false;
      });
    }
  }

  Future<void> _addMediaByUrl() async {
    final item = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _MediaUrlSheet(),
    );
    if (item != null && mounted) {
      setState(() => _draftMedia.add(item));
    }
  }

  Future<void> _like(Post post) async {
    try {
      final updated = await ApiScope.of(context).reactToPost(post.id);
      if (!mounted) return;
      setState(() {
        final i = _posts.indexWhere((p) => p.id == post.id);
        if (i >= 0) _posts[i] = updated;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ثبتِ واکنش ممکن نشد. ابتدا وارد شوید.');
    }
  }

  Future<void> _sendComment(Post post) async {
    final ctrl = _commentCtrls[post.id];
    final text = ctrl?.text.trim() ?? '';
    if (text.isEmpty) return;
    try {
      await ApiScope.of(context).commentOnPost(post.id, text);
      if (!mounted) return;
      setState(() {
        final i = _posts.indexWhere((p) => p.id == post.id);
        if (i >= 0) _posts[i] = _posts[i].copyWithCommentCount(_posts[i].commentCount + 1);
        ctrl?.clear();
        _commentFor = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ثبتِ نظر ممکن نشد. ابتدا وارد شوید.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خانه')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _composer(),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('هنوز پستی نیست.', textAlign: TextAlign.center),
                    )
                  else
                    ..._posts.map(_postCard),
                ],
              ),
      ),
    );
  }

  Widget _composer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _draftCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'چه خبر؟',
                border: OutlineInputBorder(),
              ),
            ),
            if (_draftMedia.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _draftMedia.length; i++)
                    Chip(
                      avatar: Icon(
                        (_draftMedia[i]['type'] as String?) == 'video'
                            ? Icons.videocam_outlined
                            : Icons.image_outlined,
                        size: 18,
                      ),
                      label: Text('رسانه ${i + 1}'),
                      onDeleted: () => setState(() => _draftMedia.removeAt(i)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _addMediaByUrl,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('افزودنِ رسانه'),
                ),
                FilledButton(
                  onPressed: _publishing ? null : _publish,
                  child: Text(_publishing ? '…' : 'انتشار'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(Post p) {
    final ctrl = _commentCtrls.putIfAbsent(p.id, TextEditingController.new);
    final mediaUrls = <String>[
      for (final m in p.media)
        if ((m['url'] ?? m['media_url']) is String) (m['url'] ?? m['media_url']) as String,
    ];
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
                  '${p.authorEarthId.length >= 8 ? p.authorEarthId.substring(0, 8) : p.authorEarthId}…',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(p.postType, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (p.content != null) ...[
              const SizedBox(height: 8),
              Text(p.content!),
            ],
            for (final u in mediaUrls) _mediaWidget(u, p),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _like(p),
                  icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                  label: Text('${p.reactionCounts['like'] ?? 0}'),
                ),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _commentFor = _commentFor == p.id ? null : p.id,
                  ),
                  icon: const Icon(Icons.mode_comment_outlined, size: 18),
                  label: Text('${p.commentCount}'),
                ),
              ],
            ),
            if (_commentFor == p.id)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: 'نظر خود را بنویسید…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => _sendComment(p),
                    child: const Text('ارسال'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaWidget(String url, Post p) {
    final isVideo = p.postType == 'video' || url.toLowerCase().contains('.mp4');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isVideo
            ? Container(
                height: 180,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.play_circle_outline, size: 48)),
              )
            : Image.network(
                url,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
      ),
    );
  }
}

/// bottom-sheet برای افزودنِ رسانه به‌کمکِ URL (بدونِ نیاز به پلاگینِ انتخابِ فایل).
class _MediaUrlSheet extends StatefulWidget {
  const _MediaUrlSheet();

  @override
  State<_MediaUrlSheet> createState() => _MediaUrlSheetState();
}

class _MediaUrlSheetState extends State<_MediaUrlSheet> {
  final _urlCtrl = TextEditingController();
  String _type = 'image';

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('افزودنِ رسانه (URL)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(labelText: 'نشانیِ تصویر یا ویدیو'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'نوع'),
            items: const [
              DropdownMenuItem(value: 'image', child: Text('تصویر')),
              DropdownMenuItem(value: 'video', child: Text('ویدیو')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'image'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final url = _urlCtrl.text.trim();
                if (url.isEmpty) return;
                Navigator.of(context).pop(<String, dynamic>{'url': url, 'type': _type});
              },
              child: const Text('افزودن'),
            ),
          ),
        ],
      ),
    );
  }
}
