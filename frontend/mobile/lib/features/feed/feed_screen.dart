import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../core/location_service.dart';
import '../../core/notification_center.dart';
import '../../models/models.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/unread_badge.dart';
import '../services/services_screen.dart';
import 'explore_screen.dart';
import 'post_card.dart';

import '../../core/l10n.dart';
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
  bool _attachLocation = false;
  bool _locating = false;
  LocationFix? _locationFix;
  final _placeCtrl = TextEditingController();
  static const _location = LocationService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    _placeCtrl.dispose();
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
        _error = tr('بارگذاری فید ممکن نشد.\n{0}', [e]);
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

  /// موقعیتِ فعلی را می‌گیرد تا پست به‌صورتِ «لحظه» روی کره ثبت شود؛ تپِ دوم
  /// موقعیت را برمی‌دارد (مثلِ دکمهٔ وب).
  Future<void> _toggleLocation() async {
    if (_attachLocation) {
      setState(() {
        _attachLocation = false;
        _locationFix = null;
        _placeCtrl.clear();
      });
      return;
    }
    setState(() => _locating = true);
    final fix = await _location.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix.isOk) {
        _attachLocation = true;
        _locationFix = fix;
      } else {
        _error = fix.error;
      }
    });
  }

  Future<void> _publish() async {
    final file = _pickedFile;
    if (file == null) {
      setState(() => _error = tr('برای انتشار، ابتدا یک تصویر یا ویدیو انتخاب کنید.'));
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final fix = _attachLocation ? _locationFix : null;
      final post = await ApiScope.of(context).createPost(
        filePath: file.path,
        caption: _draftCtrl.text.trim(),
        lat: fix?.lat,
        lng: fix?.lng,
        placeName: fix == null ? null : _placeCtrl.text.trim(),
      );
      if (!mounted) return;
      final wasMoment = fix != null;
      setState(() {
        _posts.insert(0, post);
        _draftCtrl.clear();
        _placeCtrl.clear();
        _pickedFile = null;
        _pickedIsVideo = false;
        _attachLocation = false;
        _locationFix = null;
        _publishing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(wasMoment
            ? tr('لحظهٔ تو روی کره ثبت شد.')
            : tr('پستِ تو منتشر شد.')),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('ارسالِ پست ناموفق بود: {0}', [e]);
        _publishing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('خانه')),
        // هابِ خدمات از نوارِ بالای صفحهٔ خانه باز می‌شود؛ در وب هم تبِ اصلی
        // نیست و از داشبورد به آن می‌رسند.
        leading: IconButton(
          tooltip: tr('خدمات'),
          icon: const Icon(Icons.grid_view_outlined),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ServicesScreen())),
        ),
        actions: [
          IconButton(
            tooltip: tr('کشف و جستجو'),
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ExploreScreen())),
          ),
          // زنگولهٔ اعلان — معادلِ هدرِ همیشه‌حاضرِ وب.
          IconButton(
            tooltip: tr('اعلان‌ها'),
            icon: const UnreadBadge(child: Icon(Icons.notifications_outlined)),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const NotificationsScreen()));
              await NotificationCenter.instance.refresh();
            },
          ),
        ],
      ),
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
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        tr('فیدِ شما خالی است.\nاز «کشف» آدم‌های تازه را دنبال کنید.'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._posts.map((p) => PostCard(
                          key: ValueKey(p.id),
                          post: p,
                          onDeleted: () =>
                              setState(() => _posts.removeWhere((e) => e.id == p.id)),
                        )),
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
              decoration: InputDecoration(
                hintText: tr('چه خبر؟'),
                border: const OutlineInputBorder(),
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
                  label: Text(tr('حذفِ رسانه')),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                avatar: _locating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _attachLocation ? Icons.place : Icons.place_outlined,
                        size: 18,
                      ),
                label: Text(_attachLocation
                    ? tr('موقعیت افزوده شد — برای حذف بزنید')
                    : tr('افزودنِ موقعیت (لحظه روی کره)')),
                onPressed: _locating ? null : _toggleLocation,
              ),
            ),
            if (_attachLocation) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _placeCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.edit_location_alt_outlined),
                  hintText: tr('نامِ مکان (اختیاری)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(tr('تصویر')),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: Text(tr('ویدیو')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _publishing ? null : _publish,
                  child: Text(_publishing ? '…' : tr('انتشار')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
