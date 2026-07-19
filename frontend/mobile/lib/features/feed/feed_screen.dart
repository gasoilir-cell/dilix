import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../models/models.dart';

/// فیدِ اجتماعی: نمایشِ پست‌ها + رسانه، ساختِ پست با انتخابِ تصویر/ویدیو از
/// حافظهٔ گوشی (آپلودِ multipart به `/api/v1/posts`)، لایک و نظر.
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
  final _picker = ImagePicker();
  XFile? _pickedFile;
  bool _pickedIsVideo = false;
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

  Future<void> _pickImage() async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (f != null && mounted) {
      setState(() {
        _pickedFile = f;
        _pickedIsVideo = false;
      });
    }
  }

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null && mounted) {
      setState(() {
        _pickedFile = f;
        _pickedIsVideo = true;
      });
    }
  }

  Future<void> _publish() async {
    final file = _pickedFile;
    if (file == null) {
      setState(() => _error = 'برای انتشار، ابتدا یک تصویر یا ویدیو انتخاب کنید.');
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final post = await ApiScope.of(context).createPost(
        filePath: file.path,
        caption: _draftCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _posts.insert(0, post);
        _draftCtrl.clear();
        _pickedFile = null;
        _pickedIsVideo = false;
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

  Future<void> _like(Post post) async {
    // به‌روزرسانیِ خوش‌بینانه، سپس هم‌سان‌سازی با شمارِ سرور.
    final prevLiked = post.likedByMe;
    final prevCount = post.reactionCounts['like'] ?? 0;
    setState(() => _replace(post.copyWithLike(
          liked: !prevLiked,
          likeCount: prevCount + (prevLiked ? -1 : 1),
        )));
    try {
      final count = await ApiScope.of(context).likePost(post.id);
      if (!mounted) return;
      setState(() => _replace(post.copyWithLike(liked: !prevLiked, likeCount: count)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replace(post.copyWithLike(liked: prevLiked, likeCount: prevCount));
        _error = 'ثبتِ واکنش ممکن نشد. ابتدا وارد شوید.';
      });
    }
  }

  void _replace(Post p) {
    final i = _posts.indexWhere((e) => e.id == p.id);
    if (i >= 0) _posts[i] = p;
  }

  Future<void> _sendComment(Post post) async {
    final ctrl = _commentCtrls[post.id];
    final text = ctrl?.text.trim() ?? '';
    if (text.isEmpty) return;
    try {
      await ApiScope.of(context).commentOnPost(post.id, text);
      if (!mounted) return;
      setState(() {
        _replace(post.copyWithCommentCount(post.commentCount + 1));
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
    final file = _pickedFile;
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
            if (file != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _pickedIsVideo
                    ? Container(
                        height: 160,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.videocam, size: 40),
                        ),
                      )
                    : Image.file(
                        File(file.path),
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _pickedFile = null),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('حذفِ رسانه'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('تصویر'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('ویدیو'),
                ),
                const Spacer(),
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
    final author = (p.authorName != null && p.authorName!.isNotEmpty)
        ? p.authorName!
        : (p.authorEarthId.length >= 8
            ? '${p.authorEarthId.substring(0, 8)}…'
            : p.authorEarthId);
    final img = p.imageUrl;
    final video = p.videoUrl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(author, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (p.content != null && p.content!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p.content!),
            ],
            if (video != null)
              _videoPlaceholder()
            else if (img != null)
              _image(img),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _like(p),
                  icon: Icon(
                    p.likedByMe ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: p.likedByMe ? Colors.red : null,
                  ),
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

  Widget _image(String url) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
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

  Widget _videoPlaceholder() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 180,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.play_circle_outline, size: 48)),
          ),
        ),
      );
}
