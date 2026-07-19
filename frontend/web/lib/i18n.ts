// i18n سبک — fa (RTL) پیش‌فرض. برای زبان‌های بیشتر دیکشنری اضافه کنید.
export type Locale =
  | "fa"
  | "en"
  | "ar"
  | "ru"
  | "tr"
  | "zh"
  | "hi"
  | "es"
  | "fr"
  | "de"
  | "ur"
  | "ps";

export const RTL_LOCALES: ReadonlySet<Locale> = new Set(["fa", "ar", "ur", "ps"]);

export function dir(locale: Locale): "rtl" | "ltr" {
  return RTL_LOCALES.has(locale) ? "rtl" : "ltr";
}

const fa = {
  app_name: "Dilix",
  nav_home: "خانه",
  nav_earth: "کره‌ی زمین",
  nav_messages: "پیام‌ها",
  nav_services: "خدمات",
  nav_me: "من",
  assistant: "دستیار هوشمند",
  feed_empty: "هنوز پستی نیست.",
  earth_title: "کشفِ افراد و کسب‌وکار روی کره",
  earth_privacy: "فقط کاربرانِ opt-in نمایش داده می‌شوند؛ مختصاتِ دقیق هرگز فاش نمی‌شود.",
  services_title: "خدمات",
  freight: "حمل‌ونقل (اسنپِ بار)",
  insurance: "بیمه",
  telecom: "ارتباطات",
  marketplace: "بازارگاه",
  me_title: "حساب من",
  wallet: "کیفِ پاداش",
  membership: "عضویت",
  privacy_settings: "تنظیماتِ حریمِ خصوصی",
  provider_portal: "پورتالِ ارائه‌دهنده",
};

export type Dict = typeof fa;

const en: Dict = {
  app_name: "Dilix",
  nav_home: "Home",
  nav_earth: "Earth",
  nav_messages: "Messages",
  nav_services: "Services",
  nav_me: "Me",
  assistant: "Smart Assistant",
  feed_empty: "No posts yet.",
  earth_title: "Discover people & businesses on the globe",
  earth_privacy: "Only opt-in users are shown; exact coordinates are never revealed.",
  services_title: "Services",
  freight: "Freight (Snapp for cargo)",
  insurance: "Insurance",
  telecom: "Telecom",
  marketplace: "Marketplace",
  me_title: "My Account",
  wallet: "Rewards Wallet",
  membership: "Membership",
  privacy_settings: "Privacy Settings",
  provider_portal: "Provider Portal",
};

const ar: Dict = {
  app_name: "Dilix",
  nav_home: "الرئيسية",
  nav_earth: "الكرة الأرضية",
  nav_messages: "الرسائل",
  nav_services: "الخدمات",
  nav_me: "حسابي",
  assistant: "المساعد الذكي",
  feed_empty: "لا توجد منشورات بعد.",
  earth_title: "اكتشف الأشخاص والأعمال على الكرة الأرضية",
  earth_privacy: "يُعرض فقط المستخدمون المشتركون طوعًا؛ ولا يتم الكشف عن الإحداثيات الدقيقة أبدًا.",
  services_title: "الخدمات",
  freight: "الشحن (سناب للبضائع)",
  insurance: "التأمين",
  telecom: "الاتصالات",
  marketplace: "السوق",
  me_title: "حسابي",
  wallet: "محفظة المكافآت",
  membership: "العضوية",
  privacy_settings: "إعدادات الخصوصية",
  provider_portal: "بوابة مزوّد الخدمة",
};

const ru: Dict = {
  app_name: "Dilix",
  nav_home: "Главная",
  nav_earth: "Земля",
  nav_messages: "Сообщения",
  nav_services: "Услуги",
  nav_me: "Профиль",
  assistant: "Умный помощник",
  feed_empty: "Пока нет публикаций.",
  earth_title: "Находите людей и компании на карте мира",
  earth_privacy: "Показываются только пользователи, давшие согласие; точные координаты никогда не раскрываются.",
  services_title: "Услуги",
  freight: "Грузоперевозки (Snapp для грузов)",
  insurance: "Страхование",
  telecom: "Связь",
  marketplace: "Маркетплейс",
  me_title: "Мой аккаунт",
  wallet: "Кошелёк вознаграждений",
  membership: "Членство",
  privacy_settings: "Настройки конфиденциальности",
  provider_portal: "Портал поставщика",
};

