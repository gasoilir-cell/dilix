import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../social/profile_screen.dart';

/// فیدِ ریلز: پیمایشِ عمودیِ تمام‌صفحه با `PageView`.
///
/// ⚠ ریل موجودیتِ جدا از پست است؛ پیش‌تر این صفحه فید را در مدلِ `Post`
/// می‌ریخت و لایک/نظر را به `/posts/{id}/...` می‌فرستاد که برای شناسهٔ ریل
/// همیشه ۴۰۴ می‌داد و به کاربر پیامِ گمراه‌کنندهٔ «ابتدا وارد شوید» نشان می‌داد.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();
  List<Reel>? _reels;
  String? _error;
  int _current = 0;
  bool _uploading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reels == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).reelsFeed();
      if (!mounted) return;
      setState(() {
        _reels = list;
        _error = null;
        _current = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// انتشارِ ریل: انتخابِ ویدیو از گالری و آپلودِ multipart.
  Future<void> _createReel() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ApiScope.of(context);
    final picked =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final caption = await showDialog<String>(
      context: context,
      builder: (_) => const _CaptionDialog(),
    );
    if (caption == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await api.createReel(
          filePath: picked.path, caption: caption.isEmpty ? null : caption);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('ریل منتشر شد.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('انتشارِ ریل ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(Reel reel) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ApiScope.of(context);
    if (!await _confirmDeleteReel(context)) return;
    try {
      await api.deleteReel(reel.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('حذف ناموفق بود: $e')));
    }
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
        actions: [
          IconButton(
            tooltip: 'انتشارِ ریل',
            icon: _uploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_box_outlined),
            onPressed: _uploading ? null : _createReel,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Message(
          text: 'بارگذاری ریلز ممکن نشد.\n$_error', onRetry: _load);
    }
    final reels = _reels;
    if (reels == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (reels.isEmpty) {
      return _Message(
        text: 'هنوز ریلی نیست.\nاولین ویدیوی کوتاه را منتشر کنید.',
        onRetry: _load,
      );
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: reels.length,
      onPageChanged: (i) => setState(() => _current = i),
      itemBuilder: (context, i) => _ReelPage(
        key: ValueKey(reels[i].id),
        reel: reels[i],
        active: i == _current,
        onDelete: () => _delete(reels[i]),
      ),
    );
  }
}

Future<bool> _confirmDeleteReel(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حذفِ ریل'),
      content: const Text('این ریل برای همیشه حذف می‌شود.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف')),
      ],
    ),
  );
  return ok == true;
}

/// نمایشِ تمام‌صفحهٔ فهرستی از ریل‌های **از پیش بارگذاری‌شده** (مثلاً ریل‌های یک
/// کاربر در پروفایل). برخلافِ [ReelsScreen] خودش از سرور چیزی نمی‌گیرد؛ فقط
/// حذف را روی فهرستِ محلی اعمال می‌کند و با خالی‌شدن بسته می‌شود.
class ReelPagerScreen extends StatefulWidget {
  const ReelPagerScreen({
    super.key,
    required this.reels,
    this.initialIndex = 0,
    this.title = 'ریلز',
  });

  final List<Reel> reels;
  final int initialIndex;
  final String title;

  @override
  State<ReelPagerScreen> createState() => _ReelPagerScreenState();
}

class _ReelPagerScreenState extends State<ReelPagerScreen> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late final List<Reel> _reels = List.of(widget.reels);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _delete(Reel reel) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = ApiScope.of(context);
    if (!await _confirmDeleteReel(context)) return;
    try {
      await api.deleteReel(reel.id);
      if (!mounted) return;
      setState(() {
        _reels.removeWhere((r) => r.id == reel.id);
        if (_current >= _reels.length) _current = _reels.length - 1;
      });
      if (_reels.isEmpty) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('حذف ناموفق بود: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _reels.isEmpty
          ? const _Message(text: 'ریلی نمانده است.')
          : PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _reels.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => _ReelPage(
                key: ValueKey(_reels[i].id),
                reel: _reels[i],
                active: i == _current,
                onDelete: () => _delete(_reels[i]),
              ),
            ),
    );
  }
}

/// یک صفحهٔ ریل: رسانه + لایهٔ اطلاعات و کنش‌ها. تنها صفحهٔ فعال پخش می‌شود.
class _ReelPage extends StatefulWidget {
  const _ReelPage({
    super.key,
    required this.reel,
    required this.active,
    required this.onDelete,
  });

  final Reel reel;
  final bool active;
  final VoidCallback onDelete;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _manuallyPaused = false;
  bool _viewSent = false;
  late bool _liked = widget.reel.likedByMe;
  late int _likes = widget.reel.likeCount;
  late int _comments = widget.reel.commentCount;

