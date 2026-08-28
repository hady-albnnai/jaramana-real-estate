import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نقطة الوصول المركزية لـ Supabase
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static bool _initialized = false;
  static String? _url;
  static String? _publishableKey;

  /// تهيئة Supabase — تُستدعى مرة واحدة في main()
  static Future<void> initialize({
    required String url,
    required String publishableKey,
  }) async {
    if (_initialized) return;
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: publishableKey,
        debug: kDebugMode,
      );
      _url = url;
      _publishableKey = publishableKey;
      _initialized = true;
    } catch (e) {
      rethrow;
    }
  }

  /// URL الخاص بـ Supabase project
  static String? get url => _url;

  /// Publishable/Anon Key
  static String? get publishableKey => _publishableKey;

  /// الوصول لـ Supabase Client
  SupabaseClient get client => Supabase.instance.client;

  /// الوصول لـ Auth
  GoTrueClient get auth => Supabase.instance.client.auth;

  /// الوصول لـ Storage
  SupabaseStorageClient get storage => Supabase.instance.client.storage;

  /// المستخدم الحالي
  User? get currentUser => auth.currentUser;

  /// Stream للمستخدم الحالي
  Stream<AuthState> get authStateChanges => auth.onAuthStateChange;

  /// هل التطبيق جاهز؟
  bool get isReady => _initialized;

  /// يحاول الحصول على access token صالح مع تحديث تلقائي إذا لزم
  Future<String?> getValidAccessToken() async {
    try {
      var session = auth.currentSession;

      // لا يوجد جلسة أصلاً → لا داعي لمحاولة التحديث
      if (session == null) return null;

      if (session.expiresAt != null) {
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          session.expiresAt! * 1000,
        );
        final now = DateTime.now();
        if (now.isBefore(expiresAt.subtract(const Duration(minutes: 5)))) {
          return session.accessToken;
        }
      }

      // التوكن منتهي → حاول التحديث فقط إذا يوجد refresh token
      if (session.refreshToken != null && session.refreshToken!.isNotEmpty) {
        try {
          final response = await auth.refreshSession();
          if (response.session != null) {
            return response.session!.accessToken;
          }
        } catch (_) {}
      }

      // Last resort
      session = auth.currentSession;
      return session?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// استدعاء Edge Function مع إضافة توكن الجلسة المخصص إذا لزم الأمر
  Future<dynamic> invokeFunction(
    String functionName, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('staff_session_token');
    final storedUserId = prefs.getString('user_id') ?? currentUser?.id;

    // ✅ نحصل على توكن صالح مع تحديث تلقائي
    final jwt = await getValidAccessToken();

    final finalHeaders = Map<String, String>.from(headers ?? {});

    if (jwt != null) {
      // JWT is primary. Custom password-login sessions are sent in the body
      // as staff_session_token so Edge Function JWT verification remains safe.
      finalHeaders['Authorization'] = 'Bearer $jwt';
    }

    dynamic finalBody = body;
    if (body is Map) {
      final mapBody = Map<String, dynamic>.from(body);
      if (sessionToken != null && sessionToken.isNotEmpty && mapBody['staff_session_token'] == null) {
        mapBody['staff_session_token'] = sessionToken;
      }
      if (storedUserId != null && storedUserId.isNotEmpty) {
        final adminUidEmpty = (mapBody['admin_uid'] == null || mapBody['admin_uid'].toString().isEmpty) &&
            (mapBody['adminUid'] == null || mapBody['adminUid'].toString().isEmpty);
        final userUidEmpty = (mapBody['user_uid'] == null || mapBody['user_uid'].toString().isEmpty) &&
            (mapBody['userUid'] == null || mapBody['userUid'].toString().isEmpty);

        if (functionName.startsWith('admin-') && adminUidEmpty) {
          mapBody['admin_uid'] = storedUserId;
        }
        if (!functionName.startsWith('admin-') && userUidEmpty) {
          mapBody['user_uid'] = storedUserId;
        }
      }
      finalBody = mapBody;
    }

    return await _invokeWithErrorCodeExtraction(functionName, finalBody, finalHeaders);
  }

  /// 🩹 2026-08-28: كان جسم رد الخطأ من دوال Edge يُفقد كلياً — أي فشل من أي
  /// دالة (400/401/500 مع رمز خطأ عربي جاهز) يتحول إلى FunctionException عامة
  /// تظهر للمستخدم «حدث خلل أثناء الاتصال بالخادم» بلا سبب حقيقي (بلاغ المالك:
  /// إرسال عرض للمراجعة يفشل برسالة عامة). هنا نستخرج رمز الخطأ من جسم الرد
  /// ونعيد رميه كاستثناء نظيف يلتقطه ErrorUtils ويترجمه.
  Future<dynamic> _invokeWithErrorCodeExtraction(
    String functionName,
    dynamic body,
    Map<String, String> headers,
  ) async {
    try {
      return await client.functions.invoke(
        functionName,
        body: body,
        headers: headers,
      );
    } on FunctionException catch (fe) {
      // نفس النمط المجرّب في appointment_provider: جسم الرد يصل عبر details
      final details = fe.details;
      String code = '';
      if (details is Map) {
        code = (details['error'] ?? details['message'] ?? '').toString();
      } else if (details is String) {
        code = details;
      }
      code = code.trim();
      if (code.isEmpty) rethrow;
      throw Exception(code);
    }
  }
}
