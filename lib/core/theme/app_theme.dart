import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ═══════════════════════════════════════════════════════════════
  // الألوان الأساسية - Core Colors
  // ═══════════════════════════════════════════════════════════════
  static const Color primaryGold = Color(0xFFB5A287);
  static const Color deepBlack = Color(0xFF09111B);
  static const Color scaffoldBackground = Color(0xFF09111B);
  static const Color lightGold = Color(0xFFEED9BB);
  static const Color surfaceBlack = Color(0xFF121B26);
  static const Color errorRed = Color(0xFFB3261E);
  static const Color textWhite = Color(0xFFEED9BB);
  static const Color textGrey = Color(0xFFB5A287);

  // ═══════════════════════════════════════════════════════════════
  // الألوان الدلالية - Semantic Colors
  // ═══════════════════════════════════════════════════════════════
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color warningOrange = Color(0xFFED6C02);
  static const Color infoBlue = Color(0xFF62B6C1);
  static const Color pendingYellow = Color(0xFFFFB300);
  static const Color disabledGrey = Color(0xFFBDBDBD);
  static const Color borderGrey = Color(0xFF455A5C);
  static const Color cardBackground = Color(0xFF121B26);
  static const Color inputBackground = Color(0xFF182B36);

  // ═══════════════════════════════════════════════════════════════
  // أحجام الخطوط - Font Sizes
  // ═══════════════════════════════════════════════════════════════
  static const double fontSizeXS = 10.0;      // نصوص صغيرة جداً
  static const double fontSizeCaption = 11.0;  // تسميات وتعليقات
  static const double fontSizeSmall = 12.0;    // نصوص ثانوية
  static const double fontSizeBody = 13.0;     // نصوص أساسية
  static const double fontSizeMedium = 14.0;   // نصوص متوسطة
  static const double fontSizeSubtitle = 16.0; // عناوين فرعية
  static const double fontSizeTitle = 18.0;    // عناوين رئيسية
  static const double fontSizeHeadline = 20.0; // عناوين بارزة
  static const double fontSizeLarge = 24.0;    // نصوص كبيرة
  static const double fontSizeXL = 28.0;       // نصوص كبيرة جداً
  static const double fontSizeDisplay = 32.0;  // عرض رئيسي

  // ═══════════════════════════════════════════════════════════════
  // المسافات والتباعد - Spacing
  // ═══════════════════════════════════════════════════════════════
  static const double spacingXXS = 2.0;
  static const double spacingXS = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 12.0;
  static const double spacingLarge = 16.0;
  static const double spacingXL = 20.0;
  static const double spacingXXL = 24.0;
  static const double spacingXXXL = 32.0;

  // ═══════════════════════════════════════════════════════════════
  // الحشوة الداخلية - Padding
  // ═══════════════════════════════════════════════════════════════
  static const double paddingXXS = 2.0;
  static const double paddingXS = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 12.0;
  static const double paddingLarge = 16.0;
  static const double paddingXL = 20.0;
  static const double paddingXXL = 24.0;
  static const double paddingXXXL = 32.0;

  // ═══════════════════════════════════════════════════════════════
  // EdgeInsets الجاهزة - Predefined EdgeInsets
  // ═══════════════════════════════════════════════════════════════
  static const EdgeInsets paddingAllSmall = EdgeInsets.all(paddingSmall);
  static const EdgeInsets paddingAllMedium = EdgeInsets.all(paddingMedium);
  static const EdgeInsets paddingAllLarge = EdgeInsets.all(paddingLarge);
  static const EdgeInsets paddingAllXL = EdgeInsets.all(paddingXL);
  
  static const EdgeInsets paddingHorizontalSmall = EdgeInsets.symmetric(horizontal: paddingSmall);
  static const EdgeInsets paddingHorizontalMedium = EdgeInsets.symmetric(horizontal: paddingMedium);
  static const EdgeInsets paddingHorizontalLarge = EdgeInsets.symmetric(horizontal: paddingLarge);
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(horizontal: paddingXL);
  
  static const EdgeInsets paddingVerticalSmall = EdgeInsets.symmetric(vertical: paddingSmall);
  static const EdgeInsets paddingVerticalMedium = EdgeInsets.symmetric(vertical: paddingMedium);
  static const EdgeInsets paddingVerticalLarge = EdgeInsets.symmetric(vertical: paddingLarge);
  static const EdgeInsets paddingVerticalXL = EdgeInsets.symmetric(vertical: paddingXL);

  static const EdgeInsets paddingSymmetricSmall = EdgeInsets.symmetric(
    horizontal: paddingMedium,
    vertical: paddingSmall,
  );
  static const EdgeInsets paddingSymmetricMedium = EdgeInsets.symmetric(
    horizontal: paddingLarge,
    vertical: paddingMedium,
  );
  static const EdgeInsets paddingSymmetricLarge = EdgeInsets.symmetric(
    horizontal: paddingXL,
    vertical: paddingLarge,
  );

  // ═══════════════════════════════════════════════════════════════
  // SizedBox الجاهزة - Predefined SizedBox
  // ═══════════════════════════════════════════════════════════════
  static const SizedBox gapXXS = SizedBox(width: spacingXXS, height: spacingXXS);
  static const SizedBox gapXS = SizedBox(width: spacingXS, height: spacingXS);
  static const SizedBox gapSmall = SizedBox(width: spacingSmall, height: spacingSmall);
  static const SizedBox gapMedium = SizedBox(width: spacingMedium, height: spacingMedium);
  static const SizedBox gapLarge = SizedBox(width: spacingLarge, height: spacingLarge);
  static const SizedBox gapXL = SizedBox(width: spacingXL, height: spacingXL);
  static const SizedBox gapXXL = SizedBox(width: spacingXXL, height: spacingXXL);

  static const SizedBox gapWidthXXS = SizedBox(width: spacingXXS);
  static const SizedBox gapWidthXS = SizedBox(width: spacingXS);
  static const SizedBox gapWidthSmall = SizedBox(width: spacingSmall);
  static const SizedBox gapWidthMedium = SizedBox(width: spacingMedium);
  static const SizedBox gapWidthLarge = SizedBox(width: spacingLarge);
  static const SizedBox gapWidthXL = SizedBox(width: spacingXL);
  static const SizedBox gapWidthXXL = SizedBox(width: spacingXXL);

  static const SizedBox gapHeightXXS = SizedBox(height: spacingXXS);
  static const SizedBox gapHeightXS = SizedBox(height: spacingXS);
  static const SizedBox gapHeightSmall = SizedBox(height: spacingSmall);
  static const SizedBox gapHeightMedium = SizedBox(height: spacingMedium);
  static const SizedBox gapHeightLarge = SizedBox(height: spacingLarge);
  static const SizedBox gapHeightXL = SizedBox(height: spacingXL);
  static const SizedBox gapHeightXXL = SizedBox(height: spacingXXL);

  // ═══════════════════════════════════════════════════════════════
  // زوايا الحدود - Border Radius
  // ═══════════════════════════════════════════════════════════════
  static const double borderRadiusXS = 4.0;
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 16.0;
  static const double borderRadiusXL = 20.0;
  static const double borderRadiusXXL = 24.0;
  static const double borderRadiusRound = 999.0; // دائري تماماً

  static const BorderRadius radiusXS = BorderRadius.all(Radius.circular(borderRadiusXS));
  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(borderRadiusSmall));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(borderRadiusMedium));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(borderRadiusLarge));
  static const BorderRadius radiusXL = BorderRadius.all(Radius.circular(borderRadiusXL));
  static const BorderRadius radiusXXL = BorderRadius.all(Radius.circular(borderRadiusXXL));
  static const BorderRadius radiusRound = BorderRadius.all(Radius.circular(borderRadiusRound));

  // ═══════════════════════════════════════════════════════════════
  // الظلال - Shadows
  // ═══════════════════════════════════════════════════════════════
  static const List<BoxShadow> shadowSmall = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Color(0x29000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> shadowLarge = [
    BoxShadow(
      color: Color(0x3D000000),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════
  // المدة الزمنية للأنيميشن - Animation Durations
  // ═══════════════════════════════════════════════════════════════
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);

  static OverlayEntry? _activeMessageEntry;

  /// يعرض الرسائل فوق كل الطبقات (Dialogs / BottomSheets) بدل SnackBar العادي
  /// الذي كان يظهر أحياناً خلف النوافذ المنبثقة.
  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
      return;
    }

    hideSnackBar(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.maybeOf(ctx);
        final top = (media?.padding.top ?? 0) + 12;
        final width = media?.size.width ?? 360;
        final isWide = width > 700;
        final bg = snackBar.backgroundColor ?? const Color(0xFF1E1A12);
        final fg = bg.computeLuminance() > 0.55 ? deepBlack : Colors.white;

        return Positioned(
          top: top,
          left: isWide ? (width - 560) / 2 : 16,
          right: isWide ? (width - 560) / 2 : 16,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              // 🩹 م1+م8 (2026-08-20): البانر المعلوماتي (بلا زر إجراء) كان
              // يغطي شريط الهيدر فيمنع الضغط على الجرس والأزرار، وكان يبقى
              // عالقاً فوق كل الشاشات. الآن اللمس يعبره كلياً — يظهر ولا يعيق،
              // ويختفي بمؤقته الذاتي أو عند إظهار بانر أحدث.
              ignoring: snackBar.action == null,
              child: Material(
                color: Colors.transparent,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: AnimatedOpacity(
                    opacity: 1,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: primaryGold.withOpacity(0.35)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 22,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            bg == errorRed ? Icons.error_outline : Icons.info_outline,
                            color: fg,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DefaultTextStyle(
                              style: TextStyle(
                                color: fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                              child: snackBar.content,
                            ),
                          ),
                          if (snackBar.action != null) ...[
                            const SizedBox(width: 8),
                            snackBar.action!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeMessageEntry = entry;
    overlay.insert(entry);

    Future.delayed(snackBar.duration, () {
      if (_activeMessageEntry == entry && entry.mounted) {
        entry.remove();
        _activeMessageEntry = null;
      }
    });
  }

  static void hideSnackBar(BuildContext context) {
    final entry = _activeMessageEntry;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
    _activeMessageEntry = null;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryGold,
      scaffoldBackgroundColor: scaffoldBackground,
      colorScheme: const ColorScheme.light(
        primary: primaryGold,
        secondary: primaryGold,
        surface: surfaceBlack,
        error: errorRed,
        onPrimary: deepBlack,
        onSecondary: deepBlack,
        onSurface: textWhite,
      ),
      textTheme: GoogleFonts.cairoTextTheme(
        ThemeData.light().textTheme.apply(
          bodyColor: textWhite,
          displayColor: primaryGold,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: primaryGold,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGold,
          foregroundColor: deepBlack,
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceBlack,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGold),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGold, width: 2),
        ),
        labelStyle: const TextStyle(color: textGrey),
      ),
      // Removed cardTheme to avoid version conflict,
      // we will handle card styling inside the widgets themselves for stability.
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // المساعد الريسبونسيڤ - Responsive Helper Methods
  // ═══════════════════════════════════════════════════════════════
  
  /// يرجع حجم الشاشة الحالي
  static Size getScreenSize(BuildContext context) {
    return MediaQuery.of(context).size;
  }

  /// يرجع عرض الشاشة الحالي
  static double getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// يرجع ارتفاع الشاشة الحالي
  static double getScreenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// يحدد إذا كان الجهاز تابلت أو شاشة كبيرة
  static bool isTablet(BuildContext context) {
    return getScreenWidth(context) >= 600;
  }

  /// يحدد إذا كان الجهاز موبايل
  static bool isMobile(BuildContext context) {
    return getScreenWidth(context) < 600;
  }

  /// يحدد إذا كان الجهاز شاشة كبيرة جداً (ديسكتوب)
  static bool isDesktop(BuildContext context) {
    return getScreenWidth(context) >= 1200;
  }

  /// يرجع حجم خط متجاوب حسب حجم الشاشة
  static double responsiveFontSize(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final width = getScreenWidth(context);
    if (width >= 1200 && desktop != null) {
      return desktop;
    } else if (width >= 600 && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  /// يرجع قيمة متجاوبة حسب حجم الشاشة
  static double responsiveValue(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final width = getScreenWidth(context);
    if (width >= 1200 && desktop != null) {
      return desktop;
    } else if (width >= 600 && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  /// يرجع EdgeInsets متجاوبة
  static EdgeInsets responsivePadding(
    BuildContext context, {
    required EdgeInsets mobile,
    EdgeInsets? tablet,
    EdgeInsets? desktop,
  }) {
    final width = getScreenWidth(context);
    if (width >= 1200 && desktop != null) {
      return desktop;
    } else if (width >= 600 && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  /// يرجع أعرض محتوى مناسب للشاشة (مثلاً للقوائم والفورمات)
  static double getMaxContentWidth(BuildContext context) {
    final width = getScreenWidth(context);
    if (width >= 1200) {
      return 1100; // ديسكتوب
    } else if (width >= 600) {
      return 540; // تابلت
    }
    return width - 32; // موبايل (16 padding من كل جانب)
  }

  /// يرجع عدد الأعمدة المناسب للشبكة حسب حجم الشاشة
  static int getGridColumns(BuildContext context, {int mobile = 1, int tablet = 2, int desktop = 3}) {
    final width = getScreenWidth(context);
    if (width >= 1200) {
      return desktop;
    } else if (width >= 600) {
      return tablet;
    }
    return mobile;
  }

  /// يحدد إذا كان الاتجاه أفقي أو عمودي
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// يحدد إذا كان الاتجاه عمودي
  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }
}
