import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// فیدِ داستان‌ها: هر نویسنده یک حلقه؛ با لمسِ حلقه، نمایش‌گرِ داستان‌های آن
/// نویسنده باز می‌شود و بازدیدِ هر داستان ثبت می‌گردد. هم‌سبکِ سایرِ featureها.
class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  Future<List<StoryRing>>? _rings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rings ??= ApiScope.of(context).storiesFeed();
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
      appBar: AppBar(title: const Text('داستان‌ها')),
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
                    child: Text('بارگذاری ممکن نشد.\n${snap.error}',
                        textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            final rings = snap.data ?? const <StoryRing>[];
            if (rings.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('هنوز داستانی نیست.')),
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
        ? 'داستان‌های من'
        : 'کاربر ${ring.authorEarthId.substring(0, 8)}…';
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
        subtitle: Text('${ring.storyCount} داستان'),
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
      ],
    );
  }
}
