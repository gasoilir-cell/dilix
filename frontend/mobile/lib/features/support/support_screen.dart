import 'package:flutter/material.dart';

import '../messages/messages_screen.dart';

/// صفحهٔ پشتیبانی — parity با `app/support/page.tsx` وب:
/// راه‌های ارتباط + تماسِ مستقیم + سوالاتِ متداول (FAQ).
/// بدونِ افزودنِ dependency جدید (مثلِ url_launcher): «پشتیبانیِ آنلاین»
/// درون‌برنامه‌ای به صفحهٔ پیام‌ها می‌رود و ایمیل/تلفن به‌صورتِ متنِ
/// قابلِ انتخاب (کپی) نمایش داده می‌شوند.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  // FAQِ منطبق با نسخهٔ وب.
  static const List<(String, String)> _faq = [
    (
      'در Core فعلی کیف پول چه کاری انجام می‌دهد؟',
      'در نسخهٔ فعلی، کیفِ پاداش و پرداختِ امانی فعال است. شارژِ مستقیم و برداشتِ بانکی به‌صورتِ غیرفعالِ توضیح‌دار نمایش داده می‌شود تا با وضعیتِ واقعیِ Core هم‌خوان باشد.',
    ),
    (
      'چطور بار ثبت کنم؟',
      'از بخشِ «خدمات» → «اسنپِ بار» → «ثبتِ بار» را انتخاب کنید. مبدأ، مقصد، عنوانِ بار و وزن را وارد کنید. بارِ شما به رانندگانِ در مسیر نمایش داده می‌شود.',
    ),
    (
      'تأیید هویت (KYC) چیست و چرا مهم است؟',
      'KYC (Know Your Customer) برای امنیتِ حساب و افزایشِ سقفِ تراکنش‌ها الزامی است. سطح ۱: تأییدِ شماره موبایل. سطح ۲: بارگذاریِ کارتِ ملی. سطح ۳: تأییدِ کامل با selfie.',
    ),
    (
      'دستیارِ هوشمند Dilix چه کمکی می‌کند؟',
      'دستیارِ هوشمند به سوالات دربارهٔ نرخ‌های حمل، بیمهٔ بار، راهنمای استفاده از پلتفرم و اطلاعاتِ مسیرها پاسخ می‌دهد.',
    ),
    (
      'آیا می‌توانم با رانندگان مستقیم در تماس باشم؟',
      'بله. از طریقِ بخشِ «پیام‌ها» می‌توانید با هر کاربری که Earth ID آن را دارید چت کنید. کافیست Earth ID را در کادرِ «گفتگویِ جدید» وارد کنید.',
    ),
    (
      'انتقالِ امن به کاربرِ دیگر چطور است؟',
      'از کیفِ پول → «انتقالِ امن» استفاده کنید و Earth ID گیرنده را وارد کنید. این جریان سفارشِ امانی می‌سازد تا پیش از تسویه، وضعیتِ پرداخت قابلِ پیگیری و برگشت باشد.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پشتیبانی')),
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
                  const Text('راه‌های ارتباط', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('پشتیبانیِ آنلاین'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MessagesScreen()),
                        ),
                      ),
                      const Chip(
                        avatar: Icon(Icons.email_outlined, size: 18),
                        label: Text('support@dilix.ir'),
                      ),
                      const Chip(
                        avatar: Icon(Icons.phone_outlined, size: 18),
                        label: Text('۰۲۱-۰۰۰۰۰۰۰۰'),
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
                children: const [
                  Text('تماسِ مستقیم', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('خطِ پشتیبانی: ۰۲۱-۰۰۰۰۰۰۰۰'),
                  SizedBox(height: 4),
                  SelectableText('ایمیل: support@dilix.ir'),
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
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('سوالاتِ متداول', style: TextStyle(fontWeight: FontWeight.bold)),
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
          const Center(
            child: Text('Dilix v1.0.0 · ساخته‌شده با ❤️ در ایران'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
