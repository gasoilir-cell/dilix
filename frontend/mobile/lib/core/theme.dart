import 'package:flutter/material.dart';

/// سیستمِ طراحیِ Dilix — Material 3، روشن‌محور، فارسی/RTL.
///
/// ## چرا از `ColorScheme.fromSeed` فاصله گرفتیم؟
/// نسخهٔ قبلی فقط `fromSeed(0xFF3B82F6)` بود. الگوریتمِ تُنالِ M3 عمداً رنگ را
/// خاکستری می‌کند تا هر seedِ دلخواهی «امن» شود؛ نتیجه‌اش برای Dilix یک آبیِ
/// مات (~`#415F91`) بود که نه هویتِ برند را می‌رساند و نه آن حسِ روشن و
/// سرزنده‌ای که این محصول می‌خواهد. حالا seed فقط ستونِ فقراتِ نقش‌های فرعی را
/// می‌سازد و نقش‌های دیده‌شده دستی روی مقادیرِ برند بازنویسی می‌شوند.
///
/// ## قاعده‌های ثابتِ این فایل
/// * **کنتراست:** هر جفتِ متن/زمینه در هر دو حالت ≥ ۴.۵:۱ و هر خط/مرز ≥ ۳:۱
///   سنجیده شده است. تغییرِ هر مقدار بدونِ سنجشِ دوباره مجاز نیست.
/// * **`letterSpacing: 0`:** پیش‌فرضِ M3 به بعضی سبک‌ها فاصلهٔ حرفیِ مثبت می‌دهد.
///   در خطِ فارسی این فاصله اتصالِ حروف را می‌شکند و متن را «تیکه‌تیکه» نشان
///   می‌دهد، پس در کلِ مقیاسِ تایپ صفر است.
/// * **`height` سخاوتمند:** حروفِ فارسی زیرنویس (ج/چ/ح/…) و اعرابِ بلند دارند؛
///   ارتفاعِ خطِ ۱.۶ برای متنِ بدنه از ۱.۴۳ـِ پیش‌فرض خواناتر است.
/// * **هدفِ لمس:** `materialTapTargetSize.padded` + کف‌های `minimumSize`
///   تضمین می‌کنند هیچ کنترلی زیرِ ۴۸dp نشود.
class DilixTheme {
  const DilixTheme._();

