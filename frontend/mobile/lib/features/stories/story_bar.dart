import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';
import 'stories_screen.dart';

/// نوارِ افقیِ حلقه‌های داستان — همان چیزی که وب بالای صفحهٔ **پیام‌ها**
/// می‌گذارد (سبکِ «وضعیت»).
///
/// پیش از این، داستان‌ها در موبایل فقط از هابِ خدمات در دسترس بودند و عملاً
/// دیده نمی‌شدند؛ ارزشِ استوری به دیده‌شدنِ در مسیرِ روزمرهٔ کاربر است.
class StoryBar extends StatefulWidget {
  const StoryBar({super.key});

  @override
  State<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends State<StoryBar> {
  static const double _height = 104;

  List<StoryRing> _rings = const [];
  bool _loaded = false;
  bool _publishing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    if (!api.isAuthenticated) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final rings = await api.storiesFeed();
      if (!mounted) return;
      // حلقهٔ خودم همیشه اول است؛ بقیه به‌ترتیبِ «دیده‌نشده‌ها جلوتر».
      rings.sort((a, b) {
        if (a.isMe != b.isMe) return a.isMe ? -1 : 1;
        if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
        return b.latestAt.compareTo(a.latestAt);
      });
      setState(() {
        _rings = rings;
        _loaded = true;
      });
    } catch (_) {
      // نوار تزئینی است؛ خطای شبکه نباید فهرستِ گفتگوها را خراب کند.
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _openAuthor(StoryRing ring) async {
    final api = ApiScope.of(context);
    try {
      final stories = await api.userStories(ring.authorEarthId);
      if (!mounted || stories.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StoryViewer(stories: stories)),
      );
    } catch (_) {
      return;
    }
    if (mounted) _load();
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      imageQuality: 85,
    );
    if (img == null || !mounted) return;
    setState(() => _publishing = true);
    try {
      // مخاطبِ پیش‌فرضِ خودِ کاربر رعایت می‌شود؛ انتشارِ همیشه-عمومی از یک دکمهٔ
      // میان‌بر، نقضِ تنظیمی است که کاربر جای دیگری انتخاب کرده.
      var audience = 'public';
      try {
        audience = (await api.storySettings()).defaultAudience;
      } catch (_) {}
      await api.createStory(filePath: img.path, audience: audience);
      messenger.showSnackBar(SnackBar(content: Text(tr('داستانِ شما منتشر شد.'))));
      if (mounted) await _load();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(tr('انتشارِ داستان ممکن نشد: {0}', [e]))));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: _height);
    final mine = _rings.where((r) => r.isMe).firstOrNull;
    return SizedBox(
      height: _height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _MyRing(
            ring: mine,
            busy: _publishing,
            onAdd: _publish,
            onOpen: mine == null ? null : () => _openAuthor(mine),
          ),
          for (final ring in _rings.where((r) => !r.isMe))
            _RingAvatar(
              label: ring.name.isNotEmpty
                  ? ring.name
                  : ring.authorEarthId.substring(0, 8),
              avatarUrl: AppConfig.absoluteMedia(ring.avatarUrl),
              unseen: ring.hasUnseen,
              onTap: () => _openAuthor(ring),
            ),
        ],
      ),
    );
  }
}

/// کاشیِ «داستانِ من»: اگر داستانِ فعالی دارم با تپ باز می‌شود و دکمهٔ «+»
/// همچنان برای افزودن است؛ وگرنه کلِ کاشی دکمهٔ افزودن است.
class _MyRing extends StatelessWidget {
  const _MyRing({
    required this.ring,
    required this.busy,
    required this.onAdd,
    required this.onOpen,
  });

  final StoryRing? ring;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RingAvatar(
      label: tr('داستانِ شما'),
      avatarUrl: AppConfig.absoluteMedia(ring?.avatarUrl),
      unseen: ring?.hasUnseen ?? false,
      onTap: busy ? null : (onOpen ?? onAdd),
      badge: busy
          ? const SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : GestureDetector(
              onTap: busy ? null : onAdd,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.add, size: 14, color: scheme.onPrimary),
              ),
            ),
    );
  }
}

class _RingAvatar extends StatelessWidget {
  const _RingAvatar({
    required this.label,
    required this.avatarUrl,
    required this.unseen,
    required this.onTap,
    this.badge,
  });

  final String label;
  final String? avatarUrl;
  final bool unseen;
  final VoidCallback? onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // حلقهٔ رنگی = دیده‌نشده؛ همان قراردادِ بصریِ وب.
                      color: unseen ? scheme.primary : scheme.surfaceContainerHighest,
                    ),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: scheme.surface,
                      backgroundImage:
                          avatarUrl == null ? null : NetworkImage(avatarUrl!),
                      child: avatarUrl == null
                          ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant)
                          : null,
                    ),
                  ),
                  if (badge != null)
                    PositionedDirectional(bottom: -2, end: -2, child: badge!),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
