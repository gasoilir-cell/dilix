import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/social_auth.dart';

/// صفحهٔ ورود — ورود با شناسه/رمز، ورودِ یک‌بارمصرف (OTP/پیامک) و
/// ورودِ اجتماعی (فقط اگر در بیلد پیکربندی شده باشد).
///
/// پس از ورودِ موفق `onAuthenticated` صدا زده می‌شود تا [RootGate] به
/// `HomeShell` سوییچ کند.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { login, register }

class _LoginScreenState extends State<LoginScreen> {
  _Mode _mode = _Mode.login;

  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // فیلدهای ثبت‌نام
  final _nameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  late final SocialAuth _social = SocialAuth();

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regPasswordCtrl.dispose();
    super.dispose();
  }

  ApiClient get _api => ApiScope.of(context);

  /// اجرای امنِ یک عملیاتِ async با مدیریتِ busy/خطا؛ در موفقیت gate را باز می‌کند.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => _error = e.toString());
    } on SocialAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'خطای غیرمنتظره: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithPassword() => _run(() async {
        await _api.login(_identifierCtrl.text.trim(), _passwordCtrl.text);
        widget.onAuthenticated();
      });

  Future<void> _register() {
    final email = _regEmailCtrl.text.trim();
    final phone = _regPhoneCtrl.text.trim();
    if (_nameCtrl.text.trim().length < 2) {
      setState(() => _error = 'نامِ نمایشی باید حداقل ۲ نویسه باشد.');
      return Future.value();
    }
    if (email.isEmpty && phone.isEmpty) {
      setState(() => _error = 'ایمیل یا شمارهٔ موبایل را وارد کنید.');
      return Future.value();
    }
    if (_regPasswordCtrl.text.length < 8) {
      setState(() => _error = 'رمز عبور باید حداقل ۸ نویسه باشد.');
      return Future.value();
    }
    return _run(() async {
      await _api.register(
        identifier: email.isEmpty ? phone : email,
        fullName: _nameCtrl.text.trim(),
        password: _regPasswordCtrl.text,
      );
      widget.onAuthenticated();
    });
  }

  Future<void> _oauth(String provider) => _run(() async {
        final credential = await _social.credentialFor(provider);
        await _api.oauthLogin(provider, credential);
        widget.onAuthenticated();
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.public, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'به دیلیکس خوش آمدید',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  _modeSwitch(scheme),
                  const SizedBox(height: 20),
                  if (_mode == _Mode.login)
                    ..._passwordFields()
                  else
                    ..._registerFields(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ..._socialButtons(scheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeSwitch(ColorScheme scheme) {
    return SegmentedButton<_Mode>(
      segments: const [
        ButtonSegment(value: _Mode.login, label: Text('ورود'), icon: Icon(Icons.lock_outline)),
        ButtonSegment(value: _Mode.register, label: Text('ثبت‌نام'), icon: Icon(Icons.person_add_alt_1)),
      ],
      selected: {_mode},
      onSelectionChanged: _busy
          ? null
          : (s) => setState(() {
                _mode = s.first;
                _error = null;
              }),
    );
  }

  List<Widget> _passwordFields() => [
        TextField(
          controller: _identifierCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'ایمیل / موبایل / شناسهٔ کاربری',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          enabled: !_busy,
          obscureText: true,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _busy ? null : _loginWithPassword(),
          decoration: const InputDecoration(
            labelText: 'رمز عبور',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _loginWithPassword,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('ورود'),
          ),
        ),
      ];

  List<Widget> _registerFields() => [
        TextField(
          controller: _nameCtrl,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'نامِ نمایشی',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmailCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'ایمیل (اختیاری)',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPhoneCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'شمارهٔ موبایل (اختیاری)',
            hintText: '+98...',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'حداقل یکی از ایمیل یا موبایل الزامی است.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPasswordCtrl,
          enabled: !_busy,
          obscureText: true,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _busy ? null : _register(),
          decoration: const InputDecoration(
            labelText: 'رمز عبور (حداقل ۸ نویسه)',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _register,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('ثبت‌نام'),
          ),
        ),
      ];

  List<Widget> _socialButtons(ColorScheme scheme) {
    final providers = <MapEntry<String, String>>[
      if (AppConfig.googleClientId.isNotEmpty) const MapEntry('google', 'ورود با Google'),
      if (AppConfig.microsoftClientId.isNotEmpty) const MapEntry('microsoft', 'ورود با Microsoft'),
      if (AppConfig.appleClientId.isNotEmpty) const MapEntry('apple', 'ورود با Apple'),
      if (AppConfig.facebookAppId.isNotEmpty) const MapEntry('facebook', 'ورود با Facebook'),
    ];
    if (providers.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('یا', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: 12),
      for (final p in providers) ...[
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _oauth(p.key),
          icon: const Icon(Icons.login),
          label: Text(p.value),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }
}
