import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

import '../../core/app_lock.dart';
import '../../core/l10n.dart';
/// امنیتِ حساب — نمای وضعیتِ حسابِ کاربر از `GET /api/v1/auth/me` (فقط‌خواندنی)
/// به‌اضافهٔ تنها تنظیمِ نوشتنیِ این صفحه: قفلِ اثرِ انگشتِ اپ.
/// شناسه‌ی Earth، ایمیل، تلفن، وضعیتِ احرازِ هویت و کدِ ملی را نشان می‌دهد.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  Identity? _me;
  bool _loading = true;
  String? _error;

  /// وضعیتِ حسگرِ دستگاه؛ تا مشخص‌شدنش سوییچ غیرفعال می‌مانَد تا کاربر روی
  /// گوشیِ بدونِ حسگر کلیدی ببیند که کار نمی‌کند.
  BiometricStatus? _bio;
  bool _lockBusy = false;

  @override
  void initState() {
    super.initState();
    AppLock.instance.status().then((s) {
      if (mounted) setState(() => _bio = s);
    });
  }

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
      final me = await ApiScope.of(context).me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ اطلاعاتِ امنیتی ممکن نشد: {0}', [e]);
        _loading = false;
      });
    }
  }

  String _kycLabel(String status) {
    switch (status) {
      case 'approved':
        return tr('تأییدشده');
      case 'pending':
        return tr('در حالِ بررسی');
      case 'rejected':
        return tr('ردشده');
      default:
        return tr('ثبت‌نشده');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(title: Text(tr('امنیت'))),
      // قفلِ اپ محلی است و به سرور کاری ندارد، پس **بیرونِ** شاخهٔ
      // بارگذاری/خطا می‌نشیند: کاربرِ آفلاین هم باید بتواند خاموشش کند.
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _lockCard(),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  _row(Icons.badge_outlined, 'Earth ID', me?.earthId ?? '—'),
                  const Divider(height: 1),
                  _row(Icons.email_outlined, tr('ایمیل'), _valueOr(me?.email)),
                  const Divider(height: 1),
                  _row(Icons.phone_outlined, tr('تلفن'), _valueOr(me?.phone)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  _row(
                    Icons.verified_user_outlined,
                    tr('وضعیتِ احرازِ هویت'),
                    tr('{0} (سطح {1})',
                        [_kycLabel(me?.kycStatus ?? 'none'), me?.kycLevel ?? 0]),
                  ),
                  const Divider(height: 1),
                  _row(
                    Icons.credit_card,
                    tr('کدِ ملی'),
                    (me?.nationalIdSet ?? false)
                        ? tr('ثبت‌شده')
                        : tr('ثبت‌نشده'),
                  ),
                  const Divider(height: 1),
                  _row(
                    Icons.public_outlined,
                    tr('نمایش روی کره'),
                    (me?.privacyOnMap ?? false) ? tr('خاموش') : tr('روشن'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                tr('برای تغییرِ رمزِ عبور یا مدیریتِ نشست‌ها، از نسخهٔ وبِ Earth ID استفاده کنید.'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// کارتِ «قفلِ اپ». پیامِ زیرِ سوییچ عمداً صریح است: این قفل جای رمزِ حساب را
  /// نمی‌گیرد و فقط بازکردنِ اپ روی همین گوشی را محافظت می‌کند.
  Widget _lockCard() {
    final bio = _bio;
    final ready = bio == BiometricStatus.ready;
    final String hint;
    switch (bio) {
      case null:
        hint = tr('در حالِ بررسیِ حسگرِ دستگاه…');
      case BiometricStatus.ready:
        hint = tr('پس از روشن‌کردن، هر بار که اپ را باز کنید اثرِ انگشت (یا رمزِ گوشی) پرسیده می‌شود. این قفل فقط روی همین دستگاه است و جای رمزِ حساب را نمی‌گیرد.');
      case BiometricStatus.notEnrolled:
        hint = tr('هیچ اثرِ انگشتی روی این گوشی ثبت نشده است. ابتدا از تنظیماتِ گوشی اثرِ انگشت یا رمزِ صفحه را تعریف کنید.');
      case BiometricStatus.unsupported:
        hint = tr('این دستگاه حسگرِ زیستی ندارد.');
    }
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(tr('قفلِ اپ با اثرِ انگشت')),
            subtitle: Text(hint, style: const TextStyle(fontSize: 12)),
            value: AppLock.instance.enabled,
            onChanged: (!ready || _lockBusy) ? null : _toggleLock,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLock(bool value) async {
    setState(() => _lockBusy = true);
    final ok = await AppLock.instance.setEnabled(value);
    if (!mounted) return;
    setState(() => _lockBusy = false);
    if (!ok) {
      // احرازِ ناموفق = تنظیم دست‌نخورده می‌مانَد؛ بدونِ این پیام کاربر فکر
      // می‌کند سوییچ خراب است.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('هویت تأیید نشد؛ تنظیم تغییری نکرد.'))),
      );
    }
  }

  String _valueOr(String? v) => (v == null || v.isEmpty) ? tr('ثبت‌نشده') : v;

  Widget _row(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
