import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../social/comments_sheet.dart';
import '../social/profile_screen.dart';

import '../../core/l10n.dart';
/// کارتِ یک پست؛ در فید، کشف، ذخیره‌شده‌ها و پروفایل مشترک است.
///
/// ⚠ نشانیِ رسانه از سرور **نسبی** است (`/uploads/posts/...`)؛ پیش‌تر مستقیم به
/// `Image.network` داده می‌شد و هیچ تصویری بار نمی‌شد. حالا از
/// [AppConfig.absoluteMedia] رد می‌شود.
class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, this.onDeleted});

  final Post post;

  /// پس از حذفِ موفقِ پست صدا زده می‌شود تا صداکننده آن را از فهرست بردارد.
  final VoidCallback? onDeleted;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _post = widget.post;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    if (old.post.id != widget.post.id) _post = widget.post;
  }

  Future<void> _like() async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final before = _post;
    final count = before.reactionCounts['like'] ?? 0;
    setState(() => _post = before.copyWithLike(
          liked: !before.likedByMe,
          likeCount: before.likedByMe ? (count > 0 ? count - 1 : 0) : count + 1,
        ));
    try {
      final (liked, serverCount) = await api.likePost(before.id);
      if (mounted) {
        setState(() =>
            _post = _post.copyWithLike(liked: liked, likeCount: serverCount));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _post = before);
      messenger
          .showSnackBar(SnackBar(content: Text(tr('ثبتِ واکنش ناموفق بود: {0}', [e]))));
    }
  }

  Future<void> _save() async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final before = _post;
    setState(() => _post = before.copyWithSaved(!before.savedByMe));
    try {
      final saved = await api.toggleSavePost(before.id);
      if (mounted) setState(() => _post = _post.copyWithSaved(saved));
    } catch (e) {
      if (!mounted) return;
      setState(() => _post = before);
      messenger.showSnackBar(SnackBar(content: Text(tr('ذخیره ناموفق بود: {0}', [e]))));
    }
  }

  Future<void> _comments() async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentsSheet(
        load: (api) => api.postComments(_post.id),
        send: (api, body) => api.commentOnPost(_post.id, body),
        remove: (api, cid) => api.deletePostComment(cid),
      ),
    );
    if (added != null && added != 0 && mounted) {
      setState(() => _post =
          _post.copyWithCommentCount((_post.commentCount + added).clamp(0, 1 << 30).toInt()));
    }
  }

  Future<void> _delete() async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذفِ پست')),
        content: Text(tr('این پست برای همیشه حذف می‌شود.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('انصراف'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr('حذف'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await api.deletePost(_post.id);
      widget.onDeleted?.call();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('حذف ناموفق بود: {0}', [e]))));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openProfile() {
    if (_post.authorEarthId.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(
          earthId: _post.authorEarthId, fallbackName: _post.authorName),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final video = AppConfig.absoluteMedia(p.videoUrl);
    final image = AppConfig.absoluteMedia(p.imageUrl);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _authorRow(p),
            if (p.content != null && p.content!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p.content!.trim()),
            ],
            if (video != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _PostVideo(url: video),
              )
            else if (image != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    image,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child:
                          const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            _actions(p),
          ],
        ),
      ),
    );
  }

  Widget _authorRow(Post p) {
    final avatar = AppConfig.absoluteMedia(p.authorAvatar);
    final name = (p.authorName?.trim().isNotEmpty ?? false)
        ? p.authorName!.trim()
        : p.authorEarthId;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _openProfile,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: avatar == null ? null : NetworkImage(avatar),
                  child: avatar == null && name.isNotEmpty
                      ? Text(name.characters.first)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      if (p.placeName != null && p.placeName!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 12),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(p.placeName!,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (p.isMine)
          IconButton(
            tooltip: tr('حذفِ پست'),
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
      ],
    );
  }

  Widget _actions(Post p) => Row(
        children: [
          TextButton.icon(
            onPressed: _like,
            icon: Icon(
              p.likedByMe ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: p.likedByMe ? Colors.red : null,
            ),
            label: Text('${p.reactionCounts['like'] ?? 0}'),
          ),
          TextButton.icon(
            onPressed: _comments,
            icon: const Icon(Icons.mode_comment_outlined, size: 18),
            label: Text('${p.commentCount}'),
          ),
          const Spacer(),
          IconButton(
            tooltip: p.savedByMe ? tr('حذف از ذخیره‌ها') : tr('ذخیره'),
            onPressed: _save,
            icon: Icon(
              p.savedByMe ? Icons.bookmark : Icons.bookmark_border,
              size: 20,
            ),
          ),
        ],
      );
}

/// ویدیوی پست: تا وقتی کاربر تپ نکند کنترلری ساخته نمی‌شود تا فیدِ بلند
/// چند دیکودرِ همزمان باز نکند.
class _PostVideo extends StatefulWidget {
  const _PostVideo({required this.url});

  final String url;

  @override
  State<_PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<_PostVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final existing = _controller;
    if (existing != null) {
      if (!_ready) return;
      setState(() {
        if (existing.value.isPlaying) {
          existing.pause();
        } else {
          existing.play();
        }
      });
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
      c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return GestureDetector(
      onTap: _failed ? null : _start,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _ready && c != null
            ? AspectRatio(
                aspectRatio:
                    c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                child: VideoPlayer(c),
              )
            : Container(
                height: 180,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    _failed
                        ? Icons.videocam_off_outlined
                        : Icons.play_circle_outline,
                    size: 48,
                  ),
                ),
              ),
      ),
    );
  }
}