  /// رنگِ برند (همان آبیِ وب). فقط برای مشتق‌کردنِ نقش‌های فرعیِ M3 به کار
  /// می‌رود؛ خودش روی سفید ۳.۶۸:۱ است و برای *متن* کافی نیست، پس در
  /// `primary` از تُنِ تیره‌ترِ ۶۰۰ استفاده می‌شود.
  static const brandSeed = Color(0xFF3B82F6);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  // ── پالتِ روشن ───────────────────────────────────────────────────────────
  // زمینهٔ اصلی سفیدِ خالص نیست: یک آبیِ بسیار روشن (#F5F8FD). این تفاوتِ کمِ
  // زمینه با کارت‌های سفید، عمق را بدونِ هیچ سایه‌ای می‌سازد — همان «مینیمال
  // ولی جذاب». اگر زمینه سفیدِ خالص بود، کارت‌ها فقط با خطِ دور دیده می‌شدند و
  // صفحه تخت و اداری می‌شد.
  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2563EB), // آبیِ برند، تُنِ ۶۰۰ → ۵.۱۷:۱ روی سفید
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDBEAFE),
    onPrimaryContainer: Color(0xFF1E3A8A),
    secondary: Color(0xFF0E7490), // فیروزه‌ای؛ لهجهٔ خنکِ کنارِ آبی
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCFFAFE),
    onSecondaryContainer: Color(0xFF164E63),
    tertiary: Color(0xFF7C3AED), // بنفش؛ لهجهٔ گرم برای جشن/دستاورد/دستیار
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFEDE9FE),
    onTertiaryContainer: Color(0xFF4C1D95),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0F172A),
    onSurfaceVariant: Color(0xFF51607A),
    surfaceDim: Color(0xFFE8EDF5),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFCFF),
    surfaceContainer: Color(0xFFF4F8FD),
    surfaceContainerHigh: Color(0xFFEDF3FA),
    surfaceContainerHighest: Color(0xFFE6EEF8),
    outline: Color(0xFF8896AB), // ۳.۰۰:۱ روی سفید — کفِ مجازِ عناصرِ غیرمتنی
    outlineVariant: Color(0xFFDFE7F1),
    inverseSurface: Color(0xFF1E293B),
    onInverseSurface: Color(0xFFF1F5F9),
    inversePrimary: Color(0xFF93C5FD),
    shadow: Color(0xFF0F172A),
    scrim: Color(0xFF0F172A),
    surfaceTint: Color(0xFF2563EB),
  );

  // ── پالتِ تیره ───────────────────────────────────────────────────────────
  // سیاهِ خالص نیست: سرمه‌ایِ خیلی تیره. سیاهِ مطلق روی OLED باعثِ smearing و
  // خستگیِ چشم در تمِ شب می‌شود و مرزِ لایه‌ها هم گم می‌شود.
  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8AB4FF),
    onPrimary: Color(0xFF0A2A6B),
    primaryContainer: Color(0xFF1D4ED8),
    onPrimaryContainer: Color(0xFFDBEAFE),
    secondary: Color(0xFF67E8F9),
    onSecondary: Color(0xFF06333D),
    secondaryContainer: Color(0xFF0E7490),
    onSecondaryContainer: Color(0xFFCFFAFE),
    tertiary: Color(0xFFC4B5FD),
    onTertiary: Color(0xFF3B1E7A),
    tertiaryContainer: Color(0xFF6D28D9),
    onTertiaryContainer: Color(0xFFEDE9FE),
    error: Color(0xFFFCA5A5),
    onError: Color(0xFF5F1414),
    errorContainer: Color(0xFF991B1B),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF101720),
    onSurface: Color(0xFFE6EDF7),
    onSurfaceVariant: Color(0xFFA7B6CA),
    surfaceDim: Color(0xFF0A0F16),
    surfaceBright: Color(0xFF29343F),
    surfaceContainerLowest: Color(0xFF0A0F16),
    surfaceContainerLow: Color(0xFF121A24),
    surfaceContainer: Color(0xFF161F2A),
    surfaceContainerHigh: Color(0xFF1C2733),
    surfaceContainerHighest: Color(0xFF23303E),
    outline: Color(0xFF5A6C84), // ۳.۳۶:۱ روی surface
    outlineVariant: Color(0xFF2A3644),
    inverseSurface: Color(0xFFE6EDF7),
    onInverseSurface: Color(0xFF16202B),
    inversePrimary: Color(0xFF2563EB),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF8AB4FF),
  );

  static const _lightScaffold = Color(0xFFF5F8FD);
  static const _darkScaffold = Color(0xFF0B1119);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = isLight ? _lightScheme : _darkScheme;
    final scaffold = isLight ? _lightScaffold : _darkScaffold;
    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      textTheme: text,
      // هیچ کنترلی زیرِ ۴۸dp نمی‌رود، حتی اگر آیکنش کوچک باشد.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[DilixSemanticColors.of(brightness)],

      // ── حرکت ──────────────────────────────────────────────────────────────
      // جایگزینِ `Zoom`ِ پیش‌فرض. روی اندروید ۱۴+ حرکتِ صفحه به خودِ ژستِ
      // «بازگشت» گره می‌خورد (کاربر می‌بیند دارد کجا برمی‌گردد و می‌تواند نیمه‌راه
      // منصرف شود)؛ روی نسخه‌های قدیمی‌تر خودِ Flutter به `FadeForwards` برمی‌گردد
      // که محو + لغزشِ کوتاه است و از بزرگ‌نماییِ کلِ صفحه سبک‌تر.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),

      // ── نوارِ بالا ─────────────────────────────────────────────────────────
      // هم‌رنگِ زمینهٔ صفحه، بدونِ سایه و بدونِ tint هنگامِ اسکرول. مرزِ نوار از
      // خطِ سایه نمی‌آید بلکه از تفاوتِ کارت‌های سفیدِ زیرش. این همان چیزی است
      // که ظاهر را «مینیمال» می‌کند بدونِ اینکه ساختار گم شود.
      appBarTheme: AppBarThemeData(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      ),

      // ── کارت ──────────────────────────────────────────────────────────────
      // سفیدِ خالص روی زمینهٔ آبیِ روشن. `elevation: 0` عمدی است: عمق از تضادِ
      // سطح می‌آید نه از سایه — سایه در تمِ روشن سریع کثیف به نظر می‌رسد.
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: const EdgeInsets.symmetric(vertical: DilixSpacing.xs),
      ),

      // ── دکمه‌ها ────────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: DilixSpacing.lg),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DilixRadius.md),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          elevation: 0,
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: DilixSpacing.lg),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DilixRadius.md),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: DilixSpacing.lg),
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DilixRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: DilixSpacing.md),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DilixRadius.sm),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: text.labelLarge,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DilixRadius.md),
          ),
        ),
      ),

      // ── ورودی ─────────────────────────────────────────────────────────────
      // پُرشده با سفید (نه خاکستری): روی زمینهٔ آبیِ روشن، فیلدِ سفید خودش
      // «جای نوشتن» را اعلام می‌کند و به خطِ پررنگ نیازی نیست.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DilixSpacing.md,
          vertical: DilixSpacing.md,
        ),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        focusedBorder: _inputBorder(scheme.primary, width: 1.6),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.6),
        disabledBorder: _inputBorder(scheme.outlineVariant),
      ),

      // ── ناوبریِ پایین ──────────────────────────────────────────────────────
      // ارتفاعِ ۶۸ (نه ۸۰ـِ پیش‌فرض) تا فضایِ محتوا بیشتر بماند، ولی هنوز
      // بالایِ کفِ ۴۸dpِ هدفِ لمس. برچسب‌ها همیشه دیده می‌شوند: کاربرِ فارسی‌زبان
      // آیکنِ تنها را کندتر تشخیص می‌دهد.
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.pill),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => (states.contains(WidgetState.selected)
                  ? text.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    )
                  : text.labelMedium?.copyWith(color: scheme.onSurfaceVariant))
              ?.copyWith(height: 1.2),
        ),
      ),

      // ── دکمهٔ شناور (دستیار) ───────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.lg),
        ),
      ),

      // ── لیست/چیپ/جداکننده ─────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DilixSpacing.md,
          vertical: DilixSpacing.xxs,
        ),
        minVerticalPadding: DilixSpacing.sm,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.md),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        surfaceTintColor: Colors.transparent,
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DilixSpacing.sm,
          vertical: DilixSpacing.xs,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // ── لایه‌های شناور ────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DilixRadius.xxl),
          ),
        ),
      ),
      // شناور، تا نوارِ ناوبریِ پایین را نپوشاند و پیام روی محتوا گم نشود.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        elevation: 3,
        insetPadding: const EdgeInsets.all(DilixSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(
          horizontal: DilixSpacing.sm,
          vertical: DilixSpacing.xs,
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(DilixRadius.sm),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DilixRadius.md),
        ),
      ),

      // ── وضعیت‌ها ──────────────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant,
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.06),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(DilixRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// مقیاسِ تایپِ Dilix — ۱۱/۱۲/۱۴/۱۶/۱۸/۲۰/۲۴/۳۲.
  ///
  /// عمداً کوتاه است: هرچه پله‌های اندازه کمتر باشند، صفحه‌ها ناخودآگاه شبیهِ
  /// هم می‌مانند. `letterSpacing: 0` در همه‌جا اجباری است (توضیح در سرِ کلاس).
  static TextTheme _textTheme(ColorScheme scheme) {
    TextStyle s(double size, double height, FontWeight weight, {Color? color}) {
      return TextStyle(
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: 0,
        color: color ?? scheme.onSurface,
      );
    }

    final muted = scheme.onSurfaceVariant;
    return TextTheme(
      displayLarge: s(32, 1.25, FontWeight.w700),
      displayMedium: s(28, 1.25, FontWeight.w700),
      displaySmall: s(24, 1.3, FontWeight.w700),
      headlineLarge: s(28, 1.3, FontWeight.w700),
      headlineMedium: s(24, 1.3, FontWeight.w700),
      headlineSmall: s(20, 1.35, FontWeight.w600),
      titleLarge: s(18, 1.4, FontWeight.w600),
      titleMedium: s(16, 1.45, FontWeight.w600),
      titleSmall: s(14, 1.45, FontWeight.w600),
      bodyLarge: s(16, 1.6, FontWeight.w400),
      bodyMedium: s(14, 1.6, FontWeight.w400),
      bodySmall: s(12, 1.5, FontWeight.w400, color: muted),
      labelLarge: s(14, 1.2, FontWeight.w600),
      labelMedium: s(12, 1.25, FontWeight.w500),
      labelSmall: s(11, 1.25, FontWeight.w500, color: muted),
    );
  }
}

