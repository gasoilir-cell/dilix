import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/preferences.dart';
import 'onboarding_strings.dart';

/// صفحهٔ ۲ آنبوردینگ: پذیرشِ قوانین و مقررات (الگوی صفحهٔ خوش‌آمدِ واتساپ).
///
/// لینک‌های «شرایط خدمات» و «سیاست حریم خصوصی» خالی نیستند؛ با لمسِ هرکدام،
/// متنِ کاملِ همان سند در یک پنجرهٔ پایین‌کشویی برای مطالعه باز می‌شود.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key, required this.onBack, required this.onAccept});

  final VoidCallback onBack;
  final VoidCallback onAccept;

  void _openLegal(BuildContext context, String lang, {required bool privacy}) {
    final paragraphs = OnboardingStrings.legalBody(lang, privacy: privacy);
    final title = OnboardingStrings.t(lang, privacy ? 'readPrivacy' : 'readTerms');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (final p in paragraphs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(p, style: const TextStyle(height: 1.6)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.of(context);
    final lang =
        prefs.locale?.languageCode ?? PreferencesController.deviceSuggestedLanguage();
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(color: scheme.onSurfaceVariant, height: 1.6);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: onBack),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    Icon(Icons.handshake_outlined, size: 72, color: scheme.primary),
                    const SizedBox(height: 24),
                    Text(
                      AppConfig.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      OnboardingStrings.t(lang, 'welcome'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      OnboardingStrings.t(lang, 'tagline'),
                      textAlign: TextAlign.center,
                      style: baseStyle,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      OnboardingStrings.t(lang, 'termsBody'),
                      textAlign: TextAlign.center,
                      style: baseStyle,
                    ),
                    const SizedBox(height: 8),
                    // لینک‌های فعال به اسنادِ حقوقی (خالی نیستند؛ متنِ کامل باز می‌شود).
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openLegal(context, lang, privacy: false),
                          icon: const Icon(Icons.gavel_outlined, size: 18),
                          label: Text(OnboardingStrings.t(lang, 'readTerms')),
                        ),
                        TextButton.icon(
                          onPressed: () => _openLegal(context, lang, privacy: true),
                          icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                          label: Text(OnboardingStrings.t(lang, 'readPrivacy')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: FilledButton(
                onPressed: onAccept,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(OnboardingStrings.t(lang, 'agree')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
