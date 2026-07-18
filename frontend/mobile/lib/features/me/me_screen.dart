import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/social_auth.dart';
import '../../models/models.dart';
import '../dashboard/dashboard_screen.dart';
import '../notifications/notifications_screen.dart';
import '../support/support_screen.dart';
import '../wallet/wallet_screen.dart';

const _socialProviders = <({String id, String label})>[
  (id: 'google', label: 'Google'),
  (id: 'microsoft', label: 'Microsoft'),
  (id: 'apple', label: 'Apple'),
  (id: 'facebook', label: 'Facebook'),
];

/// حسابِ من: ورود، Earth ID، کیفِ پاداش، لینکِ دعوت، حریمِ خصوصی (سند ۷ §۴, §۶).
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _otpDestCtrl = TextEditingController();
  final _otpCodeCtrl = TextEditingController();
  final _social = SocialAuth();
  Identity? _me;
  ReferralLink? _referral;
  int? _points;
  List<NotificationItem> _notifications = const [];
  String? _error;
  bool _busy = false;
  String _otpChannel = 'sms';
  String? _otpChallengeId;

  @override
  void dispose() {
    _idCtrl.dispose();
    _passCtrl.dispose();
    _otpDestCtrl.dispose();
    _otpCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAfterAuth() async {
    final api = ApiScope.of(context);
    final me = await api.me();
    ReferralLink? referral;
    int? points;
    List<NotificationItem> notifications = const [];
    // این‌ها اختیاری‌اند؛ نبودشان نباید نمایشِ حساب را بشکند.
    try {
      referral = await api.referralLink();
    } catch (_) {}
    try {
      points = await api.rewardPoints();
    } catch (_) {}
    try {
      notifications = await api.notifications(limit: 20);
    } catch (_) {}
    setState(() {
      _me = me;
      _referral = referral;
      _points = points;
      _notifications = notifications;
    });
  }

  Future<void> _logout() async {
    await ApiScope.of(context).logout();
    setState(() {
      _me = null;
      _referral = null;
      _points = null;
      _notifications = const [];
      _idCtrl.clear();
      _passCtrl.clear();
    });
  }

  Future<void> _socialLogin(String provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      final credential = await _social.credentialFor(provider);
      await api.oauthLogin(provider, credential);
      await _loadAfterAuth();
    } on SocialAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'ورود با شبکه‌ی اجتماعی ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ApiScope.of(context).otpRequest(_otpChannel, _otpDestCtrl.text.trim());
      setState(() => _otpChallengeId = id);
    } catch (e) {
      setState(() => _error = 'ارسالِ کد ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final id = _otpChallengeId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).otpVerify(id, _otpCodeCtrl.text.trim());
      await _loadAfterAuth();
    } catch (e) {
      setState(() => _error = 'کدِ واردشده نادرست یا منقضی است.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiScope.of(context);
    try {
      await api.login(_idCtrl.text.trim(), _passCtrl.text);
      await _loadAfterAuth();
    } catch (e) {
      setState(() => _error = 'ورود ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableVisibility() async {
    try {
      await ApiScope.of(context).setVisibility(discoverable: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اکنون در سطحِ منطقه (fuzzed) دیده می‌شوید.')),
        );
      }
    } catch (e) {
      setState(() => _error = 'به‌روزرسانیِ حریمِ خصوصی ممکن نشد: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('حساب من')),
      body: !api.isAuthenticated ? _loginForm() : _account(),
    );
  }

  Widget _loginForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('ورود به Earth ID', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(controller: _idCtrl, decoration: const InputDecoration(labelText: 'ایمیل یا شماره تلفن')),
                const SizedBox(height: 8),
                TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'گذرواژه')),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _busy ? null : _login, child: const Text('ورود')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        _socialCard(),
        _otpCard(),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'حساب ندارید؟ با ورودِ اجتماعی یا کدِ یک‌بارمصرف، حساب به‌صورتِ خودکار ساخته می‌شود.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _socialCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ورود با حسابِ اجتماعی', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _socialProviders)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _socialLogin(p.id),
                    child: Text(p.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _otpCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ورود با کدِ یک‌بارمصرف', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'sms', label: Text('پیامک')),
                ButtonSegment(value: 'facebook', label: Text('Facebook')),
              ],
              selected: {_otpChannel},
              onSelectionChanged: _otpChallengeId != null
                  ? null
                  : (s) => setState(() => _otpChannel = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _otpDestCtrl,
              enabled: _otpChallengeId == null,
              decoration: InputDecoration(
                labelText: _otpChannel == 'sms'
                    ? 'شماره موبایل (با کدِ کشور)'
                    : 'شناسه‌ی Messenger (PSID)',
              ),
            ),
            const SizedBox(height: 8),
            if (_otpChallengeId == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _sendOtp,
                  child: const Text('ارسالِ کد'),
                ),
              )
            else ...[
              TextField(
                controller: _otpCodeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'کدِ دریافتی'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _verifyOtp,
                  child: const Text('تأیید و ورود'),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _otpChallengeId = null;
                          _otpCodeCtrl.clear();
                        }),
                child: const Text('تغییرِ مقصد'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _account() {
    final unread = _notifications.where((n) => !n.read).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text(_me?.displayName ?? 'کاربر'),
            subtitle: Text('Earth ID: ${_me?.earthId.substring(0, 12)}…'),
            trailing: Chip(label: Text('KYC L${_me?.kycLevel ?? 0}')),
          ),
        ),
        // نمای کلی (داشبوردِ نقش‌محور) — سلام + نقش + میان‌برهای مخصوصِ نقش.
        Card(
          child: ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('نمای کلی'),
            subtitle: const Text('داشبوردِ نقش‌محور و میان‌برها'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
            ),
          ),
        ),
        // کیفِ پاداش (سکه‌ی دیلیکس) — کارت به صفحهٔ کاملِ کیف پول می‌رود.
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('کیفِ پول'),
            subtitle: const Text('پاداش، پرداختِ امن و درآمد'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _points != null ? '$_points' : '—',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
            ),
          ),
        ),
        // اعلان‌ها — سرصفحه به صفحهٔ کاملِ اعلان‌ها می‌رود.
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('اعلان‌ها'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (unread > 0)
                      Chip(
                        label: Text('$unread جدید'),
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      ),
                    const Icon(Icons.chevron_left),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
                ),
              ),
              if (_notifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('اعلانی ندارید.'),
                  ),
                )
              else
                ..._notifications.take(5).map(
                      (n) => ListTile(
                        dense: true,
                        leading: Icon(
                          n.read ? Icons.circle_outlined : Icons.circle,
                          size: 12,
                          color: n.read
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: n.read ? null : () => _markRead(n),
                      ),
                    ),
            ],
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.link),
            title: const Text('لینکِ دعوت'),
            subtitle: Text(_referral?.url ?? 'در دسترس نیست'),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حریمِ خصوصی', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('پیش‌فرض: روی نقشه دیده نمی‌شوید (ADR-06).',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _enableVisibility,
                  child: const Text('فعال‌سازیِ دیده‌شدن (محدود)'),
                ),
              ],
            ),
          ),
        ),
        // پشتیبانی
        Card(
          child: ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('پشتیبانی'),
            subtitle: const Text('راه‌های ارتباط + سوالاتِ متداول'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('خروج از حساب'),
        ),
      ],
    );
  }

  Future<void> _markRead(NotificationItem n) async {
    try {
      await ApiScope.of(context).markNotificationRead(n.id);
      setState(() {
        _notifications = [
          for (final x in _notifications)
            if (x.id == n.id)
              NotificationItem(
                id: x.id,
                channel: x.channel,
                title: x.title,
                body: x.body,
                read: true,
                createdAt: x.createdAt,
              )
            else
              x,
        ];
      });
    } catch (_) {
      // خطای علامت‌گذاری بحرانی نیست؛ نادیده گرفته می‌شود.
    }
  }
}
