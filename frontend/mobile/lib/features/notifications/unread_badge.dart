import 'package:flutter/material.dart';

import '../../core/notification_center.dart';

/// نشانِ شمارِ اعلانِ نخوانده روی یک آیکن.
///
/// اگر چیزی نخوانده نباشد خودِ آیکن بدونِ هیچ تغییری رندر می‌شود، تا نوارِ پایین
/// در حالتِ عادی شلوغ نشود.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationCenter.instance,
      builder: (context, _) {
        final unread = NotificationCenter.instance.unread;
        if (unread <= 0) return child;
        return Badge(label: Text(unread > 99 ? '+99' : '$unread'), child: child);
      },
    );
  }
}
