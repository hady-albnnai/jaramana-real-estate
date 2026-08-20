import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/network/supabase_service.dart';
import 'core/constants/supabase_constants.dart';
import 'providers/auth_provider.dart';
import 'providers/config_provider.dart';
import 'providers/offer_provider.dart';
import 'providers/request_provider.dart';
import 'providers/appointment_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/broker_provider.dart';
import 'providers/photography_provider.dart';
import 'providers/executor_provider.dart';
import 'providers/legal_provider.dart';
import 'services/notification_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;
  String? _initError;
  StreamSubscription<AuthState>? _authSub;

  // ✅ إنشاء AuthProvider كمتغير عضو للوصول المباشر من المستمع
  // بدون الحاجة لـ BuildContext (السياق فوق MultiProvider لا يرى الـ Provider)
  final AuthProvider _authProvider = AuthProvider();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// يستمع لتغيرات auth — ينفّذ تلقائياً تسجيل دخول الإيميل
  /// بعد ما يفتح المستخدم الـ Magic Link.
  /// يدعم كلاً من:
  ///   - signedIn: عند فتح الرابط والتطبيق قيد التشغيل (warm start)
  ///   - initialSession: عند فتح الرابط والتطبيق كان مغلقاً (cold start)
  void _listenAuthChanges() {
    _authSub?.cancel();
    _authSub = SupabaseService().auth.onAuthStateChange.listen(
      (data) {
        final event = data.event;
        // ✅ معالجة signedIn (warm start) + initialSession (cold start)
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession) {
          final session = data.session;
          if (session?.user.email != null &&
              !session!.user.email!.endsWith('@whatsapp.local')) {
            if (!mounted) return;
            // إيميل حقيقي → magic link
            // ✅ استخدام المتغير العضو مباشرة بدل context.read
            if (!_authProvider.isLoggedIn) {
              _authProvider.handleEmailSession().then((ok) {
                if (!mounted || !ok) return;
                _navigateAfterEmailAuth();
              });
            }
          }
        }
      },
      onError: (error) {
        // تجاهل أخطاء انتهاء صلاحية الرابط بصمت
        // (supabase_flutter يرمي AuthException داخلياً)
        debugPrint('👉 [AUTH_LISTENER] Auth stream error: $error');
      },
    );
  }

  /// توجيه المستخدم بعد تسجيل الدخول عبر الإيميل
  void _navigateAfterEmailAuth() {
    final go = AppRouter.router;
    if (_authProvider.isNewUser) {
      go.go('/setup-profile');
    } else if (_authProvider.isLawyer) {
      go.go('/lawyer/dashboard');
    } else if (_authProvider.isExpediter) {
      go.go('/expediter/tasks');
    } else if (_authProvider.isSenior) {
      go.go('/admin/dashboard');
    } else if (_authProvider.isEmployee) {
      go.go('/employee/home');
    } else if (_authProvider.isSupervisor) {
      go.go('/executor/tasks');
    } else if (_authProvider.isPhotographer) {
      go.go('/photographer/tasks');
    } else if (_authProvider.isBroker) {
      go.go('/broker/dashboard');
    } else {
      go.go('/user/home');
    }
  }

  Future<void> _initializeApp() async {
    try {
      await SupabaseService.initialize(
          url: supabaseUrl, publishableKey: supabasePublishableKey);
      await NotificationService.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ✅ استخدام .value لأننا أنشأنا المتغير مسبقاً
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        // 🚫 GP-004 (2026-08-15): `OfferProvider` يتبع `AuthProvider` ليعرف
        // العروض المحظورة ويُخفيها. Proxy بدل قراءة متقاطعة يدوية: التحديث
        // تلقائي عند كل تغيّر في الحظر (دخول، خروج، حظر جديد، رفع حظر).
        ChangeNotifierProxyProvider<AuthProvider, OfferProvider>(
          create: (_) => OfferProvider(),
          update: (_, auth, offers) =>
              (offers ?? OfferProvider())..setBlockedIds(auth.blockedOfferIds),
        ),
        ChangeNotifierProvider(create: (_) => RequestProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => BrokerProvider()),
        ChangeNotifierProvider(create: (_) => PhotographyProvider()),
        ChangeNotifierProvider(create: (_) => ExecutorProvider()),
        ChangeNotifierProvider(create: (_) => LegalProvider()),
      ],
      child: Builder(builder: (ctx) {
        // ربط الـ listener مرة واحدة بعد ما يتوفر context
        if (_initialized && _authSub == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _listenAuthChanges();
          });
        }
        return MaterialApp.router(
          title: 'المكتب العقاري الالكتروني',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          routerConfig: AppRouter.router,
          locale: const Locale('ar', 'SY'),
          builder: (context, child) {
            if (_initError != null) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  backgroundColor: AppTheme.scaffoldBackground,
                  body: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 60),
                          const SizedBox(height: 20),
                          const Text('حدث خطأ في التهيئة',
                              style: TextStyle(
                                  color: AppTheme.textWhite, fontSize: 18)),
                          const SizedBox(height: 10),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 30),
                            child: Text(_initError!,
                                style: const TextStyle(
                                    color: AppTheme.textGrey,
                                    fontSize: 12),
                                textAlign: TextAlign.center),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                              onPressed: () => setState(() {
                                    _initError = null;
                                    _initializeApp();
                                  }),
                              child: const Text('إعادة المحاولة')),
                        ]),
                  ),
                ),
              );
            }
            // ═══════════════════════════════════════════════════════════
            // 🧱 UI-OVF-001 (2026-08-15) — سقف تكبير خط النظام
            // ═══════════════════════════════════════════════════════════
            // إعدادات إمكانية الوصول في أندرويد تسمح بتكبير الخط حتى ×2.0.
            // كل تخطيط في التطبيق مبني على ارتفاعات بكسلية ثابتة (بطاقات
            // الشبكات، ListTile، الشارات)، فأي معامل >1.15 يُحدث فيضاناً
            // جماعياً على **كل** الشاشات لا على شاشة واحدة.
            // القيد هنا يحفظ إمكانية الوصول (تكبير حتى 15%) ويمنع الانكسار،
            // وهو الحصانة العامة؛ و`FitTile` هو الحصانة الموضعية للبطاقات.
            return MediaQuery.withClampedTextScaling(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.15,
              child: Directionality(
                textDirection: TextDirection.rtl,
                // 🔒 2026-08-20: حماية سفلية عامة — أندرويد الحديث يرسم
                // التطبيق خلف شريط التحكم (الرجوع/القائمة)، فكانت أسفل
                // الشاشات تظهر تحت أزرار النظام. SafeArea سفلي يرفع محتوى
                // التطبيق فوق الشريط في كل الشاشات (النوافذ السفلية
                // المضمّنة SafeArea لا تتضاعف مسافتها).
                child: SafeArea(top: false, child: child!),
              ),
            );
          },
        );
      }),
    );
  }
}
