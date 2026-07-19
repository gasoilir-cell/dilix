import 'package:flutter/material.dart';

import '../../core/preferences.dart';
import 'onboarding_strings.dart';

/// صفحهٔ ۴ آنبوردینگ: انتخابِ تمِ برنامه (روشن/تیره/هماهنگ با سیستم).
/// انتخاب بلافاصله روی کلِ اپ اعمال و پایدار می‌شود.
class ThemePage extends StatelessWidget {
  const ThemePage({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.of(context);
    final lang =
        prefs.locale?.languageCode ?? PreferencesController.deviceSuggestedLanguage();
    final scheme = Theme.of(context).colorScheme;

    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.light, Icons.light_mode, OnboardingStrings.t(lang, 'light')),
      (ThemeMode.dark, Icons.dark_mode, OnboardingStrings.t(lang, 'dark')),
      (ThemeMode.system, Icons.brightness_auto, OnboardingStrings.t(lang, 'system')),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.palette_outlined, size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    OnboardingStrings.t(lang, 'chooseTheme'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    OnboardingStrings.t(lang, 'chooseThemeSub'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  for (final o in options)
                    Card(
                      color: prefs.themeMode == o.$1 ? scheme.primaryContainer : null,
                      child: ListTile(
                        leading: Icon(o.$2, color: scheme.primary),
                        title: Text(o.$3),
                        trailing: prefs.themeMode == o.$1
                            ? Icon(Icons.check_circle, color: scheme.primary)
                            : null,
                        onTap: () => prefs.setThemeMode(o.$1),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: FilledButton(
                onPressed: onFinish,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(OnboardingStrings.t(lang, 'finish')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