  @override
  void initState() {
    super.initState();
    if (widget.reel.isVideo) _initVideo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active) _sendView();
  }

  Future<void> _initVideo() async {
    final url = AppConfig.absoluteMedia(widget.reel.mediaUrl);
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

  /// بازدید یک‌بار در هر بار دیده‌شدنِ صفحه ثبت می‌شود تا با هر rebuild شمارنده
  /// بی‌خود بالا نرود.
  void _sendView() {
    if (_viewSent) return;
    _viewSent = true;
    ApiScope.of(context).viewReel(widget.reel.id);
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.active) _sendView();
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
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final wasLiked = _liked;
    final wasCount = _likes;
    setState(() {
      _liked = !wasLiked;
      _likes = wasLiked ? (wasCount > 0 ? wasCount - 1 : 0) : wasCount + 1;
    });
    try {
      final (liked, count) = await api.likeReel(widget.reel.id);
      if (mounted) {
        setState(() {
          _liked = liked;
          _likes = count;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likes = wasCount;
      });
      messenger.showSnackBar(SnackBar(content: Text('ثبتِ واکنش ناموفق بود: $e')));
    }
  }

  Future<void> _openComments() async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReelCommentsSheet(reelId: widget.reel.id),
    );
    if (added != null && added > 0 && mounted) {
      setState(() => _comments += added);
    }
  }

  void _openProfile() {
    if (widget.reel.authorEarthId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(
          earthId: widget.reel.authorEarthId,
          fallbackName: widget.reel.authorName),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          _media(),
          if (widget.reel.isVideo &&
              _ready &&
              _controller != null &&
              !_controller!.value.isPlaying)
            const Center(
              child: Icon(Icons.play_arrow, size: 72, color: Colors.white70),
            ),
          _overlay(),
        ],
      ),
    );
  }

  Widget _media() {
    final url = AppConfig.absoluteMedia(widget.reel.mediaUrl);
    // سرور برای ریل هم `image` می‌پذیرد؛ پیش‌تر این حالت پیامِ «ویدیویی ندارد»
    // می‌گرفت و رسانه اصلاً نمایش داده نمی‌شد.
    if (!widget.reel.isVideo) {
      return url == null
          ? const Center(
              child: Text('این ریل رسانه‌ای ندارد',
                  style: TextStyle(color: Colors.white70)))
          : Center(child: Image.network(url, fit: BoxFit.contain));
    }
    final c = _controller;
    if (_ready && c != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }

  Widget _overlay() {
    final avatar = AppConfig.absoluteMedia(widget.reel.authorAvatar);
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
                  InkWell(
                    onTap: _openProfile,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundImage:
                              avatar == null ? null : NetworkImage(avatar),
                          child: avatar == null
                              ? Text(widget.reel.authorTitle.characters.first,
                                  style: const TextStyle(fontSize: 12))
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.reel.authorTitle,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (widget.reel.caption != null &&
                      widget.reel.caption!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(widget.reel.caption!,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${widget.reel.viewCount} بازدید',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                _action(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  '$_likes',
                  _like,
                  color: _liked ? const Color(0xFFF43F5E) : Colors.white,
                ),
                const SizedBox(height: 16),
                _action(Icons.mode_comment_outlined, '$_comments',
                    _openComments),
                if (widget.reel.isMine) ...[
                  const SizedBox(height: 16),
                  _action(Icons.delete_outline, 'حذف', widget.onDelete),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

/// شیتِ نظرهای یک ریل؛ با pop شمارِ نظرهای **افزوده‌شده** را برمی‌گرداند تا
/// صفحهٔ ریل بدونِ بارگذاریِ دوبارهٔ فید شمارنده را به‌روز کند.
class ReelCommentsSheet extends StatefulWidget {
  const ReelCommentsSheet({super.key, required this.reelId});

  final String reelId;

  @override
  State<ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<ReelCommentsSheet> {
  final _ctrl = TextEditingController();
  List<ReelComment>? _items;
  String? _error;
  bool _sending = false;
  int _added = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && _error == null) _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ApiScope.of(context).reelComments(widget.reelId);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final c = await api.commentOnReel(widget.reelId, text);
      if (!mounted) return;
      setState(() {
        _items = [...?_items, c];
        _added += 1;
        _ctrl.clear();
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('ثبتِ نظر ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ReelComment c) async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.deleteReelComment(c.id);
      if (!mounted) return;
      setState(() {
        _items = _items?.where((x) => x.id != c.id).toList();
        _added -= 1;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('حذف ناموفق بود: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_added);
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('نظرها',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Expanded(
                child: _error != null
                    ? Center(child: Text('بارگذاری ناموفق بود.\n$_error',
                        textAlign: TextAlign.center))
                    : items == null
                        ? const Center(child: CircularProgressIndicator())
                        : items.isEmpty
                            ? const Center(child: Text('هنوز نظری نیست.'))
                            : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (_, i) => _tile(items[i]),
                              ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(
                          hintText: 'نظر خود را بنویسید…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(ReelComment c) {
    final avatar = AppConfig.absoluteMedia(c.authorAvatar);
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: avatar == null ? null : NetworkImage(avatar),
        child: avatar == null ? Text(c.authorTitle.characters.first) : null,
      ),
      title: Text(c.authorTitle),
      subtitle: Text(c.body),
      trailing: c.isMine
          ? IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _delete(c),
            )
          : null,
      onTap: c.authorEarthId.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ProfileScreen(
                    earthId: c.authorEarthId, fallbackName: c.authorName),
              )),
    );
  }
}

class _CaptionDialog extends StatefulWidget {
  const _CaptionDialog();

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('کپشنِ ریل'),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'اختیاری',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
              child: const Text('انتشار')),
        ],
      );
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
