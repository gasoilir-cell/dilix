import 'package:flutter/material.dart';

import '../../core/preferences.dart';
import 'onboarding_strings.dart';

/// صفحهٔ ۱ آنبوردینگ: انتخابِ دستیِ زبان از میانِ ۱۲ زبان.
///
/// زبانِ پیش‌فرض به‌صورتِ هوشمند بر اساسِ زبانِ دستگاه (فارسی یا انگلیسی)
/// انتخاب شده و همین‌جا پیش‌گزیده نمایش داده می‌شود؛ انتخابِ هر زبان بلافاصله
/// جهت/زبانِ کلِ اپ را عوض می‌کند.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selected =
        prefs.locale?.languageCode ?? PreferencesController.deviceSuggestedLanguage();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.language, size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    OnboardingStrings.t(selected, 'selectLanguage'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    OnboardingStrings.t(selected, 'selectLanguageSub'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: PreferencesController.languages.length,
                itemBuilder: (context, i) {
                  final lang = PreferencesController.languages[i];
                  final isSelected = lang.code == selected;
                  return Card(
                    color: isSelected ? scheme.primaryContainer : null,
                    child: ListTile(
                      leading: Text(lang.flag, style: const TextStyle(fontSize: 26)),
                      title: Text(
                        lang.native,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(lang.english),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: scheme.primary)
                          : null,
                      onTap: () => prefs.setLocale(lang.code),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: FilledButton(
                onPressed: () {
                  // زبانِ انتخاب‌شده را پایدار می‌کنیم (حتی اگر همان پیش‌فرضِ
                  // هوشمند باشد) تا در اجراهای بعدی حفظ شود.
                  prefs.setLocale(selected);
                  onContinue();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(OnboardingStrings.t(selected, 'continue')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
