import 'package:flutter/material.dart';

import '../messages/messages_screen.dart';

import '../../core/l10n.dart';
/// صفحهٔ پشتیبانی — parity با `app/support/page.tsx` وب:
/// راه‌های ارتباط + تماسِ مستقیم + سوالاتِ متداول (FAQ).
/// بدونِ افزودنِ dependency جدید (مثلِ url_launcher): «پشتیبانیِ آنلاین»
/// درون‌برنامه‌ای به صفحهٔ پیام‌ها می‌رود و ایمیل/تلفن به‌صورتِ متنِ
/// قابلِ انتخاب (کپی) نمایش داده می‌شوند.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // FAQِ منطبق با نسخهٔ وب. getter است نه const: `tr()` به زبانِ جاری وابسته
  // است و مقدارِ ثابت با تعویضِ زبان به‌روز نمی‌شود.
  static List<(String, String)> get _faq => [
    (
      tr('در Core فعلی کیف پول چه کاری انجام می‌دهد؟'),
      tr('در نسخهٔ فعلی، کیفِ پاداش و پرداختِ امانی فعال است. شارژِ مستقیم و برداشتِ بانکی به‌صورتِ غیرفعالِ توضیح‌دار نمایش داده می‌شود تا با وضعیتِ واقعیِ Core هم‌خوان باشد.'),
    ),
    (
      tr('چطور بار ثبت کنم؟'),
      tr('از بخشِ «خدمات» → «اسنپِ بار» → «ثبتِ بار» را انتخاب کنید. مبدأ، مقصد، عنوانِ بار و وزن را وارد کنید. بارِ شما به رانندگانِ در مسیر نمایش داده می‌شود.'),
    ),
    (
      tr('تأیید هویت (KYC) چیست و چرا مهم است؟'),
      tr('KYC (Know Your Customer) برای امنیتِ حساب و افزایشِ سقفِ تراکنش‌ها الزامی است. سطح ۱: تأییدِ شماره موبایل. سطح ۲: بارگذاریِ کارتِ ملی. سطح ۳: تأییدِ کامل با selfie.'),
    ),
    (
      tr('دستیارِ هوشمند Dilix چه کمکی می‌کند؟'),
      tr('دستیارِ هوشمند به سوالات دربارهٔ نرخ‌های حمل، بیمهٔ بار، راهنمای استفاده از پلتفرم و اطلاعاتِ مسیرها پاسخ می‌دهد.'),
    ),
    (
      tr('آیا می‌توانم با رانندگان مستقیم در تماس باشم؟'),
      tr('بله. از طریقِ بخشِ «پیام‌ها» می‌توانید با هر کاربری که Earth ID آن را دارید چت کنید. کافیست Earth ID را در کادرِ «گفتگویِ جدید» وارد کنید.'),
    ),
    (
      tr('انتقالِ امن به کاربرِ دیگر چطور است؟'),
      tr('از کیفِ پول → «انتقالِ امن» استفاده کنید و Earth ID گیرنده را وارد کنید. این جریان سفارشِ امانی می‌سازد تا پیش از تسویه، وضعیتِ پرداخت قابلِ پیگیری و برگشت باشد.'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('پشتیبانی'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // راه‌های ارتباط
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('راه‌های ارتباط'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: Text(tr('پشتیبانیِ آنلاین')),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MessagesScreen()),
                        ),
                      ),
                      const Chip(
                        avatar: Icon(Icons.email_outlined, size: 18),
                        label: Text('support@dilix.ir'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.phone_outlined, size: 18),
                        label: Text(tr('۰۲۱-۰۰۰۰۰۰۰۰')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // تماسِ مستقیم
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('تماسِ مستقیم'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(tr('خطِ پشتیبانی: ۰۲۱-۰۰۰۰۰۰۰۰')),
                  const SizedBox(height: 4),
                  SelectableText(tr('ایمیل: support@dilix.ir')),
                ],
              ),
            ),
          ),
          // سوالاتِ متداول
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(tr('سوالاتِ متداول'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final item in _faq)
                    ExpansionTile(
                      title: Text(item.$1, style: const TextStyle(fontSize: 14)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(item.$2, style: Theme.of(context).textTheme.bodySmall)],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(tr('Dilix v1.0.0 · ساخته‌شده با ❤️ در ایران')),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