/// مقیاسِ فاصله‌ها (۴dp). هر padding/marginِ جدید باید یکی از این‌ها باشد؛
/// عددِ دلخواه همان چیزی است که چیدمانِ اپ را کم‌کم ناهمگون می‌کند.
abstract final class DilixSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// شعاعِ گوشه‌ها. یک‌دست‌بودنِ این مقادیر بیشتر از خودِ مقدارها اهمیت دارد.
abstract final class DilixRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double pill = 999;
}

/// زمان‌بندیِ حرکت. کمتر از ۱۵۰ms چشم تغییر را «پرش» می‌بیند و بیشتر از ۳۰۰ms
/// اپ کُند حس می‌شود؛ همهٔ انیمیشن‌های رابط باید در این بازه بمانند.
abstract final class DilixMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve emphasized = Curves.easeOutCubic;
}

/// رنگ‌های *معنایی* که در `ColorScheme` نقشی ندارند: موفقیت، هشدار، اطلاع.
///
/// چرا افزونه و نه ثابتِ سراسری؟ چون این‌ها هم باید با تمِ روشن/تیره عوض شوند.
/// پیش از این، صفحه‌ها مستقیم `Colors.green`/`Colors.amber` می‌گذاشتند که در تمِ
/// تیره کنتراستش می‌افتاد و در تمِ روشن هم با پالتِ برند نمی‌خواند.
@immutable
class DilixSemanticColors extends ThemeExtension<DilixSemanticColors> {
  const DilixSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;

