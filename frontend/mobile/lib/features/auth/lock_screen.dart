import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../../core/l10n.dart';

/// صفحهٔ قفلِ زیستی — بینِ نشستِ معتبر و محتوای اپ می‌نشیند.
///
/// به‌محضِ ساخته‌شدن یک‌بار خودکار پرسشِ اثرِ انگشت را باز می‌کند (کاربر انتظار
/// دارد با باز کردنِ اپ همان لحظه بپرسد، نه اینکه دکمه‌ای را بزند)، ولی اگر
/// لغو شد در همین صفحه می‌مانَد تا دستی دوباره تلاش کند.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onLogout});

  /// خروج از حساب — تنها راهِ فرار وقتی حسگر خراب شده یا اثرِ انگشت‌ها از
  /// تنظیماتِ گوشی حذف شده‌اند.
  final Future<void> Function() onLogout;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await AppLock.instance.unlock();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
  }

  Future<void> _confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('خروج از حساب')),
        content: Text(tr(
            'قفلِ اپ برداشته می‌شود و برای ورودِ دوباره به رمزِ عبور نیاز دارید. ادامه می‌دهید؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('خروج')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fingerprint, size: 96, color: scheme.primary),
                const SizedBox(height: 24),
                Text(
                  tr('دیلیکس قفل است'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _failed
                      ? tr('هویت تأیید نشد. دوباره تلاش کنید.')
                      : tr('برای ادامه، اثرِ انگشت یا رمزِ گوشی را وارد کنید.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _failed ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _busy ? null : _tryUnlock,
                  icon: const Icon(Icons.lock_open),
                  label: Text(_busy ? tr('در حالِ بررسی…') : tr('باز کردن')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _confirmLogout,
                  child: Text(tr('خروج از حساب')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
