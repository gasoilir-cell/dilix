import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// امنیتِ حساب (فقط‌خواندنی) — نمای وضعیتِ حسابِ کاربر از `GET /api/v1/auth/me`.
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Column(
                        children: [
                          _row(Icons.badge_outlined, 'Earth ID',
                              me?.earthId ?? '—'),
                          const Divider(height: 1),
                          _row(Icons.email_outlined, tr('ایمیل'),
                              _valueOr(me?.email)),
                          const Divider(height: 1),
                          _row(Icons.phone_outlined, tr('تلفن'),
                              _valueOr(me?.phone)),
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
                            tr('{0} (سطح {1})', [_kycLabel(me?.kycStatus ?? 'none'), me?.kycLevel ?? 0]),
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
                ),
    );
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
