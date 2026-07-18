import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// فهرستِ اعلان‌ها با علامت‌گذاریِ خوانده‌شده (تکی/همه). معادلِ صفحهٔ وبِ
/// `app/notifications/page.tsx`.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiScope.of(context).notifications(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ اعلان‌ها ممکن نشد: $e';
        _loading = false;
      });
    }
  }

  NotificationItem _asRead(NotificationItem n) => NotificationItem(
        id: n.id,
        channel: n.channel,
        title: n.title,
        body: n.body,
        read: true,
        createdAt: n.createdAt,
      );

  Future<void> _markRead(NotificationItem n) async {
    if (n.read) return;
    try {
      await ApiScope.of(context).markNotificationRead(n.id);
      if (!mounted) return;
      setState(() {
        _items = [for (final x in _items) if (x.id == n.id) _asRead(x) else x];
      });
    } catch (_) {
      // خطای علامت‌گذاری بحرانی نیست.
    }
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    final api = ApiScope.of(context);
    await Future.wait(
      unread.map((n) => api.markNotificationRead(n.id).catchError((_) {})),
    );
    if (!mounted) return;
    setState(() {
      _items = [for (final x in _items) x.read ? x : _asRead(x)];
    });
  }

  String _formatDate(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((n) => !n.read).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('اعلان‌ها'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('خواندنِ همه ($unread)'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('اعلانی وجود ندارد.')),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final n = _items[i];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  n.read ? Icons.circle_outlined : Icons.circle,
                                  size: 14,
                                  color: n.read
                                      ? Theme.of(context).disabledColor
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(n.title),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (n.body.isNotEmpty) Text(n.body),
                                    if (_formatDate(n.createdAt).isNotEmpty)
                                      Text(
                                        _formatDate(n.createdAt),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                trailing: n.read
                                    ? null
                                    : Chip(
                                        label: const Text('جدید'),
                                        backgroundColor:
                                            Theme.of(context).colorScheme.primaryContainer,
                                      ),
                                onTap: n.read ? null : () => _markRead(n),
                              ),
                            );
                          },
                        ),
            ),
    );
  }
}
