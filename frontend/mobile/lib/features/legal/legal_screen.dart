import 'package:flutter/material.dart';

/// اسنادِ حقوقی: قوانین و مقررات + حریمِ خصوصی به‌صورتِ آکاردئونی.
/// معادلِ صفحه‌هایِ وبِ `app/legal/terms` و `app/legal/privacy`.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  // بندهایِ هر سند — متن منطبق با صفحه‌هایِ وب.
  static const _terms = <String>[
    'Dilix یک بسترِ واسط است و خود ارائه‌دهنده‌ی خدماتِ مالی، بیمه‌ای یا '
        'حمل‌ونقلِ دارای مجوز نیست. خدمات از طریقِ شرکای دارای مجوز ارائه '
        'می‌شوند و مسئولیتِ صدور و اجرای آن‌ها بر عهده‌ی همان ارائه‌دهنده است.',
    'با ساختِ حساب، شما می‌پذیرید که اطلاعاتِ صحیح ارائه دهید، از سرویس برای '
        'فعالیتِ غیرقانونی استفاده نکنید و مسئولِ حفظِ محرمانگیِ '
        'اعتبارنامه‌های ورودِ خود باشید.',
  ];

  static const _privacy = <String>[
    'موقعیتِ مکانیِ شما به‌صورتِ پیش‌فرض روی نقشه نمایش داده نمی‌شود (Opt-in). '
        'در صورتِ فعال‌سازی نیز موقعیت به‌صورتِ محو شده (Location Fuzzing) و در '
        'سطحِ منطقه نمایش داده می‌شود؛ مختصاتِ دقیق هرگز فاش نمی‌شود (ADR-06).',
    'پیام‌های خصوصی با رمزنگاریِ سرتاسری (E2EE) منتقل می‌شوند و سرور به محتوای '
        'آن‌ها دسترسی ندارد. پردازشِ هوشِ مصنوعی فقط روی داده‌هایی انجام می‌شود '
        'که خارج از مرزِ E2EE هستند.',
    'داده‌های کاربرانِ ایران در ریجنِ داخلی نگه‌داری می‌شوند (Data Residency) و '
        'انتقالِ بین‌مرزی فقط در چارچوبِ قوانینِ مربوطه انجام می‌شود.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسنادِ حقوقی')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'آخرین به‌روزرسانی: ۱۴۰۵',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('قوانین و مقررات'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in _terms)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(p),
                  ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('حریمِ خصوصی'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in _privacy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(p),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
