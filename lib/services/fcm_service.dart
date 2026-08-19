import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/supabase_service.dart';
import '../core/router/app_router.dart';
import '../core/services/notification_router.dart';
import '../core/utils/error_utils.dart';
import '../providers/notification_provider.dart';

/// خدمة Firebase Cloud Messaging (FCM)
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  late FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  String? _currentToken;

  /// دور المستخدم الحالي — يلزم لتوجيه إشعارات الأدوار (معقّب/مصوّر/محامٍ).
  /// يُحدَّث من AuthProvider عند الدخول لأن _navigateFromData متزامنة.
  int _currentRole = 0;
  void setCurrentRole(int role) => _currentRole = role;
  bool _initialized = false;
  String? _lastError;

  String? get currentToken => _currentToken;
  String? get lastError => _lastError;

  void clearError() => _lastError = null;

  void _setError(Object? error) {
    _lastError = ErrorUtils.arabicMessage(error);
  }

  /// تهيئة Firebase + FCM — تُستدعى مرّة واحدة في main()
  static Future<void> initializeFirebase() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      FCMService()._setError(e);
      rethrow;
    }
  }

  /// تهيئة الـ FCM service الكاملة
  Future<void> setup() async {
    if (_initialized) return;

    try {
      _messaging = FirebaseMessaging.instance;

      // 1) طلب الأذونات
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );// 2) إعدادات local notifications
      await _initLocalNotifications();

      // 3) الحصول على الـ token
      _currentToken = await _messaging.getToken();// 4) تسجيل التوكن
      if (_currentToken != null) {
        await _registerDeviceToken(_currentToken!);
      }

      // 5) الاستماع لتغيير التوكن
      _messaging.onTokenRefresh.listen((newToken) async {_currentToken = newToken;
        await _registerDeviceToken(newToken);
      });

      // 6) معالجة الإشعارات الواردة
      _setupMessageHandlers();

      _initialized = true;
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // إنشاء قناة الإشعارات
    const channel = AndroidNotificationChannel(
      'sweeda_default',
      'إشعارات عقارات السويداء',
      description: 'الإشعارات العامة',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        // المستخدم ضغط على local notification
        _handleNotificationTap(response.payload);
      },
    );
  }

  void _setupMessageHandlers() {
    // الإشعارات لما التطبيق مفتوح
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    // الإشعارات لما المستخدم يضغط عليها من الخلفية
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    // الإشعار اللي فتح التطبيق من حالة مغلقة
    _messaging.getInitialMessage().then((message) {
      if (message != null) _handleMessageOpenedApp(message);
    });
  }

  /// إشعار وصل والتطبيق مفتوح → نعرضه + نحفظه في DB
  void _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final suppressBanner = _shouldSuppressBanner(data);

    if (notification != null && !suppressBanner) {
      // 1) عرض local notification
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'sweeda_default',
            'إشعارات عقارات السويداء',
            channelDescription: 'الإشعارات العامة',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_notification',
            color: const Color(0xFFD4AF37),
            styleInformation: BigTextStyleInformation(
              notification.body ?? '',
              contentTitle: notification.title,
            ),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: data.toString(),
      );
    }

    // 2) حفظ في DB ليظهر داخل التطبيق — يبقى في كل الحالات (الشارة والقائمة تتحدثان)
    await _saveNotificationToDb(
      title: notification?.title ?? '',
      body: notification?.body ?? '',
      data: data,
    );

    // 🔄 2026-08-19: وصول Push والتطبيق مفتوح ⇒ تحديث فوري للقوائم والشارات
    // (شاشة الإشعارات تستمع وتعيد الجلب — بلا استطلاع دوري ثقيل)
    NotificationProvider.requestRefresh();
  }

  /// 🚫 نظام «واتساب» (2026-08-19): لا نعرض بانر Push والمستخدم مفتوح على
  /// شاشة الإشعارات (يرى القائمة نفسها)، ولا لإشعارات المحادثة وهو داخل
  /// تلك المحادثة تحديداً (المحادثة تُحدَّث عبر Realtime خاص بها أصلاً).
  /// الحجب جانب عرضي فقط — الحفظ في DB يتم دائماً.
  bool _shouldSuppressBanner(Map<String, dynamic> data) {
    try {
      final path =
          AppRouter.router.routerDelegate.currentConfiguration.uri.path;
      // شاشة الإشعارات: نحجب كل البانرات — المستخدم يرى القائمة نفسها.
      if (path == '/user/notifications') return true;

      // داخل محادثة: نحجب إشعارات تلك المحادثة فقط، وتبقى باقي الإشعارات
      // (عروض، مواعيد...) تصل بانر عادي — تماماً كواتساب.
      if (path.startsWith('/legal/chat/')) {
        final chatId = path.substring('/legal/chat/'.length);
        final act = (data['act'] ?? data['action'] ?? '').toString();
        final refId = (data['ref_id'] ?? data['id'] ?? '').toString();
        const chatActs = {
          'chat_started',
          'chat_message',
          'chat_renewed',
          'chat_extended',
          'legal_lawyer_ready',
          'legal_user_joined',
          'legal_session_auto_started',
          'legal_session_started',
          'legal_session_ended',
          'legal_renewal_paid_ready',
        };
        if (chatActs.contains(act)) return refId.isEmpty || refId == chatId;
        return refId == chatId;
      }
    } catch (_) {
      // أي خطأ في قراءة المسار الحالي ⇒ لا نحجب (نعرض البانر) — لا كتمان في الشك.
    }
    return false;
  }

  /// المستخدم ضغط على إشعار → نتنقل للشاشة المناسبة
  void _handleMessageOpenedApp(RemoteMessage message) {_navigateFromData(message.data);
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null) return;// parse الـ payload (format: {key: value, key2: value2})
    try {
      // إزالة الأقواس والـ spaces
      final cleaned = payload.replaceAll('{', '').replaceAll('}', '').trim();
      if (cleaned.isEmpty) return;
      final data = <String, dynamic>{};
      for (final pair in cleaned.split(',')) {
        final parts = pair.split(':');
        if (parts.length >= 2) {
          data[parts[0].trim()] = parts.sublist(1).join(':').trim();
        }
      }
      _navigateFromData(data);
    } catch (e) {
      _setError(e);
    }
  }

  /// 🧭 التنقل من إشعار Push — عبر **نفس** الموجّه الذي تستخدمه شاشة الإشعارات
  ///
  /// 2026-08-14: كان هنا منطق مستقل يوجّه بـ`data['type']` (6 حالات) بينما
  /// الشاشة توجّه بـ`tp` (حالتان) ⇒ نفس الحدث يوصل لمكانين مختلفين حسب طريقة
  /// الفتح، وكلاهما يجهل الاستشارة القانونية والتصوير. الآن مصدر واحد.
  void _navigateFromData(Map<String, dynamic> data) {
    try {
      final target = NotificationRouter.fromPushData(data, role: _currentRole);
      final router = AppRouter.router;
      if (target.hasRoute) {
        router.push(target.route!);
      } else {
        // معلوماتي أو ممنوع بالدور ⇒ شاشة الإشعارات (سياق آمن دائماً)
        router.push('/user/notifications');
      }
    } catch (e) {
      _setError(e);
    }
  }

  /// حفظ الإشعار في DB ليظهر داخل التطبيق
  Future<void> _saveNotificationToDb({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('user_id');
      if (uid == null) return;

      // Phase 8: RPC 'notify_user' is locked. Local messages shouldn't duplicate DB triggers.
      // await SupabaseService().client.rpc('notify_user', params: {...});
    } catch (e) {
      _setError(e);
    }
  }

  /// تسجيل التوكن عبر Edge Function (user-account/register_fcm_token)
  /// إصلاح 2026-07-27: الكتابة المباشرة في user_devices كانت محظورة بـ RLS
  /// (منذ تشديد 2026-06-28) ويُبتلع خطؤها بصمت → صفر أجهزة مسجلة = بلا Push.
  /// التشطيب/التفعيل/إعادة الإسناد تتم كلها داخل RPC register_fcm_token.
  Future<void> _registerDeviceToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('user_id');

      if (uid == null) {
        return;
      }

      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : 'web';

      await SupabaseService().invokeFunction(
        'user-account',
        body: {
          'action': 'register_fcm_token',
          'user_uid': uid,
          'device_token': token,
          'platform': platform,
        },
      );
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> registerCurrentTokenForUser() async {
    if (_currentToken != null) {
      await _registerDeviceToken(_currentToken!);
    }
  }

  Future<void> unregisterDevice() async {
    if (_currentToken == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('user_id');
      if (uid == null) return;
      await SupabaseService().invokeFunction(
        'user-account',
        body: {
          'action': 'unregister_fcm_token',
          'user_uid': uid,
          'device_token': _currentToken!,
        },
      );
    } catch (e) {
      _setError(e);
    }
  }
}

/// معالج الإشعارات بالخلفية
/// مهم: Firebase Messaging SDK يعرض الإشعار تلقائياً عند background/terminated
/// فلا نحتاج local notification هنا — يكفي init الـ engine.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();// ملاحظة: لا تستدعِ flutter_local_notifications هنا — Firebase يعرضها تلقائياً
}
