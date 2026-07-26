import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/preferences.dart';
import '../../core/social_auth.dart';
import '../../models/models.dart';
import '../admin/admin_kyc_screen.dart';
import '../admin/admin_providers_screen.dart';
import '../admin/insurance_commissions_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../legal/legal_screen.dart';
import '../notifications/notifications_screen.dart';
import '../feed/saved_posts_screen.dart';
import '../social/people_screen.dart';
import '../social/profile_qr_sheet.dart';
import '../support/support_screen.dart';
import '../wallet/holdings_screen.dart' show formatMinor;
import '../wallet/wallet_screen.dart';
import 'kyc_screen.dart';
import 'marketing_network_screen.dart';
import 'region_screen.dart';
import 'security_screen.dart';

import '../../core/l10n.dart';
/// برچسبِ فارسیِ نقش‌های خودسرویسِ dilix-api (`SELF_SERVICE_ROLES`).
Map<String, String> get kRoleLabels =>
    kRoleLabelsSrc.map((k, v) => MapEntry(k, tr(v)));

const Map<String, String> kRoleLabelsSrc = {
  'user': 'کاربر',
  'driver': 'راننده',
  'cargo_owner': 'صاحبِ بار',
  'freight_broker': 'کارگزار / شرکتِ حمل',
  'insurance_agent': 'نمایندهٔ بیمه',
  'banker': 'بانکدار',
  'creator': 'تولیدکنندهٔ محتوا',
};

/// برچسبِ فارسیِ مخاطبِ داستان (`AUDIENCES` در dilix-api).
Map<String, String> get kAudienceLabels =>
    kAudienceLabelsSrc.map((k, v) => MapEntry(k, tr(v)));

