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

enum _Mode { password, otp }

class _LoginScreenState extends State<LoginScreen> {
  _Mode _mode = _Mode.password;

  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String? _challengeId; // پس از ارسالِ کد پر می‌شود
  bool _busy = false;
  String? _error;

  late final SocialAuth _social = SocialAuth();

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _destinationCtrl.dispose();
    _codeCtrl.dispose();
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

  Future<void> _requestOtp() => _run(() async {
        final id = await _api.otpRequest('sms', _destinationCtrl.text.trim());
        setState(() => _challengeId = id);
      });

  Future<void> _verifyOtp() => _run(() async {
        await _api.otpVerify(_challengeId!, _codeCtrl.text.trim());
        widget.onAuthenticated();
      });

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
                  if (_mode == _Mode.password)
                    ..._passwordFields()
                  else
                    ..._otpFields(),
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
        ButtonSegment(value: _Mode.password, label: Text('رمز عبور'), icon: Icon(Icons.lock_outline)),
        ButtonSegment(value: _Mode.otp, label: Text('کد پیامکی'), icon: Icon(Icons.sms_outlined)),
      ],
      selected: {_mode},
      onSelectionChanged: _busy
          ? null
          : (s) => setState(() {
                _mode = s.first;
                _error = null;
                _challengeId = null;
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

  List<Widget> _otpFields() {
    if (_challengeId == null) {
      return [
        TextField(
          controller: _destinationCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'شمارهٔ موبایل',
            hintText: '+98...',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _requestOtp,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('ارسال کد'),
          ),
        ),
      ];
    }
    return [
      Text(
        'کدِ ارسال‌شده به ${_destinationCtrl.text.trim()} را وارد کنید',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _codeCtrl,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        onSubmitted: (_) => _busy ? null : _verifyOtp(),
        decoration: const InputDecoration(
          labelText: 'کد تأیید',
          prefixIcon: Icon(Icons.pin_outlined),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _verifyOtp,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('تأیید و ورود'),
        ),
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _challengeId = null),
        child: const Text('تغییر شماره / ارسال دوباره'),
      ),
    ];
  }

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
