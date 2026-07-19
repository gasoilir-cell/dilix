/// ترجمهٔ رشته‌های صفحه‌های آنبوردینگ (زبان/قوانین/تم) برای هر ۱۲ زبان.
///
/// فقط UIِ آنبوردینگ ترجمه شده است؛ اگر کلیدی برای زبانی نبود، به انگلیسی
/// (`en`) بازمی‌گردد. متنِ کاملِ حقوقی جداگانه در [legalBody] نگه‌داری می‌شود.
class OnboardingStrings {
  static const _fallback = 'en';

  static String t(String langCode, String key) {
    final table = _all[langCode] ?? _all[_fallback]!;
    return table[key] ?? _all[_fallback]![key] ?? key;
  }

  static const Map<String, Map<String, String>> _all = {
    'en': {
      'continue': 'Continue',
      'back': 'Back',
      'finish': 'Get Started',
      'agree': 'Agree & Continue',
      'selectLanguage': 'Choose your language',
      'selectLanguageSub': 'You can change this anytime in settings.',
      'welcome': 'Welcome to Dilix',
      'tagline': 'A safe, reliable way to connect businesses and customers.',
      'termsBody':
          'By continuing, you accept our Terms of Service and Privacy Policy.',
      'readTerms': 'Terms of Service',
      'readPrivacy': 'Privacy Policy',
      'chooseTheme': 'Choose appearance',
      'chooseThemeSub': 'Light, dark, or follow your device.',
      'light': 'Light',
      'dark': 'Dark',
      'system': 'System',
    },
    'fa': {
      'continue': 'ادامه',
      'back': 'بازگشت',
      'finish': 'شروع کنید',
      'agree': 'موافقت و ادامه',
      'selectLanguage': 'زبان خود را انتخاب کنید',
      'selectLanguageSub': 'می‌توانید بعداً از تنظیمات تغییر دهید.',
      'welcome': 'به دیلیکس خوش آمدید',
      'tagline': 'روشی آسان، ایمن و قابل‌اعتماد برای ارتباطِ کسب‌وکارها و مشتریان.',
      'termsBody': 'با ادامه، شرایط خدمات و سیاست حریم خصوصیِ ما را می‌پذیرید.',
      'readTerms': 'شرایط خدمات',
      'readPrivacy': 'سیاست حریم خصوصی',
      'chooseTheme': 'انتخاب ظاهرِ برنامه',
      'chooseThemeSub': 'روشن، تیره یا هماهنگ با دستگاه.',
      'light': 'روشن',
      'dark': 'تیره',
      'system': 'سیستم',
    },
    'ar': {
      'continue': 'متابعة',
      'back': 'رجوع',
      'finish': 'ابدأ الآن',
      'agree': 'أوافق ومتابعة',
      'selectLanguage': 'اختر لغتك',
      'selectLanguageSub': 'يمكنك تغييرها لاحقًا من الإعدادات.',
      'welcome': 'مرحبًا بك في ديليكس',
      'tagline': 'طريقة آمنة وموثوقة لربط الشركات والعملاء.',
      'termsBody': 'بالمتابعة، فإنك توافق على شروط الخدمة وسياسة الخصوصية.',
      'readTerms': 'شروط الخدمة',
      'readPrivacy': 'سياسة الخصوصية',
      'chooseTheme': 'اختر المظهر',
      'chooseThemeSub': 'فاتح أو داكن أو حسب جهازك.',
      'light': 'فاتح',
      'dark': 'داكن',
      'system': 'النظام',
    },
    'tr': {
      'continue': 'Devam',
      'back': 'Geri',
      'finish': 'Başla',
      'agree': 'Kabul et ve devam et',
      'selectLanguage': 'Dilinizi seçin',
      'selectLanguageSub': 'Bunu daha sonra ayarlardan değiştirebilirsiniz.',
      'welcome': 'Dilix\'e hoş geldiniz',
      'tagline': 'İşletmeleri ve müşterileri güvenle buluşturmanın kolay yolu.',
      'termsBody':
          'Devam ederek Hizmet Şartları ve Gizlilik Politikasını kabul edersiniz.',
      'readTerms': 'Hizmet Şartları',
      'readPrivacy': 'Gizlilik Politikası',
      'chooseTheme': 'Görünümü seçin',
      'chooseThemeSub': 'Açık, koyu veya cihazınıza göre.',
      'light': 'Açık',
      'dark': 'Koyu',
      'system': 'Sistem',
    },
    'ru': {
      'continue': 'Продолжить',
      'back': 'Назад',
      'finish': 'Начать',
      'agree': 'Принять и продолжить',
      'selectLanguage': 'Выберите язык',
      'selectLanguageSub': 'Вы можете изменить это позже в настройках.',
      'welcome': 'Добро пожаловать в Dilix',
      'tagline': 'Простой и надёжный способ связать бизнес и клиентов.',
      'termsBody':
          'Продолжая, вы принимаете Условия использования и Политику конфиденциальности.',
      'readTerms': 'Условия использования',
      'readPrivacy': 'Политика конфиденциальности',
      'chooseTheme': 'Выберите оформление',
      'chooseThemeSub': 'Светлое, тёмное или как на устройстве.',
      'light': 'Светлое',
      'dark': 'Тёмное',
      'system': 'Системное',
    },
    'zh': {
      'continue': '继续',
      'back': '返回',
      'finish': '开始',
      'agree': '同意并继续',
      'selectLanguage': '选择你的语言',
      'selectLanguageSub': '你可以稍后在设置中更改。',
      'welcome': '欢迎使用 Dilix',
      'tagline': '连接企业与客户的安全可靠方式。',
      'termsBody': '继续即表示你接受我们的服务条款和隐私政策。',
      'readTerms': '服务条款',
      'readPrivacy': '隐私政策',
      'chooseTheme': '选择外观',
      'chooseThemeSub': '浅色、深色或跟随设备。',
      'light': '浅色',
      'dark': '深色',
      'system': '系统',
    },
    'hi': {
      'continue': 'जारी रखें',
      'back': 'वापस',
      'finish': 'शुरू करें',
      'agree': 'सहमत हों और जारी रखें',
      'selectLanguage': 'अपनी भाषा चुनें',
      'selectLanguageSub': 'आप इसे बाद में सेटिंग्स में बदल सकते हैं।',
      'welcome': 'Dilix में आपका स्वागत है',
      'tagline': 'व्यवसायों और ग्राहकों को जोड़ने का सुरक्षित, भरोसेमंद तरीका।',
      'termsBody': 'जारी रखकर, आप हमारी सेवा की शर्तें और गोपनीयता नीति स्वीकार करते हैं।',
      'readTerms': 'सेवा की शर्तें',
      'readPrivacy': 'गोपनीयता नीति',
      'chooseTheme': 'रूप चुनें',
      'chooseThemeSub': 'हल्का, गहरा या डिवाइस के अनुसार।',
      'light': 'हल्का',
      'dark': 'गहरा',
      'system': 'सिस्टम',
    },
    'es': {
      'continue': 'Continuar',
      'back': 'Atrás',
      'finish': 'Empezar',
      'agree': 'Aceptar y continuar',
      'selectLanguage': 'Elige tu idioma',
      'selectLanguageSub': 'Puedes cambiarlo más tarde en ajustes.',
      'welcome': 'Bienvenido a Dilix',
      'tagline': 'Una forma segura y fiable de conectar empresas y clientes.',
      'termsBody':
          'Al continuar, aceptas nuestros Términos del servicio y la Política de privacidad.',
      'readTerms': 'Términos del servicio',
      'readPrivacy': 'Política de privacidad',
      'chooseTheme': 'Elige la apariencia',
      'chooseThemeSub': 'Claro, oscuro o según tu dispositivo.',
      'light': 'Claro',
      'dark': 'Oscuro',
      'system': 'Sistema',
    },
    'fr': {
      'continue': 'Continuer',
      'back': 'Retour',
      'finish': 'Commencer',
      'agree': 'Accepter et continuer',
      'selectLanguage': 'Choisissez votre langue',
      'selectLanguageSub': 'Vous pourrez le modifier plus tard dans les paramètres.',
      'welcome': 'Bienvenue sur Dilix',
      'tagline': 'Un moyen simple et fiable de relier entreprises et clients.',
      'termsBody':
          'En continuant, vous acceptez nos Conditions d\'utilisation et notre Politique de confidentialité.',
      'readTerms': 'Conditions d\'utilisation',
      'readPrivacy': 'Politique de confidentialité',
      'chooseTheme': 'Choisir l\'apparence',
      'chooseThemeSub': 'Clair, sombre ou selon votre appareil.',
      'light': 'Clair',
      'dark': 'Sombre',
      'system': 'Système',
    },
    'de': {
      'continue': 'Weiter',
      'back': 'Zurück',
      'finish': 'Loslegen',
      'agree': 'Zustimmen und fortfahren',
      'selectLanguage': 'Wählen Sie Ihre Sprache',
      'selectLanguageSub': 'Sie können dies später in den Einstellungen ändern.',
      'welcome': 'Willkommen bei Dilix',
      'tagline': 'Ein sicherer, zuverlässiger Weg, Unternehmen und Kunden zu verbinden.',
      'termsBody':
          'Wenn Sie fortfahren, akzeptieren Sie unsere Nutzungsbedingungen und Datenschutzrichtlinie.',
      'readTerms': 'Nutzungsbedingungen',
      'readPrivacy': 'Datenschutzrichtlinie',
      'chooseTheme': 'Darstellung wählen',
      'chooseThemeSub': 'Hell, dunkel oder wie Ihr Gerät.',
      'light': 'Hell',
      'dark': 'Dunkel',
      'system': 'System',
    },
    'ur': {
      'continue': 'جاری رکھیں',
      'back': 'واپس',
      'finish': 'شروع کریں',
      'agree': 'اتفاق اور جاری رکھیں',
      'selectLanguage': 'اپنی زبان منتخب کریں',
      'selectLanguageSub': 'آپ اسے بعد میں ترتیبات میں تبدیل کر سکتے ہیں۔',
      'welcome': 'Dilix میں خوش آمدید',
      'tagline': 'کاروبار اور صارفین کو جوڑنے کا محفوظ اور قابلِ اعتماد طریقہ۔',
      'termsBody': 'جاری رکھ کر، آپ ہماری شرائطِ خدمت اور رازداری کی پالیسی سے اتفاق کرتے ہیں۔',
      'readTerms': 'شرائطِ خدمت',
      'readPrivacy': 'رازداری کی پالیسی',
      'chooseTheme': 'ظاہری شکل منتخب کریں',
      'chooseThemeSub': 'روشن، تاریک یا آلے کے مطابق۔',
      'light': 'روشن',
      'dark': 'تاریک',
      'system': 'سسٹم',
    },
    'ps': {
      'continue': 'دوام',
      'back': 'شاته',
      'finish': 'پیل وکړئ',
      'agree': 'منم او دوام ورکړئ',
      'selectLanguage': 'خپله ژبه وټاکئ',
      'selectLanguageSub': 'تاسو کولی شئ وروسته یې په تنظیماتو کې بدل کړئ.',
      'welcome': 'Dilix ته ښه راغلاست',
      'tagline': 'د سوداګریو او پیرودونکو د نښلولو خوندي او د باور وړ لاره.',
      'termsBody': 'په دوام سره، تاسو زموږ د خدماتو شرایط او د محرمیت پالیسي منئ.',
      'readTerms': 'د خدماتو شرایط',
      'readPrivacy': 'د محرمیت پالیسي',
      'chooseTheme': 'بڼه وټاکئ',
      'chooseThemeSub': 'روښانه، تیاره یا ستاسو د وسیلې مطابق.',
      'light': 'روښانه',
      'dark': 'تیاره',
      'system': 'سیسټم',
    },
  };

