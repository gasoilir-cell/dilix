/// تنظیماتِ زمانِ بیلد. با `--dart-define=DILIX_API_BASE_URL=...` مقداردهی کنید.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'DILIX_API_BASE_URL',
    defaultValue: 'http://185.55.226.250:8000',
  );

  static const String appName = String.fromEnvironment(
    'DILIX_APP_NAME',
    defaultValue: 'Dilix',
  );

  static const String defaultLocale = String.fromEnvironment(
    'DILIX_DEFAULT_LOCALE',
    defaultValue: 'fa',
  );

  /// آدرسِ کره‌ی سه‌بعدیِ وب که در تبِ «کره» داخلِ WebView بارگذاری می‌شود.
  static const String earthWebUrl = String.fromEnvironment(
    'DILIX_EARTH_WEB_URL',
    defaultValue: 'https://dilix.ir/earth',
  );

  // ── ورودِ اجتماعی (OAuth/OIDC) ──
  static const String googleClientId =
      String.fromEnvironment('DILIX_GOOGLE_CLIENT_ID');
  static const String microsoftClientId =
      String.fromEnvironment('DILIX_MICROSOFT_CLIENT_ID');
  static const String microsoftTenant =
      String.fromEnvironment('DILIX_MICROSOFT_TENANT', defaultValue: 'common');
  static const String appleClientId =
      String.fromEnvironment('DILIX_APPLE_CLIENT_ID');
  static const String facebookAppId =
      String.fromEnvironment('DILIX_FACEBOOK_APP_ID');

  /// طرحِ بازگشتِ OAuth (باید با AndroidManifest/Info.plist هم‌خوان باشد).
  static const String oauthRedirectScheme =
      String.fromEnvironment('DILIX_OAUTH_REDIRECT_SCHEME', defaultValue: 'app.dilix');
}