const Map<String, String> kAudienceLabelsSrc = {
  'public': 'عمومی',
  'followers': 'دنبال‌کننده‌ها',
  'colleagues': 'همکاران',
  'family': 'خانواده',
  'friends': 'دوستان',
};

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
  bool _fxBusy = false;
  ReferralLink? _referral;
  RewardWallet? _wallet;
  List<NotificationItem> _notifications = const [];
  String? _error;
  bool _busy = false;
  bool _discoverable = false;
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
    RewardWallet? wallet;
    List<NotificationItem> notifications = const [];
    // این‌ها اختیاری‌اند؛ نبودشان نباید نمایشِ حساب را بشکند.
    try {
      referral = await api.referralLink();
    } catch (_) {}
    try {
      wallet = await api.rewardWallet();
    } catch (_) {}
    try {
      notifications = await api.notifications(limit: 20);
    } catch (_) {}
    setState(() {
      _me = me;
      _referral = referral;
      _wallet = wallet;
      _discoverable = me.privacyOnMap == false; // دیده‌شدن = عکسِ privacy_on_map
      _notifications = notifications;
    });
  }

  /// تازه‌سازیِ پروفایل پس از ویرایش/آواتار/نقش.
  Future<void> _refreshMe() async {
    try {
      final me = await ApiScope.of(context).me();
      if (mounted) {
        setState(() {
          _me = me;
          _discoverable = me.privacyOnMap == false;
        });
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
    // حلقهٔ حضور/تماس باید پیش از پاک‌شدنِ توکن بایستد، وگرنه هر ۱٫۵ث یک ۴۰۱ می‌زند.
    CallScope.of(context).stopPolling();
    await ApiScope.of(context).logout();
    setState(() {
      _me = null;
      _referral = null;
      _wallet = null;
      _discoverable = false;
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
      setState(() => _error = tr('ورود با شبکه‌ی اجتماعی ناموفق بود: {0}', [e]));
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
      setState(() => _error = tr('ارسالِ کد ناموفق بود: {0}', [e]));
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
      setState(() => _error = tr('کدِ واردشده نادرست یا منقضی است.'));
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
      setState(() => _error = tr('ورود ناموفق بود: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setDiscoverable(bool value) async {
    setState(() => _discoverable = value);
    try {
      await ApiScope.of(context).setVisibility(discoverable: value);
      _snack(value
          ? tr('اکنون در سطحِ منطقه (fuzzed) روی کره دیده می‌شوید.')
          : tr('دیگر روی کره دیده نمی‌شوید.'));
    } catch (e) {
      if (mounted) setState(() => _discoverable = !value);
      _snack(tr('به‌روزرسانیِ حریمِ خصوصی ممکن نشد: {0}', [e]));
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _snack(tr('{0} کپی شد.', [label]));
  }

  /// trigger دستیِ فیدِ نرخ (فقط مدیر). سرور حلقهٔ دوره‌ای هم دارد، پس این
  /// فقط برای وقتی است که نرخ باید همین حالا تازه شود.
  Future<void> _refreshFx() async {
    setState(() => _fxBusy = true);
    final api = ApiScope.of(context);
    try {
      final (rial, _) = await api.fxRefresh();
      if (!mounted) return;
      _snack(rial > 0
          ? tr('نرخِ تازه: هر دلار {0}', [formatMinor(rial, 'IRR', 1)])
          : tr('فید نرخِ معتبری برنگرداند؛ نرخِ قبلی دست‌نخورده ماند.'));
    } catch (e) {
      if (!mounted) return;
      _snack(tr('تازه‌سازیِ نرخ ناموفق بود: {0}', [e]));
    } finally {
      if (mounted) setState(() => _fxBusy = false);
    }
  }

  /// انتخابِ تصویر از گالری و آپلود به‌عنوانِ عکسِ پروفایل.
  Future<void> _changeAvatar() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (img == null) return;
      await ApiScope.of(context).uploadAvatar(img.path);
      await _refreshMe();
      _snack(tr('عکسِ پروفایل به‌روزرسانی شد.'));
    } catch (e) {
      _snack(tr('آپلودِ عکس ممکن نشد: {0}', [e]));
    }
  }

  /// فرمِ ویرایشِ نام/نامِ‌کاربری/بیو (اطلاعاتِ شخصی).
  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _me?.displayName ?? '');
    final userCtrl = TextEditingController(text: _me?.username ?? '');
    final bioCtrl = TextEditingController(text: _me?.bio ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('اطلاعاتِ شخصی'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: tr('نامِ نمایشی')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: userCtrl,
              decoration: InputDecoration(
                labelText: tr('نامِ کاربری'),
                helperText: tr('حروفِ کوچک، اعداد، _ و .'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bioCtrl,
              maxLines: 3,
              decoration: InputDecoration(labelText: tr('دربارهٔ من')),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr('ذخیره')),
              ),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await ApiScope.of(context).updateProfile(
        fullName: nameCtrl.text.trim(),
        username: userCtrl.text.trim().isEmpty ? null : userCtrl.text.trim(),
        bio: bioCtrl.text.trim(),
      );
      await _refreshMe();
      _snack(tr('پروفایل ذخیره شد.'));
    } catch (e) {
      _snack(tr('ذخیرهٔ پروفایل ممکن نشد: {0}', [e]));
    }
  }

  /// انتخابِ نقشِ خودسرویس و ذخیره روی پروفایل.
  Future<void> _pickRole() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('نقشِ من'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final e in kRoleLabels.entries)
              ListTile(
                title: Text(e.value),
                trailing: _me?.role == e.key ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await ApiScope.of(context).updateProfile(role: chosen);
      await _refreshMe();
      _snack(tr('نقشِ شما به «{0}» تغییر کرد.', [kRoleLabels[chosen]]));
    } catch (e) {
      _snack(tr('تغییرِ نقش ممکن نشد: {0}', [e]));
    }
  }

  /// انتخابِ مخاطبِ پیش‌فرضِ داستان (`stories/settings`).
  Future<void> _pickStoryAudience() async {
    StorySettings? current;
    try {
      current = await ApiScope.of(context).storySettings();
    } catch (_) {}
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('مخاطبِ پیش‌فرضِ داستان'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final e in kAudienceLabels.entries)
              ListTile(
                title: Text(e.value),
                trailing: current?.defaultAudience == e.key
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await ApiScope.of(context).setStorySettings(chosen);
      _snack(tr('مخاطبِ داستان روی «{0}» تنظیم شد.', [kAudienceLabels[chosen]]));
    } catch (e) {
      _snack(tr('تنظیمِ مخاطب ممکن نشد: {0}', [e]));
    }
  }

  /// دکمهٔ «جدید»: ثبتِ داستانِ تازه با انتخابِ تصویر از گالری.
  Future<void> _createStory() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        imageQuality: 85,
      );
      if (img == null) return;
      String audience = 'public';
      try {
        audience = (await ApiScope.of(context).storySettings()).defaultAudience;
      } catch (_) {}
      await ApiScope.of(context).createStory(filePath: img.path, audience: audience);
      _snack(tr('داستانِ شما منتشر شد.'));
    } catch (e) {
      _snack(tr('انتشارِ داستان ممکن نشد: {0}', [e]));
    }
  }

  /// نشانیِ کاملِ آواتار (اگر تنظیم شده)؛ dilix-api مسیرِ نسبی می‌دهد.
  String? get _avatarUrl {
    final u = _me?.avatarUrl;
    if (u == null || u.isEmpty) return null;
    if (u.startsWith('http')) return u;
    return '${AppConfig.apiBaseUrl}$u';
  }

  /// مجموعِ موجودیِ پاداش به تومان (بزرگ‌ترین واحد؛ dilix-api ریال/تومان تخت می‌دهد).
  int get _rewardToman {
    final w = _wallet;
    if (w == null) return 0;
    return w.balances
        .where((b) => !b.currency.contains(tr('امانت')))
        .fold<int>(0, (sum, b) => sum + b.amountMinor);
  }

  Future<void> _pickLanguage() async {
    final prefs = PreferencesScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('زبانِ برنامه'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final lang in PreferencesController.languages)
              ListTile(
                leading: Text(lang.flag, style: const TextStyle(fontSize: 22)),
                title: Text(lang.native),
                subtitle: Text(lang.english),
                trailing: prefs.locale?.languageCode == lang.code
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  prefs.setLocale(lang.code);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('حساب من'))),
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
                Text(tr('ورود به Earth ID'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(controller: _idCtrl, decoration: InputDecoration(labelText: tr('ایمیل یا شماره تلفن'))),
                const SizedBox(height: 8),
                TextField(controller: _passCtrl, obscureText: true, decoration: InputDecoration(labelText: tr('گذرواژه'))),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _busy ? null : _login, child: Text(tr('ورود'))),
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
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            tr('حساب ندارید؟ با ورودِ اجتماعی یا کدِ یک‌بارمصرف، حساب به‌صورتِ خودکار ساخته می‌شود.'),
            style: const TextStyle(fontSize: 12),
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
            Text(tr('ورود با حسابِ اجتماعی'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
            Text(tr('ورود با کدِ یک‌بارمصرف'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'sms', label: Text(tr('پیامک'))),
                const ButtonSegment(value: 'facebook', label: Text('Facebook')),
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
                    ? tr('شماره موبایل (با کدِ کشور)')
                    : tr('شناسه‌ی Messenger (PSID)'),
              ),
            ),
            const SizedBox(height: 8),
            if (_otpChallengeId == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _sendOtp,
                  child: Text(tr('ارسالِ کد')),
                ),
              )
            else ...[
              TextField(
                controller: _otpCodeCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('کدِ دریافتی')),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _verifyOtp,
                  child: Text(tr('تأیید و ورود')),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _otpChallengeId = null;
                          _otpCodeCtrl.clear();
                        }),
                child: Text(tr('تغییرِ مقصد')),
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
        _profileHeader(),
        const SizedBox(height: 12),
        _kycCard(),
        _marketingCard(),
        // میان‌برها: نمای کلی، کیفِ پول، اعلان‌ها.
        Card(
          child: ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: Text(tr('نمای کلی')),
            subtitle: Text(tr('داشبوردِ نقش‌محور و میان‌برها')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(tr('یافتنِ آدم‌ها')),
            subtitle: Text(tr('جستجوی کاربر و پیشنهادِ دنبال‌کردن')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PeopleScreen()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: Text(tr('ذخیره‌شده‌ها')),
            subtitle: Text(tr('پست‌هایی که نگه داشته‌اید')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SavedPostsScreen()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(tr('کیفِ پول')),
            subtitle: Text(tr('پاداش، پرداختِ امن و درآمد')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
            ),
          ),
        ),
        _notificationsCard(unread),
        _settingsCard(),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _logout,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.logout),
            label: Text(tr('خروج از حساب')),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ─────────────── Task 1: سرصفحهٔ پروفایل ───────────────
  Widget _profileHeader() {
    final theme = Theme.of(context);
    final name = _me?.displayName ?? tr('کاربر');
    final initials = name.trim().isNotEmpty ? name.trim().substring(0, 1) : tr('؟');
    final code = (_referral?.code.isNotEmpty ?? false)
        ? 'DLX-${_referral!.code}'
        : 'Earth ID: ${_me?.earthId.substring(0, 8) ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: _avatarUrl != null
                          ? NetworkImage(_avatarUrl!)
                          : null,
                      child: _avatarUrl != null
                          ? null
                          : Text(
                              initials,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                    ),
                    Positioned(
                      bottom: -4,
                      left: -4,
                      child: Material(
                        color: theme.colorScheme.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _changeAvatar,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.photo_camera,
                                size: 16, color: theme.colorScheme.onPrimary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _copy(tr('کدِ دعوت'), code),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(code,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.copy,
                                size: 14, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('کدِ QR پروفایل'),
                  onPressed: (_me?.earthId ?? '').isEmpty
                      ? null
                      : () => showProfileQr(
                            context,
                            earthId: _me!.earthId,
                            displayName: name,
                          ),
                  icon: const Icon(Icons.qr_code_2),
                ),
                IconButton(
                  tooltip: tr('ویرایشِ پروفایل'),
                  onPressed: _editProfile,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat(tr('اعتماد'), '${_me?.trustScore ?? 0}'),
                const SizedBox(width: 8),
                _stat(tr('امتیاز'), (_me?.avgRating ?? 0).toStringAsFixed(1)),
                const SizedBox(width: 8),
                _stat(tr('سفر'), '${_me?.totalTrips ?? 0}'),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: _createStory,
              child: CustomPaint(
                painter: _DashedCirclePainter(
                  color: theme.colorScheme.outline,
                ),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: theme.colorScheme.primary),
                      Text(tr('جدید'), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  // ─────────────── Task 2: سطحِ تأیید + شبکهٔ بازاریابی ───────────────
  Widget _kycCard() {
    final theme = Theme.of(context);
    final level = _me?.kycLevel ?? 0;
    final progress = (level / 3).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 8),
                Text(tr('سطحِ تأیید'), style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(tr('L{0} از ۳', [level]), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const KycScreen()),
                  );
                  await _refreshMe();
                },
                child: Text(tr('ارتقای سطحِ تأیید')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marketingCard() {
    final theme = Theme.of(context);
    final referred = _referral?.totalReferred ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_outlined),
                const SizedBox(width: 8),
                Text(tr('شبکهٔ بازاریابی'), style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricBox('$_rewardToman', tr('تومان پاداش'),
                    theme.colorScheme.primaryContainer),
                const SizedBox(width: 8),
                _metricBox('$referred', tr('دعوت‌شده'),
                    theme.colorScheme.secondaryContainer),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _copy(tr('لینکِ دعوت'), _referral?.url ?? ''),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _referral?.url ?? tr('لینکِ دعوت در دسترس نیست'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6A3DE8),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const MarketingNetworkScreen()),
                ),
                child: Text(tr('مشاهدهٔ شبکه و درآمد')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBox(String value, String label, Color bg) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _notificationsCard(int unread) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(tr('اعلان‌ها')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unread > 0)
                  Chip(
                    label: Text(tr('{0} جدید', [unread])),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(tr('اعلانی ندارید.')),
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
    );
  }

  // ─────────────── Task 3: تنظیمات ───────────────
  Widget _settingsCard() {
    final prefs = PreferencesScope.of(context);
    final isDark = prefs.themeMode == ThemeMode.dark;
    final langCode = prefs.locale?.languageCode ?? 'fa';
    final lang = PreferencesController.languages.firstWhere(
      (l) => l.code == langCode,
      orElse: () => PreferencesController.languages.first,
    );
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.public_outlined),
            title: Text(tr('نمایش روی کره زمین')),
            subtitle: Text(tr('در سطحِ منطقه و به‌صورتِ محدود (ADR-06)')),
            value: _discoverable,
            onChanged: _setDiscoverable,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(tr('نقشِ من')),
            subtitle: Text(kRoleLabels[_me?.role] ?? _me?.entityType ?? '—'),
            trailing: const Icon(Icons.chevron_left),
            onTap: _pickRole,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(tr('اطلاعاتِ شخصی')),
            trailing: const Icon(Icons.chevron_left),
            onTap: _editProfile,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr('زبانِ برنامه')),
            subtitle: Text('${lang.flag} ${lang.native}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: _pickLanguage,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.travel_explore_outlined),
            title: Text(tr('زبان و ارزِ حساب')),
            subtitle: Text(tr('ذخیره روی سرور؛ مبنای ارزِ صورت‌حساب')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RegionScreen()),
            ),
          ),
          // کنسولِ ادمین فقط برای مدیران؛ سرور هم مستقلاً ۴۰۳ می‌دهد ولی
          // ردیف را پنهان می‌کنیم تا کاربرِ عادی به بن‌بست نخورد.
          if (_me?.role == 'admin' || _me?.role == 'super_admin') ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(tr('بررسیِ احرازِ هویت')),
              subtitle: Text(tr('صفِ درخواست‌های کاربران — ویژهٔ مدیران')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AdminKycScreen()),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.domain_verification_outlined),
              title: Text(tr('احرازِ مراکزِ خدمات')),
              subtitle: Text(tr('تصمیمِ KYB روی شرکت‌ها — ویژهٔ مدیران')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const AdminProvidersScreen()),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(tr('کارمزدِ بیمه')),
              subtitle: Text(tr('جمع‌بندی و تسویهٔ مراکز — ویژهٔ مدیران')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const InsuranceCommissionsScreen()),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.currency_exchange_outlined),
              title: Text(tr('تازه‌سازیِ نرخِ ارز')),
              subtitle: Text(tr('گرفتنِ فوریِ نرخِ ریال از فیدِ زنده')),
              trailing: _fxBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onTap: _fxBusy ? null : _refreshFx,
            ),
          ],
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(tr('پوستهٔ برنامه')),
            subtitle: Text(isDark ? tr('تیره') : tr('روشن')),
            value: isDark,
            onChanged: (v) =>
                prefs.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(tr('مخاطبِ داستان')),
            trailing: const Icon(Icons.chevron_left),
            onTap: _pickStoryAudience,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(tr('امنیت')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SecurityScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: Text(tr('پشتیبانی')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SupportScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(tr('اسنادِ حقوقی')),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LegalScreen()),
            ),
          ),
        ],
      ),
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

/// دایرهٔ نقطه‌چینِ دکمهٔ «جدید» زیرِ سرصفحهٔ پروفایل.
class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    const dashCount = 24;
    const sweep = 3.141592653589793 * 2 / dashCount;
    for (var i = 0; i < dashCount; i++) {
      final start = i * sweep;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep * 0.6,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