const tr: Dict = {
  app_name: "Dilix",
  nav_home: "Ana Sayfa",
  nav_earth: "Dünya",
  nav_messages: "Mesajlar",
  nav_services: "Hizmetler",
  nav_me: "Hesabım",
  assistant: "Akıllı Asistan",
  feed_empty: "Henüz gönderi yok.",
  earth_title: "Dünya üzerinde insanları ve işletmeleri keşfedin",
  earth_privacy: "Yalnızca izin veren kullanıcılar gösterilir; kesin konum asla açıklanmaz.",
  services_title: "Hizmetler",
  freight: "Nakliye (Yük için Snapp)",
  insurance: "Sigorta",
  telecom: "Telekom",
  marketplace: "Pazar Yeri",
  me_title: "Hesabım",
  wallet: "Ödül Cüzdanı",
  membership: "Üyelik",
  privacy_settings: "Gizlilik Ayarları",
  provider_portal: "Sağlayıcı Portalı",
};

const zh: Dict = {
  app_name: "Dilix",
  nav_home: "首页",
  nav_earth: "地球",
  nav_messages: "消息",
  nav_services: "服务",
  nav_me: "我的",
  assistant: "智能助手",
  feed_empty: "暂无帖子。",
  earth_title: "在地球上发现人与企业",
  earth_privacy: "仅显示自愿加入的用户；绝不透露精确坐标。",
  services_title: "服务",
  freight: "货运（货物版 Snapp）",
  insurance: "保险",
  telecom: "电信",
  marketplace: "市场",
  me_title: "我的账户",
  wallet: "奖励钱包",
  membership: "会员",
  privacy_settings: "隐私设置",
  provider_portal: "服务商门户",
};

const hi: Dict = {
  app_name: "Dilix",
  nav_home: "होम",
  nav_earth: "पृथ्वी",
  nav_messages: "संदेश",
  nav_services: "सेवाएँ",
  nav_me: "मैं",
  assistant: "स्मार्ट सहायक",
  feed_empty: "अभी तक कोई पोस्ट नहीं।",
  earth_title: "दुनिया भर में लोगों और व्यवसायों को खोजें",
  earth_privacy: "केवल सहमति देने वाले उपयोगकर्ता दिखाए जाते हैं; सटीक निर्देशांक कभी प्रकट नहीं होते।",
  services_title: "सेवाएँ",
  freight: "माल ढुलाई (कार्गो के लिए Snapp)",
  insurance: "बीमा",
  telecom: "दूरसंचार",
  marketplace: "मार्केटप्लेस",
  me_title: "मेरा खाता",
  wallet: "रिवॉर्ड वॉलेट",
  membership: "सदस्यता",
  privacy_settings: "गोपनीयता सेटिंग्स",
  provider_portal: "प्रदाता पोर्टल",
};

const es: Dict = {
  app_name: "Dilix",
  nav_home: "Inicio",
  nav_earth: "Tierra",
  nav_messages: "Mensajes",
  nav_services: "Servicios",
  nav_me: "Yo",
  assistant: "Asistente inteligente",
  feed_empty: "Aún no hay publicaciones.",
  earth_title: "Descubre personas y empresas en el globo",
  earth_privacy: "Solo se muestran los usuarios que aceptan participar; las coordenadas exactas nunca se revelan.",
  services_title: "Servicios",
  freight: "Transporte (Snapp para carga)",
  insurance: "Seguro",
  telecom: "Telecomunicaciones",
  marketplace: "Mercado",
  me_title: "Mi cuenta",
  wallet: "Monedero de recompensas",
  membership: "Membresía",
  privacy_settings: "Configuración de privacidad",
  provider_portal: "Portal del proveedor",
};

