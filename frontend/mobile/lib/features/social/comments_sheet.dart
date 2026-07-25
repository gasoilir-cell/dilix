import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import 'profile_screen.dart';

/// شیتِ نظرها؛ برای ریل و پست یکی است چون سرور برای هر دو همان اسکیمای
/// `CommentOut` را می‌دهد. کارهای شبکه تزریق می‌شوند (مثلِ `UserListScreen`) تا
/// این ویجت به هیچ اندپوینتِ خاصی گره نخورد.
///
/// با بسته‌شدن، شمارِ **خالصِ** نظرهای افزوده‌شده را برمی‌گرداند تا صداکننده
/// بتواند شمارنده را بدونِ بارگذاریِ دوبارهٔ فید به‌روز کند.
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.load,
    required this.send,
    required this.remove,
  });

  final Future<List<SocialComment>> Function(ApiClient api) load;
  final Future<SocialComment> Function(ApiClient api, String body) send;
  final Future<void> Function(ApiClient api, String commentId) remove;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _ctrl = TextEditingController();
  List<SocialComment>? _items;
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
      final list = await widget.load(ApiScope.of(context));
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
      final c = await widget.send(api, text);
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

  Future<void> _delete(SocialComment c) async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.remove(api, c.id);
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
                child:
                    Text('نظرها', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Text('بارگذاری ناموفق بود.\n$_error',
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

  Widget _tile(SocialComment c) {
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
