import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../models/models.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
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
        actions: [
          IconButton(
            tooltip: tr('کشف و جستجو'),
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ExploreScreen())),
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