  /// متنِ کاملِ حقوقی برای نمایش در پنجرهٔ «مطالعهٔ قوانین». فارسی برای `fa`
  /// و انگلیسی برای بقیهٔ زبان‌ها (تا لینک‌ها خالی نباشند).
  static List<String> legalBody(String langCode, {required bool privacy}) {
    final fa = langCode == 'fa';
    if (privacy) {
      return fa ? _privacyFa : _privacyEn;
    }
    return fa ? _termsFa : _termsEn;
  }

  static const _termsFa = <String>[
    'دیلیکس یک بسترِ واسط است و خود ارائه‌دهنده‌ی خدماتِ مالی، بیمه‌ای یا '
        'حمل‌ونقلِ دارای مجوز نیست. خدمات از طریقِ شرکای دارای مجوز ارائه می‌شوند و '
        'مسئولیتِ صدور و اجرای آن‌ها بر عهده‌ی همان ارائه‌دهنده است.',
    'با ساختِ حساب، می‌پذیرید که اطلاعاتِ صحیح ارائه دهید، از سرویس برای '
        'فعالیتِ غیرقانونی استفاده نکنید و مسئولِ حفظِ محرمانگیِ اعتبارنامه‌های '
        'ورودِ خود باشید.',
  ];

  static const _termsEn = <String>[
    'Dilix is an intermediary platform and is not itself a licensed provider '
        'of financial, insurance or transport services. Services are offered '
        'through licensed partners who are responsible for issuing and '
        'fulfilling them.',
    'By creating an account, you agree to provide accurate information, not to '
        'use the service for any unlawful activity, and to keep your login '
        'credentials confidential.',
  ];