const fr: Dict = {
  app_name: "Dilix",
  nav_home: "Accueil",
  nav_earth: "Terre",
  nav_messages: "Messages",
  nav_services: "Services",
  nav_me: "Moi",
  assistant: "Assistant intelligent",
  feed_empty: "Aucune publication pour le moment.",
  earth_title: "Découvrez des personnes et des entreprises sur le globe",
  earth_privacy: "Seuls les utilisateurs ayant accepté sont affichés ; les coordonnées exactes ne sont jamais révélées.",
  services_title: "Services",
  freight: "Fret (Snapp pour le cargo)",
  insurance: "Assurance",
  telecom: "Télécom",
  marketplace: "Place de marché",
  me_title: "Mon compte",
  wallet: "Portefeuille de récompenses",
  membership: "Adhésion",
  privacy_settings: "Paramètres de confidentialité",
  provider_portal: "Portail fournisseur",
};

const de: Dict = {
  app_name: "Dilix",
  nav_home: "Startseite",
  nav_earth: "Erde",
  nav_messages: "Nachrichten",
  nav_services: "Dienste",
  nav_me: "Ich",
  assistant: "Intelligenter Assistent",
  feed_empty: "Noch keine Beiträge.",
  earth_title: "Entdecke Menschen und Unternehmen auf dem Globus",
  earth_privacy: "Es werden nur zustimmende Nutzer angezeigt; genaue Koordinaten werden niemals preisgegeben.",
  services_title: "Dienste",
  freight: "Fracht (Snapp für Fracht)",
  insurance: "Versicherung",
  telecom: "Telekom",
  marketplace: "Marktplatz",
  me_title: "Mein Konto",
  wallet: "Prämien-Wallet",
  membership: "Mitgliedschaft",
  privacy_settings: "Datenschutzeinstellungen",
  provider_portal: "Anbieterportal",
};

const ur: Dict = {
  app_name: "Dilix",
  nav_home: "ہوم",
  nav_earth: "زمین",
  nav_messages: "پیغامات",
  nav_services: "خدمات",
  nav_me: "میرا",
  assistant: "سمارٹ اسسٹنٹ",
  feed_empty: "ابھی تک کوئی پوسٹ نہیں۔",
  earth_title: "دنیا بھر میں لوگوں اور کاروبار کو دریافت کریں",
  earth_privacy: "صرف رضامندی دینے والے صارفین دکھائے جاتے ہیں؛ درست نقاط کبھی ظاہر نہیں کیے جاتے۔",
  services_title: "خدمات",
  freight: "مال برداری (کارگو کے لیے Snapp)",
  insurance: "بیمہ",
  telecom: "ٹیلی کام",
  marketplace: "مارکیٹ پلیس",
  me_title: "میرا اکاؤنٹ",
  wallet: "انعامی والٹ",
  membership: "رکنیت",
  privacy_settings: "رازداری کی ترتیبات",
  provider_portal: "فراہم کنندہ پورٹل",
};

const ps: Dict = {
  app_name: "Dilix",
  nav_home: "کور",
  nav_earth: "ځمکه",
  nav_messages: "پیغامونه",
  nav_services: "خدمتونه",
  nav_me: "زه",
  assistant: "هوښیار مرستیال",
  feed_empty: "تر اوسه هیڅ پوسټ نشته.",
  earth_title: "پر ځمکه خلک او سوداګرۍ ومومئ",
  earth_privacy: "یوازې هغه کاروونکي ښودل کیږي چې رضایت ورکړی وي؛ دقیق موقعیت هیڅکله نه افشا کیږي.",
  services_title: "خدمتونه",
  freight: "بار وړل (د بار لپاره Snapp)",
  insurance: "بیمه",
  telecom: "مخابرات",
  marketplace: "بازار",
  me_title: "زما حساب",
  wallet: "د انعام والټ",
  membership: "غړیتوب",
  privacy_settings: "د محرمیت تنظیمات",
  provider_portal: "د چمتوکوونکي پورټال",
};

const dictionaries: Record<Locale, Dict> = {
  fa,
  en,
  ar,
  ru,
  tr,
  zh,
  hi,
  es,
  fr,
  de,
  ur,
  ps,
};

export function t(locale: Locale): Dict {
  return dictionaries[locale] ?? fa;
}
