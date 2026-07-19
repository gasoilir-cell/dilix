import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app.dart';
import '../../models/models.dart';

/// فیدِ ریلز: پیمایشِ عمودیِ تمام‌صفحه با `PageView` و پخشِ ویدیو.
/// فقط پست‌های `post_type=reel` را از endpoint فیدِ موجود می‌گیرد.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();
  late Future<List<Post>> _future;
  int _current = 0;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = ApiScope.of(context).reelsFeed();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _current = 0;
      _future = ApiScope.of(context).reelsFeed();
    });
    await _future;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('ریلز'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: FutureBuilder<List<Post>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              text: 'بارگذاری ریلز ممکن نشد.\n${snap.error}',
              onRetry: _reload,
            );
          }
          final reels = snap.data ?? const <Post>[];
          if (reels.isEmpty) {
            return _Message(
              text: 'هنوز ریلی نیست.\nاولین ویدیوی کوتاه را منتشر کنید.',
              onRetry: _reload,
            );
          }
          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: reels.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) => _ReelPage(
              post: reels[i],
              active: i == _current,
            ),
          );
        },
      ),
    );
  }
}

/// یک صفحهٔ ریل: ویدیو + لایهٔ اطلاعات و کنش‌ها. تنها صفحهٔ فعال پخش می‌شود.
class _ReelPage extends StatefulWidget {
  const _ReelPage({required this.post, required this.active});

  final Post post;
  final bool active;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _manuallyPaused = false;
  late int _likes = widget.post.reactionCounts['like'] ?? 0;
  late int _comments = widget.post.commentCount;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = widget.post.videoUrl;
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.active) c.play();
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !_ready) return;
    if (widget.active && !_manuallyPaused) {
      c.play();
    } else if (!widget.active) {
      c
        ..pause()
        ..seekTo(Duration.zero);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _manuallyPaused = true;
      } else {
        c.play();
        _manuallyPaused = false;
      }
    });
  }

  Future<void> _like() async {
    try {
      final likeCount = await ApiScope.of(context).likePost(widget.post.id);
      if (mounted) setState(() => _likes = likeCount);
    } catch (_) {
      _snack('ثبتِ واکنش ممکن نشد. ابتدا وارد شوید.');
    }
  }

  Future<void> _comment() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CommentSheet(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await ApiScope.of(context).commentOnPost(widget.post.id, text.trim());
      if (mounted) setState(() => _comments += 1);
    } catch (_) {
      _snack('ثبتِ نظر ممکن نشد. ابتدا وارد شوید.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_ready && c != null)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            )
          else if (widget.post.videoUrl == null)
            const Center(
              child: Text('این ریل ویدیویی ندارد',
                  style: TextStyle(color: Colors.white70)),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_ready && c != null && !c.value.isPlaying)
            const Center(
              child: Icon(Icons.play_arrow, size: 72, color: Colors.white70),
            ),
          _overlay(),
        ],
      ),
    );
  }

  Widget _overlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.post.authorEarthId.substring(0, 8)}…',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  if (widget.post.content != null &&
                      widget.post.content!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(widget.post.content!,
                          style: const TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                _action(Icons.thumb_up_alt_outlined, '$_likes', _like),
                const SizedBox(height: 16),
                _action(Icons.mode_comment_outlined, '$_comments', _comment),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CommentSheet extends StatefulWidget {
  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'نظر خود را بنویسید…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('ارسال'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('تلاشِ دوباره'),
              ),
            ),
        ],
      ),
    );
  }
}
