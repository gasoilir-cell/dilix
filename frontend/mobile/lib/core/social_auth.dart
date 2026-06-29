import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import 'config.dart';

/// خطایِ ورودِ اجتماعی (لغو توسطِ کاربر یا نبودِ پیکربندی).
class SocialAuthException implements Exception {
  SocialAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// دریافتِ توکنِ ورودِ اجتماعی به‌صورتِ بومی.
///
/// Google/Microsoft/Apple از طریقِ OIDC (AppAuth، PKCE) و `id_token` برمی‌گردانند؛
/// Facebook از طریقِ SDKِ بومی و `access_token`. توکن سپس به بک‌اند
/// (`POST /v1/auth/oauth/{provider}`) فرستاده می‌شود.
///
/// پیکربندیِ بومیِ لازم:
///  * Android: تعریفِ `appAuthRedirectScheme` در `android/app/build.gradle` و
///    اضافه‌کردنِ `<activity android:name="net.openid.appauth.RedirectUriReceiverActivity">`.
///  * iOS: ثبتِ URL scheme در `Info.plist` و افزودنِ Facebook keys.
class SocialAuth {
  SocialAuth({FlutterAppAuth? appAuth, FacebookAuth? facebook})
      : _appAuth = appAuth ?? const FlutterAppAuth(),
        _facebook = facebook ?? FacebookAuth.instance;

  final FlutterAppAuth _appAuth;
  final FacebookAuth _facebook;

  static const _redirectPath = '/oauthredirect';

  String get _redirectUrl => '${AppConfig.oauthRedirectScheme}:$_redirectPath';

  Future<String> credentialFor(String provider) {
    switch (provider) {
      case 'google':
        return _oidcIdToken(
          clientId: AppConfig.googleClientId,
          issuer: 'https://accounts.google.com',
          label: 'Google',
        );
      case 'microsoft':
        return _oidcIdToken(
          clientId: AppConfig.microsoftClientId,
          issuer: 'https://login.microsoftonline.com/${AppConfig.microsoftTenant}/v2.0',
          label: 'Microsoft',
        );
      case 'apple':
        return _oidcIdToken(
          clientId: AppConfig.appleClientId,
          issuer: 'https://appleid.apple.com',
          label: 'Apple',
        );
      case 'facebook':
        return _facebookAccessToken();
      default:
        throw SocialAuthException('ارائه‌دهنده‌ی ناشناخته: $provider');
    }
  }

  Future<String> _oidcIdToken({
    required String clientId,
    required String issuer,
    required String label,
  }) async {
    if (clientId.isEmpty) {
      throw SocialAuthException('ورود با $label پیکربندی نشده است.');
    }
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        _redirectUrl,
        issuer: issuer,
        scopes: const ['openid', 'email', 'profile'],
      ),
    );
    final idToken = result?.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw SocialAuthException('توکنِ $label دریافت نشد.');
    }
    return idToken;
  }

  Future<String> _facebookAccessToken() async {
    if (AppConfig.facebookAppId.isEmpty) {
      throw SocialAuthException('ورود با Facebook پیکربندی نشده است.');
    }
    final result = await _facebook.login(permissions: const ['public_profile', 'email']);
    final token = result.accessToken?.tokenString;
    if (result.status != LoginStatus.success || token == null) {
      throw SocialAuthException('ورود با Facebook لغو شد.');
    }
    return token;
  }
}
