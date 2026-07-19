import 'package:flutter/material.dart';

import '../../core/preferences.dart';
import '../auth/login_screen.dart';
import 'language_page.dart';
import 'terms_page.dart';
import 'theme_page.dart';

/// جریانِ ۴ مرحله‌ایِ ورودِ اولِ کاربر:
/// ۱) انتخابِ زبان → ۲) قوانین و مقررات → ۳) ثبت‌نام/ورود → ۴) انتخابِ تم.
///
/// پس از پایانِ مرحلهٔ تم، [PreferencesController.completeOnboarding] فراخوانده
/// و [onFinished] صدا زده می‌شود تا دروازهٔ ریشه به خانه سوییچ کند. مرحلهٔ ۳
/// همان [LoginScreen] است؛ ورودِ موفق به‌جای رفتن به خانه، به مرحلهٔ تم می‌رود.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i);
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    final prefs = PreferencesScope.of(context);
    await prefs.completeOnboarding();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // بازگشتِ سخت‌افزاری بین مرحله‌ها را مدیریت می‌کنیم؛ در مرحلهٔ اول اجازهٔ
      // خروج نمی‌دهیم تا کاربر ناخواسته از آنبوردینگ خارج نشود.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index > 0) _go(_index - 1);
      },
      child: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          LanguagePage(onContinue: () => _go(1)),
          TermsPage(onBack: () => _go(0), onAccept: () => _go(2)),
          LoginScreen(onAuthenticated: () => _go(3)),
          ThemePage(onFinish: _finish),
        ],
      ),
    );
  }
}
