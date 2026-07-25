import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../feed/post_card.dart';
import '../messages/chat_screen.dart';
import '../reels/reels_screen.dart';
import 'user_list_screen.dart';

/// پروفایلِ عمومیِ یک کاربر: دنبال‌کردن، شمارِ دنبال‌کننده/دنبال‌شونده و شروعِ گفتگو.
///
/// تا پیش از این، کاربرانِ دیده‌شده روی کره یا در چت هیچ صفحهٔ مقصدی نداشتند و
/// هیچ‌کدام از ۸ اندپوینتِ `/api/v1/social` در اپ مصرف نمی‌شد.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.earthId, this.fallbackName});

  final String earthId;

  /// نامی که صداکننده از قبل می‌داند (مثلاً از مارکرِ کره)، تا هدر پیش از
  /// رسیدنِ پاسخِ سرور خالی نماند.
  final String? fallbackName;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  SocialProfile? _profile;
  List<Reel>? _reels;
  List<Post>? _posts;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _profile == null && _error == null) _load();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    try {
      final p = await api.socialProfile(widget.earthId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
      return;
    }
    // محتوا جدا و بعد از پروفایل می‌آید: نبودنش نباید کلِ صفحه را خطا کند.
    try {
      final reels = await api.userReels(widget.earthId);
      if (mounted) setState(() => _reels = reels);
    } catch (_) {
      if (mounted) setState(() => _reels = const []);
    }
    try {
      final posts = await api.userPosts(widget.earthId);
      if (mounted) setState(() => _posts = posts);
    } catch (_) {
      if (mounted) setState(() => _posts = const []);
    }
  }

  /// دنبال‌کردن/لغو با به‌روزرسانیِ خوش‌بینانه؛ در خطا وضعیت برمی‌گردد چون
  /// این دو اندپوینتِ جدا هستند (نه toggle) و ارسالِ دوباره وضعیت را خراب می‌کند.
  Future<void> _toggleFollow() async {
    final p = _profile;
    if (p == null || p.isMe || _busy) return;
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final wasFollowing = p.isFollowing;
    final optimistic = wasFollowing
        ? (p.followersCount > 0 ? p.followersCount - 1 : 0)
        : p.followersCount + 1;
    setState(() {
      _busy = true;
      _profile =
          p.copyWith(isFollowing: !wasFollowing, followersCount: optimistic);
    });
    try {
      final (following, count) = wasFollowing
          ? await api.unfollowUser(p.earthId)
          : await api.followUser(p.earthId);
      if (!mounted) return;
      setState(() => _profile =
          _profile?.copyWith(isFollowing: following, followersCount: count));
    } catch (e) {
      if (!mounted) return;
      setState(() => _profile = p);
      messenger.showSnackBar(SnackBar(content: Text('ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChat() async {
    final p = _profile;
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room =
          await api.createDirectRoom(widget.earthId, title: p?.name ?? widget.fallbackName);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('باز کردنِ گفتگو ناموفق بود: $e')));
    }
  }

  void _openList({required bool followersTab}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UserListScreen(
        title: followersTab ? 'دنبال‌کنندگان' : 'دنبال‌شوندگان',
        loader: (api) => followersTab
            ? api.followers(widget.earthId)
            : api.following(widget.earthId),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(p?.title ?? widget.fallbackName ?? 'پروفایل')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _header(p),
                      const SizedBox(height: 16),
                      _counters(p),
                      const SizedBox(height: 16),
                      _actions(p),
                      if (p.bio != null && p.bio!.trim().isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(p.bio!.trim(),
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 24),
                      _identityCard(p),
                      const SizedBox(height: 24),
                      _reelsSection(),
                      const SizedBox(height: 24),
                      _postsSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('پروفایل باز نشد.\n${_error ?? ''}',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('تلاشِ دوباره')),
            ],
          ),
        ),
      );

  Widget _header(SocialProfile p) {
    final avatar = AppConfig.absoluteMedia(p.avatarUrl);
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundImage: avatar == null ? null : NetworkImage(avatar),
          child: avatar == null
              ? Text(p.title.characters.first,
                  style: const TextStyle(fontSize: 30))
              : null,
        ),
        const SizedBox(height: 12),
        Text(p.title, style: Theme.of(context).textTheme.titleLarge),
        if (p.username != null && p.username!.isNotEmpty)
          Text('@${p.username}',
              style: Theme.of(context).textTheme.bodySmall),
        if (p.isFollowedBy && !p.isMe)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Chip(
              label: const Text('شما را دنبال می‌کند'),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  Widget _counters(SocialProfile p) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _counter('دنبال‌کننده', p.followersCount,
              () => _openList(followersTab: true)),
          _counter('دنبال‌شونده', p.followingCount,
              () => _openList(followersTab: false)),
        ],
      );

  Widget _counter(String label, int value, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text('$value',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );

  Widget _actions(SocialProfile p) {
    if (p.isMe) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.badge_outlined),
          title: Text('این پروفایلِ خودِ شماست'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: p.isFollowing
              ? OutlinedButton.icon(
                  onPressed: _busy ? null : _toggleFollow,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('لغوِ دنبال‌کردن'),
                )
              : FilledButton.icon(
                  onPressed: _busy ? null : _toggleFollow,
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(p.isFollowedBy ? 'دنبالِ متقابل' : 'دنبال‌کردن'),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('پیام'),
          ),
        ),
      ],
    );
  }

  /// شبکهٔ ریل‌های کاربر. سرور برای ریلِ ویدیویی thumbnail نمی‌دهد، پس فقط
  /// ریلِ تصویری پیش‌نمایشِ واقعی دارد و بقیه کاشیِ نشانه‌دار می‌گیرند.
  Widget _reelsSection() {
    final reels = _reels;
    if (reels == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (reels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ریل‌ها (${reels.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 9 / 16,
          ),
          itemCount: reels.length,
          itemBuilder: (_, i) => _reelTile(reels, i),
        ),
      ],
    );
  }

  Widget _reelTile(List<Reel> reels, int index) {
    final reel = reels[index];
    final url = reel.isVideo ? null : AppConfig.absoluteMedia(reel.mediaUrl);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReelPagerScreen(
          reels: reels,
          initialIndex: index,
          title: _profile?.title ?? 'ریل‌ها',
        ),
      )),
      child: Container(
        color: Colors.black12,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null) Image.network(url, fit: BoxFit.cover),
            if (url == null)
              const Center(
                  child: Icon(Icons.play_circle_outline,
                      size: 32, color: Colors.black45)),
            Positioned(
              right: 4,
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, size: 12, color: Colors.white),
                  const SizedBox(width: 2),
                  Text('${reel.likeCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// پست‌های کاربر؛ همان کارتِ مشترکِ فید تا رفتارِ لایک/نظر/ذخیره یکسان بماند.
  Widget _postsSection() {
    final posts = _posts;
    if (posts == null || posts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('پست‌ها (${posts.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final p in posts)
          PostCard(
            key: ValueKey(p.id),
            post: p,
            onDeleted: () =>
                setState(() => posts.removeWhere((e) => e.id == p.id)),
          ),
      ],
    );
  }

  Widget _identityCard(SocialProfile p) => Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Earth ID'),
              subtitle: Text(p.earthId),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('سطحِ احرازِ هویت'),
              subtitle: Text('سطح ${p.kycLevel}'),
            ),
          ],
        ),
      );
}
