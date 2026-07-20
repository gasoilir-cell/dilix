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

  /// آدرسِ پایهٔ اپِ وب (dilix.ir) که نماهای «کره» و «پیام‌ها» از آن داخلِ
  /// WebView با تزریقِ توکنِ نشست بارگذاری می‌شوند.
  static const String webBaseUrl = String.fromEnvironment(
    'DILIX_WEB_BASE_URL',
    defaultValue: 'https://dilix.ir',
  );

  /// آدرسِ کره‌ی سه‌بعدیِ وب که در تبِ «کره» داخلِ WebView بارگذاری می‌شود.
  static const String earthWebUrl = String.fromEnvironment(
    'DILIX_EARTH_WEB_URL',
    defaultValue: 'https://dilix.ir/earth',
  );

  /// آدرسِ پیام‌رسانِ وب که در تبِ «پیام‌ها» داخلِ WebView بارگذاری می‌شود.
  static const String messagesWebUrl = String.fromEnvironment(
    'DILIX_MESSAGES_WEB_URL',
    defaultValue: 'https://dilix.ir/messages',
  );

  /// آدرسِ کره‌ی سه‌بعدیِ خودبسنده (globe.gl) که در تبِ «کره» داخلِ WebView لود
  /// می‌شود. این صفحهٔ استاتیکِ **بدونِ احراز** روی مبدأِ خودِ سایت میزبانی می‌شود
  /// (`/globe-native.html`) تا کاشیِ ماهواره‌ای از `/globe-tiles/...` **هم‌مبدأ**
  /// (بدونِ خطایِ CORSِ WebGL) بارگذاری شود؛ داده‌ی کاربران از native تزریق و
  /// لمسِ مارکر از طریقِ پُلِ `EarthChannel` به Flutter برمی‌گردد. کاشی‌ها پس از
  /// اولین لود در کشِ WebView روی دستگاه می‌مانند.
  static const String globeUrl = String.fromEnvironment(
    'DILIX_GLOBE_URL',
    defaultValue: 'https://dilix.ir/globe-native.html',
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