  static const _light = DilixSemanticColors(
    success: Color(0xFF15803D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    warning: Color(0xFFB45309),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF78350F),
    info: Color(0xFF2563EB),
    infoContainer: Color(0xFFDBEAFE),
    onInfoContainer: Color(0xFF1E3A8A),
  );

  static const _dark = DilixSemanticColors(
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF06341A),
    successContainer: Color(0xFF166534),
    onSuccessContainer: Color(0xFFDCFCE7),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF422006),
    warningContainer: Color(0xFF92400E),
    onWarningContainer: Color(0xFFFEF3C7),
    info: Color(0xFF8AB4FF),
    infoContainer: Color(0xFF1D4ED8),
    onInfoContainer: Color(0xFFDBEAFE),
  );

  static DilixSemanticColors of(Brightness brightness) =>
      brightness == Brightness.light ? _light : _dark;

  /// میان‌بُر برای صفحه‌ها. اگر افزونه به هر دلیلی در درخت نبود (مثلِ تستی که
  /// `ThemeData()`ِ خام می‌سازد) به پالتِ هم‌روشناییِ پیش‌فرض برمی‌گردد تا
  /// به‌جای پرتاب‌کردنِ خطا، فقط رنگ کمی متفاوت شود.
  static DilixSemanticColors from(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<DilixSemanticColors>() ??
        of(theme.brightness);
  }

  @override
  DilixSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return DilixSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  DilixSemanticColors lerp(
    covariant DilixSemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return DilixSemanticColors(
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      successContainer: c(successContainer, other.successContainer),
      onSuccessContainer: c(onSuccessContainer, other.onSuccessContainer),
      warning: c(warning, other.warning),
      onWarning: c(onWarning, other.onWarning),
      warningContainer: c(warningContainer, other.warningContainer),
      onWarningContainer: c(onWarningContainer, other.onWarningContainer),
      info: c(info, other.info),
      infoContainer: c(infoContainer, other.infoContainer),
      onInfoContainer: c(onInfoContainer, other.onInfoContainer),
    );
  }
}
