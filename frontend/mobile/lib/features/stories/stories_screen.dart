import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import 'circles_screen.dart';
import 'highlights_screen.dart';

import '../../core/l10n.dart';
/// فیدِ داستان‌ها: هر نویسنده یک حلقه؛ با لمسِ حلقه، نمایش‌گرِ داستان‌های آن
/// نویسنده باز می‌شود و بازدیدِ هر داستان ثبت می‌گردد. هم‌سبکِ سایرِ featureها.
class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  Future<List<StoryRing>>? _rings;

  /// Earth IDِ خودم؛ برای بازکردنِ هایلایت‌های خودم لازم است. حلقهٔ `isMe` در
  /// فید فقط وقتی وجود دارد که داستانِ فعالی داشته باشم، پس روی آن حساب نمی‌کنیم.
  String? _myEarthId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rings == null) {
      _rings = ApiScope.of(context).storiesFeed();
      _loadMe();
    }
  }

  Future<void> _loadMe() async {
    try {
      final identity = await ApiScope.of(context).me();
      if (mounted) setState(() => _myEarthId = identity.earthId);
    } catch (_) {
      // ناواردشده یا خطای شبکه؛ فقط کاشی‌های شخصی نمایش داده نمی‌شوند.
    }
  }

  Future<void> _reload() async {
    setState(() => _rings = ApiScope.of(context).storiesFeed());
    await _rings;
  }

  Future<void> _openAuthor(StoryRing ring) async {
    final stories = await ApiScope.of(context).userStories(ring.authorEarthId);
    if (!mounted || stories.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => StoryViewer(stories: stories)),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('داستان‌ها')),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: tr('حلقه‌های مخاطب'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CirclesScreen()),
            ),
          ),
          if (_myEarthId != null)
            IconButton(
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              tooltip: tr('هایلایت‌های من'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      HighlightsScreen(earthId: _myEarthId!, isMe: true),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<StoryRing>>(
          future: _rings,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(tr('بارگذاری ممکن نشد.\n{0}', [snap.error]),
                        textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            final rings = snap.data ?? const <StoryRing>[];
            if (rings.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text(tr('هنوز داستانی نیست.'))),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rings.length,
              itemBuilder: (context, i) => _ringTile(rings[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _ringTile(StoryRing ring) {
    final label = ring.isMe
        ? tr('داستان‌های من')
        : tr('کاربر {0}…', [ring.authorEarthId.substring(0, 8)]);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ring.hasUnseen
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.auto_stories_outlined,
            color: ring.hasUnseen
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(tr('{0} داستان', [ring.storyCount])),
        trailing: ring.hasUnseen
            ? const Icon(Icons.circle, size: 12, color: Colors.redAccent)
            : const Icon(Icons.chevron_left),
        onTap: () => _openAuthor(ring),
      ),
    );
  }
}

/// نمایش‌گرِ داستان‌های یک نویسنده: با هر تپ به داستانِ بعدی می‌رود و بازدیدِ
/// هر داستان را ثبت می‌کند.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.stories});

  final List<Story> stories;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  final _controller = PageController();
  int _index = 0;

  /// داستان‌های حذف‌شده در همین نشست؛ صفحه‌شان دیگر رندر نمی‌شود.
  final _deleted = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markViewed(0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _markViewed(int i) {
    if (i < 0 || i >= widget.stories.length) return;
    final s = widget.stories[i];
    if (!s.viewedByMe && !s.isMine) {
      ApiScope.of(context).viewStory(s.id).catchError((_) {});
    }
  }

  /// فهرستِ بازدیدکنندگان — فقط نویسنده مجاز است، پس خطا را داخلِ شیت نشان
  /// می‌دهیم به‌جای آنکه نمایش‌گر را ببندیم.
  void _showViewers(Story s) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => FutureBuilder<List<StoryViewerEntry>>(
        future: ApiScope.of(context).storyViewers(s.id),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return SizedBox(
              height: 160,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('${snap.error}', textAlign: TextAlign.center),
                ),
              ),
            );
          }
          final viewers = snap.data ?? const <StoryViewerEntry>[];
          if (viewers.isEmpty) {
            return SizedBox(
              height: 160,
              child: Center(child: Text(tr('هنوز کسی این داستان را ندیده است.'))),
            );
          }
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: viewers.length,
              itemBuilder: (_, i) {
                final v = viewers[i];
                final avatar = AppConfig.absoluteMedia(v.avatarUrl);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  title: Text(v.name.isEmpty ? v.earthId : v.name),
                  subtitle: Text(v.earthId),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(Story s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذفِ داستان')),
        content: Text(tr('این داستان برای همیشه حذف شود؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('حذف')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiScope.of(context).deleteStory(s.id);
      if (!mounted) return;
      setState(() => _deleted.add(s.id));
      if (_deleted.length >= widget.stories.length) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addToHighlight(Story s) async {
    final ok = await showAddToHighlightSheet(
      context,
      earthId: s.authorEarthId,
      storyId: s.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? tr('به هایلایت افزوده شد.') : tr('انجام نشد.'))),
    );
  }

  void _next() {
    if (_index >= widget.stories.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapUp: (_) => _next(),
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.stories.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _markViewed(i);
            },
            itemBuilder: (context, i) => _storyPage(widget.stories[i]),
          ),
        ),
      ),
    );
  }

  Widget _storyPage(Story s) {
    if (_deleted.contains(s.id)) {
      return Center(
        child: Text(tr('این داستان حذف شد.'),
            style: const TextStyle(color: Colors.white70)),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: s.mediaType == 'image'
              ? Image.network(
                  s.mediaUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64),
                )
              : const Icon(Icons.play_circle_outline,
                  color: Colors.white70, size: 96),
        ),
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: Row(
            children: List.generate(
              widget.stories.length,
              (i) => Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: i <= _index ? Colors.white : Colors.white24,
                ),
              ),
            ),
          ),
        ),
        if (s.caption != null && s.caption!.isNotEmpty)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Text(
              s.caption!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        if (s.isMine)
          Positioned(
            top: 20,
            left: 4,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) {
                if (v == 'viewers') {
                  _showViewers(s);
                } else if (v == 'highlight') {
                  _addToHighlight(s);
                } else {
                  _delete(s);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'viewers',
                  child: Text(tr('بازدیدکنندگان ({0})', [s.viewCount])),
                ),
                PopupMenuItem(
                  value: 'highlight',
                  child: Text(tr('افزودن به هایلایت')),
                ),
                PopupMenuItem(value: 'delete', child: Text(tr('حذفِ داستان'))),
              ],
            ),
          ),
      ],
    );
  }
}
