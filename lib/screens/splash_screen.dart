import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../core/network/supabase_service.dart';
import '../providers/config_provider.dart';
import '../providers/auth_provider.dart';
import '../services/fcm_service.dart';

// ============================================================
// ملاحظة للرجوع لها لاحقا:
// تحسينات مستقبلية مقترحة لشاشة السبلاش:
// 1. Progress Bar يعكس حالة تحميل البيانات
// 2. انيميشن خروج سلس (slide up او fade out)
// 3. اضافة Slogan تحت اسم التطبيق
// 4. دعم Android native splash screen
// 5. فحص حالة الاتصال بالانترنت قبل المتابعة
// 6. تحميل Config من Supabase قبل الانتقال للرئيسية
// 7. شاشة onboarding لاول مرة يفتح المستخدم التطبيق
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.elasticOut)),
    );

    _controller.forward();
    // نؤجّل التحميل لبعد اكتمال أول frame لتفادي
    // setState()/notifyListeners() أثناء البناء.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// تحميل الإعدادات + فحص الجلسة ثم الانتقال
  Future<void> _bootstrap() async {
    final config = Provider.of<ConfigProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    // نشغّل التحميل والحد الأدنى للعرض بالتوازي
    await Future.wait([
      config.loadConfig(),
      auth.checkAuthStatus(),
      Future.delayed(const Duration(milliseconds: 1800)),
    ]);
    if (!mounted) return;

    // ✅ فحص جلسة إيميل نشطة غير معالجة (cold start من deep link)
    // عندما يفتح التطبيق من رابط الماجيك لينك، قد تكون جلسة Supabase
    // فعّالة لكن handleEmailSession لم تُستدعَ بعد.
    if (!auth.isLoggedIn) {
      final supabaseUser = SupabaseService().auth.currentUser;
      if (supabaseUser != null &&
          supabaseUser.email != null &&
          !supabaseUser.email!.endsWith('@whatsapp.local')) {
        await auth.handleEmailSession();
        if (!mounted) return;
      }
    }

    // ✅ إذا المستخدم قيد المعالجة (isNewUser) نوجّه فوراً
    // بدون المرور بشاشة الزائر — يمنع الوميض
    if (auth.isLoggedIn && auth.isNewUser) {
      await FCMService().setup();
      if (!mounted) return;
      context.go('/setup-profile');
      return;
    }

    // تهيئة FCM وطلب إذن الإشعارات قبل التوجيه؛ حتى لا تتزامن نافذة
    // صلاحيات النظام مع سؤال دليل المستخدم.
    await FCMService().setup();
    if (!mounted) return;

    // التوجّه حسب حالة المستخدم
    if (auth.isLoggedIn) {
      if (auth.isNewUser) {
        context.go('/setup-profile');
      } else if (auth.isLawyer) {
        context.go('/lawyer/dashboard');
      } else if (auth.isExpediter) {
        context.go('/expediter/tasks');
      } else if (auth.isSenior) {
        context.go('/admin/dashboard');
      } else if (auth.isEmployee) {
        context.go('/employee/home');
      } else if (auth.isSupervisor) {
        context.go('/executor/tasks');
      } else if (auth.isPhotographer) {
        context.go('/photographer/tasks');
      } else if (auth.isBroker) {
        context.go('/broker/dashboard');
      } else {
        context.go('/user/home');
      }
    } else {
      context.go('/home'); // شاشة الزائر
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // تكبير الشعار ليأخذ مساحة أكبر — مع سقف آمن للشاشات القصيرة
    // (كان يفيض ~34px على أجهزة مثل TECNO KI7: RenderFlex overflow)
    var logoSize = (screenSize.shortestSide * 0.85).clamp(280.0, 480.0);
    final hAllowance = screenSize.height - 300; // حجز النصوص واللودر تحت الشعار
    if (logoSize > hAllowance) {
      logoSize = hAllowance.clamp(180.0, logoSize);
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Stack(
        children: [
          // ─── تأثير إضاءة خلفي (Glow) ───
          Positioned(
            top: screenSize.height * 0.2,
            left: -screenSize.width * 0.2,
            child: Container(
              width: screenSize.width * 1.4,
              height: screenSize.width * 1.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryGold.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ─── الشعار الكبير ───
                    Opacity(
                      opacity: _fadeAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGold.withOpacity(0.15),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // دائرة ذهبية رقيقة محيطة
                              Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryGold.withOpacity(0.4),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              // الشعار الفعلي
                              Padding(
                                padding: EdgeInsets.all(logoSize * 0.12),
                                child: Image.asset(
                                  'assets/images/logo_app.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.apartment_rounded,
                                    size: logoSize * 0.5,
                                    color: AppTheme.primaryGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: screenSize.height * 0.05),

                    // ─── النصوص العصرية ───
                    Opacity(
                      opacity: _fadeAnimation.value,
                      child: Column(
                        children: [
                          Text(
                            'المكتب العقاري الإلكتروني',
                            style: GoogleFonts.cairo(
                              color: AppTheme.primaryGold,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          AppTheme.gapHeightXS,
                          Text(
                            'SWEEDA REAL ESTATE',
                            style: GoogleFonts.montserrat(
                              color: AppTheme.primaryGold.withOpacity(0.5),
                              fontSize: AppTheme.fontSizeXS,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AppTheme.gapHeightXXL,
                          // شعار تسويقي صغير (Slogan)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: AppTheme.radiusXL,
                              border: Border.all(color: Colors.white10),
                              color: Colors.white.withOpacity(0.03),
                            ),
                            child: Text(
                              'وجهتك الموثوقة لعقارات وسيارات السويداء',
                              style: GoogleFonts.cairo(
                                color: AppTheme.textGrey.withOpacity(0.8),
                                fontSize: AppTheme.fontSizeCaption,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 60),

                    // ─── مؤشر التحميل ───
                    SizedBox(
                      width: 180,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: AppTheme.radiusMedium,
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Colors.white.withOpacity(0.05),
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGold),
                            ),
                          ),
                          AppTheme.gapHeightMedium,
                          Text(
                            'جاري تهيئة النظام...',
                            style: GoogleFonts.cairo(
                              color: AppTheme.textGrey.withOpacity(0.5),
                              fontSize: AppTheme.fontSizeXS,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