  static const _privacyFa = <String>[
    'موقعیتِ مکانیِ شما به‌صورتِ پیش‌فرض روی نقشه نمایش داده نمی‌شود (Opt-in). در '
        'صورتِ فعال‌سازی نیز موقعیت به‌صورتِ محو شده و در سطحِ منطقه نمایش داده '
        'می‌شود؛ مختصاتِ دقیق هرگز فاش نمی‌شود.',
    'پیام‌های خصوصی با رمزنگاریِ سرتاسری (E2EE) منتقل می‌شوند و سرور به محتوای '
        'آن‌ها دسترسی ندارد.',
    'داده‌های کاربرانِ ایران در ریجنِ داخلی نگه‌داری می‌شوند و انتقالِ بین‌مرزی '
        'فقط در چارچوبِ قوانینِ مربوطه انجام می‌شود.',
  ];

  static const _privacyEn = <String>[
    'Your location is not shown on the map by default (opt-in). Even when '
        'enabled, it is fuzzed and shown at region level; exact coordinates are '
        'never revealed.',
    'Private messages are transmitted with end-to-end encryption (E2EE) and the '
        'server has no access to their content.',
    'Data of users in Iran is stored in the local region, and cross-border '
        'transfer only happens within the applicable legal framework.',
  ];
}
