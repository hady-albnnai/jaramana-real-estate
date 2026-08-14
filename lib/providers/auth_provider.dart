import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../core/network/supabase_service.dart';
import '../core/services/business_service.dart';
import '../core/services/device_service.dart';
import '../core/utils/error_utils.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';

class AuthProvider with ChangeNotifier {
  UserModel? _userModel;
  String? _currentPhone;
  String? _currentEmail;
  String? _currentOtp;
  AuthChannel _channel = AuthChannel.sms;
  bool _isNewUser = false;
  bool _emailSessionHandled = false;

  String? _lastError;

  UserModel? get userModel => _userModel;
  String? get currentPhone => _currentPhone;
  String? get currentEmail => _currentEmail;
  String? get currentOtp => _currentOtp;
  AuthChannel get channel => _channel;
  bool get isNewUser => _isNewUser;
  bool get isLoggedIn => _userModel != null;
  String? get lastError => _lastError;
  bool get isAdmin => _userModel?.isAdmin ?? false;
  bool get isBroker => _userModel?.isBroker ?? false;
  bool get isInternal => _userModel?.isInternal ?? false;
  bool get isPhotographer => _userModel?.isPhotographer ?? false;
  bool get isSupervisor => _userModel?.isSupervisor ?? false;
  bool get isEmployee => _userModel?.isEmployee ?? false;
  bool get isSenior => _userModel?.isSenior ?? false;
  bool get isManager => _userModel?.isManager ?? false;
  bool get isLawyer => _userModel?.isLawyer ?? false;
  bool get isExpediter => _userModel?.isExpediter ?? false;

  // ════════════════════════════════════════════════════════════════════
  // 🔑 اسم مستخدم + كلمة مرور
  // ════════════════════════════════════════════════════════════════════

  /// تسجيل الدخول باسم مستخدم/رقم هاتف + كلمة مرور
  Future<bool> loginWithPassword(String identifier, String password) async {
    try {
      debugPrint('👉 [AUTH_DEBUG] Starting loginWithPassword for id="$identifier"');
      // تنظيف أي جلسات قديمة لضمان عدم تعارض التوكنات
      await AuthService().signOut();
      
      _lastError = null;
      final result = await SupabaseService().invokeFunction('user-account', body: {'action': 'login_with_password', 'identifier': identifier, 'password': password});
      debugPrint('👉 [AUTH_DEBUG] invokeFunction login result data: ${result.data}');

      final respData = result.data is Map ? Map<String, dynamic>.from(result.data) : null;
      final data = respData?['result'] is Map ? Map<String, dynamic>.from(respData!['result']) : respData;
      if (data == null || data['success'] != true) {
        _lastError = 'فشل تسجيل الدخول';
        debugPrint('👉 [AUTH_DEBUG] login failed: data=$data');
        return false;
      }

      final userId = data['user_id'] as String;
      _isNewUser = false;

      // حفظ الجلسة محلياً أولاً قبل جلب الملف الشخصي لكي تستخدم الدالة التوكن المحفوظ
      final prefs = await _getPrefs();
      await prefs.setString('user_id', userId);
      await prefs.setString('auth_channel', 'password');

      final staffSession = data['staff_session'];
      if (staffSession is Map && staffSession['success'] == true) {
        final token = staffSession['session_token']?.toString();
        final expiresAt = staffSession['expires_at']?.toString();
        if (token != null && token.isNotEmpty) {
          await prefs.setString('staff_session_token', token);
        }
        if (expiresAt != null && expiresAt.isNotEmpty) {
          await prefs.setString('staff_session_expires_at', expiresAt);
        }
      } else {
        await prefs.remove('staff_session_token');
        await prefs.remove('staff_session_expires_at');
      }

      final profile = data['profile'];
      if (profile is Map) {
        _userModel = UserModel.fromSupabase(Map<String, dynamic>.from(profile), userId);
        DeviceService().registerWithServer();
      } else {
        await _loadUserData(userId);
      }

      // تسجيل FCM token + تزويده بالدور لتوجيه الإشعارات الصحيح
      FCMService().setCurrentRole(_userModel?.role ?? 0);
      await FCMService().registerCurrentTokenForUser();

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('👉 [AUTH_DEBUG] Exception in loginWithPassword: $e');
      final msg = e.toString();
      if (msg.contains('USER_NOT_FOUND')) {
        _lastError = 'لم يتم العثور على حساب بهذا الاسم أو الرقم';
      } else if (msg.contains('WRONG_PASSWORD')) {
        _lastError = 'كلمة المرور غير صحيحة';
      } else if (msg.contains('NO_PASSWORD_SET')) {
        _lastError = 'لم يتم تعيين كلمة مرور لهذا الحساب، سجّل دخولك عبر واتساب أولاً';
      } else if (msg.contains('USER_BANNED')) {
        _lastError = 'حسابك محظور';
      } else if (msg.contains('USER_FROZEN')) {
        _lastError = 'حسابك مجمّد مؤقتاً';
      } else {
        _lastError = ErrorUtils.arabicMessage(e);
      }
      return false;
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  // ════════════════════════════════════════════════════════════════════
  // 📱 SMS OTP
  // ════════════════════════════════════════════════════════════════════

  Future<bool> sendSMSOTP(String phone) async {
    try {
      _currentPhone = phone;
      _channel = AuthChannel.sms;
      final result = await AuthService().sendSMSOTP(phone);
      if (result['success'] == true) {
        if (result['fallbackOtp'] != null) {
          _lastError = 'DEBUG: ${result['fallbackOtp']}';
          _currentOtp = result['fallbackOtp']?.toString();
        } else {
          _currentOtp = null;
        }
        notifyListeners();
        return true;
      }
      _lastError = result['error'];
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifySMSOTP(String code) async {
    try {
      // تنظيف أي جلسات قديمة قبل بدء جلسة جديدة عبر OTP
      await AuthService().signOut();
      
      if (_currentPhone == null) return false;
      final result = await AuthService().verifySMSOTP(_currentPhone!, code);
      if (result['success'] == true) {
        final userId = result['userId'];
        _isNewUser = result['isNewUser'] ?? false;
        await _loadUserData(userId);
        return true;
      }
      _lastError = result['error'];
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // 📧 Email Magic Link
  // ════════════════════════════════════════════════════════════════════

  Future<bool> sendEmailMagicLink(String email) async {
    try {
      _currentEmail = email;
      _channel = AuthChannel.email;
      final result = await AuthService().sendEmailMagicLink(email);
      if (result['success'] == true) {
        _lastError = null;
      }
      if (result['success'] != true) {
        final err = result['error']?.toString() ?? '';
        if (err == 'EMAIL_ALREADY_REGISTERED') {
          _lastError = 'هذا الإيميل مسجل بحساب آخر — سجّل دخولك عبر رقم الهاتف';
        } else {
          _lastError = ErrorUtils.arabicMessage(Exception(err));
        }
      }
      notifyListeners();
      return result['success'] == true;
    } catch (e) {
      _lastError = ErrorUtils.arabicMessage(e);
      return false;
    }
  }

  /// يُستدعى تلقائياً عند فتح التطبيق من deep link الماجيك لينك.
  /// مهم: لا نعمل signOut هنا لأن Supabase يكون قد أنشأ جلسة الإيميل للتو؛
  /// نكتفي بتنظيف الجلسة المحلية القديمة حتى لا يحدث AUTH_MISMATCH.
  /// يتضمن حماية من الاستدعاء المزدوج عبر _emailSessionHandled.
  Future<bool> handleEmailSession() async {
    if (_emailSessionHandled) return isLoggedIn;
    _emailSessionHandled = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      await prefs.remove('user_phone');
      await prefs.remove('user_email');
      await prefs.remove('auth_channel');
      await prefs.remove('staff_session_token');
      await prefs.remove('staff_session_expires_at');

      final result = await AuthService().handleEmailSession();
      if (result['success'] == true) {
        _lastError = null;
        final serverSaysNew = result['isNewUser'] as bool? ?? false;
        await _loadUserData(result['userId'] as String);
        _isNewUser = serverSaysNew ||
            !(_userModel?.hasUsername ?? false) ||
            !(_userModel?.hasPassword ?? false);
        notifyListeners();
        return true;
      }
      _lastError = ErrorUtils.arabicMessage(
        Exception(result['error']?.toString() ?? 'EMAIL_AUTH_FAILED'),
      );
      _emailSessionHandled = false; // السماح بإعادة المحاولة عند الفشل
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = ErrorUtils.arabicMessage(e);
      _emailSessionHandled = false; // السماح بإعادة المحاولة عند الخطأ
      notifyListeners();
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // المستخدم
  // ════════════════════════════════════════════════════════════════════

  Future<void> _loadUserData(String userId) async {
    try {
      debugPrint('👉 [LOAD_USER_DEBUG] Calling get_full_profile for userId="$userId"');
      final response = await SupabaseService().invokeFunction('user-account', body: {'action': 'get_full_profile', 'user_uid': userId});
      debugPrint('👉 [LOAD_USER_DEBUG] get_full_profile res: ${response.data}');
      final data = response.data as Map;
      if (data['success'] != true || data['profile'] == null) {
        debugPrint('👉 [LOAD_USER_DEBUG] profile null or success false! data=$data');
        return;
      }
      final profileList = data['profile'];
      if (profileList is! List || profileList.isEmpty) {
        debugPrint('👉 [LOAD_USER_DEBUG] profileList empty!');
        return;
      }
      final row = Map<String, dynamic>.from(profileList.first as Map);
      _userModel = UserModel.fromSupabase(row, userId);
      // تزويد FCM بالدور هنا أيضاً — هذا مسار استعادة الجلسة عند فتح التطبيق
      FCMService().setCurrentRole(_userModel?.role ?? 0);
      debugPrint('👉 [LOAD_USER_DEBUG] _userModel set! nm=${_userModel?.nm}');
      notifyListeners();
      DeviceService().registerWithServer();
      // 🚫 GP-004: تحميل قائمة المحظورين مع بيانات المستخدم، كي تُخفى
      // عروضهم من أول إطار بدل أن تومض ثم تختفي. لا await: لا نؤخّر
      // إظهار الواجهة على نداء ثانوي — يصل ويُحدّث عبر notifyListeners.
      unawaited(refreshBlockedOffers());
    } catch (e) {
      debugPrint('👉 [LOAD_USER_DEBUG] Exception: $e');
    }
  }

  Future<bool> completeProfile({required String name, required String sid}) async {
    try {
      if (_userModel == null) return false;
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'update_profile',
        'user_uid': _userModel!.uid,
        'payload': {'nm': name, 'sid': sid}
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data == null || data['success'] == false) return false;
      await _loadUserData(_userModel!.uid);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> refreshUser() async {
    final userId = await AuthService().getSavedUserId();
    if (userId != null) await _loadUserData(userId);
  }

  // ══════════════════════════════════════════════════════════════════════
  // 🚫 GP-004 (2026-08-15) — حظر المستخدمين (متطلب سياسة UGC)
  // ══════════════════════════════════════════════════════════════════════
  // سياسة Google Play تشترط مع التبليغ **إمكانية حظر المستخدمين**.
  // `SupabaseService` يحقن `staff_session_token` تلقائياً، والسيرفر يتحقق
  // أن المنفّذ هو صاحب الجلسة (مؤكَّد حياً: محاولة الانتحال تُرفض).
  //
  // معرّفات العروض المحظورة تُخزَّن هنا ليقرأها `OfferProvider` عند الفلترة
  // بلا نداء شبكي إضافي لكل قائمة.
  Set<String> _blockedOfferIds = {};
  Set<String> get blockedOfferIds => _blockedOfferIds;

  /// حظر صاحب عرض بمعرّف **العرض** (الواجهة لا تعرف `usr_id` — SEC-004).
  Future<bool> blockOfferOwner(String offerId) async {
    if (_userModel == null) {
      _lastError = 'NOT_LOGGED_IN';
      return false;
    }
    try {
      _lastError = null;
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'block_offer_owner',
        'user_uid': _userModel!.uid,
        'offer_id': offerId,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data == null || data['success'] != true) {
        // §13: نحتفظ بنصّ الخطأ الخادمي ليعرضه الاستدعاء بدل ابتلاعه.
        _lastError = data?['error']?.toString() ?? 'BLOCK_FAILED';
        return false;
      }
      await refreshBlockedOffers();
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// رفع الحظر عن مستخدم (من شاشة المحظورين).
  Future<bool> unblockUser(String blockedUid) async {
    if (_userModel == null) return false;
    try {
      _lastError = null;
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'unblock_user',
        'user_uid': _userModel!.uid,
        'blocked_uid': blockedUid,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data == null || data['success'] != true) {
        _lastError = data?['error']?.toString() ?? 'UNBLOCK_FAILED';
        return false;
      }
      await refreshBlockedOffers();
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// قائمة المحظورين لعرضها وإدارتها.
  Future<List<Map<String, dynamic>>> listMyBlocks() async {
    if (_userModel == null) return const [];
    try {
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'list_my_blocks',
        'user_uid': _userModel!.uid,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data == null || data['success'] != true) return const [];
      final raw = data['blocks'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // فشل القراءة يعني قائمة فارغة — الشاشة تعرض «لا يوجد» ولا تنهار.
      return const [];
    }
  }

  /// تحديث مجموعة العروض المخفية (الأثر متماثل: من حظرتَهم ومن حظروك).
  Future<void> refreshBlockedOffers() async {
    if (_userModel == null) {
      if (_blockedOfferIds.isNotEmpty) {
        _blockedOfferIds = {};
        notifyListeners();
      }
      return;
    }
    try {
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'blocked_offer_ids',
        'user_uid': _userModel!.uid,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data == null || data['success'] != true) return;
      final raw = data['offer_ids'];
      if (raw is! List) return;
      _blockedOfferIds = raw.map((e) => e.toString()).toSet();
      notifyListeners();
    } catch (_) {
      // فشل التحديث يُبقي القائمة السابقة — الأسوأ أن نُظهر محتوى محظوراً،
      // لكن إفراغها عند كل فشل شبكي عابر أسوأ. تُحدَّث في المحاولة التالية.
    }
  }

  String? _lastDailyStreakCheckDate;

  String _getSyriaDateString(DateTime dt) {
    final syria = dt.toUtc().add(const Duration(hours: 3));
    return '${syria.year.toString().padLeft(4, '0')}-'
        '${syria.month.toString().padLeft(2, '0')}-'
        '${syria.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> registerStreak(dynamic config) async {
    if (_userModel == null) return {'streak': 0, 'changed': false};
    if (_userModel!.isAdmin) return {'streak': 0, 'changed': false, 'awarded': false};

    final todayStr = _getSyriaDateString(DateTime.now());

    if (_userModel!.strkDt != null) {
      final lastStr = _getSyriaDateString(_userModel!.strkDt!);
      if (lastStr == todayStr) {
        _lastDailyStreakCheckDate = todayStr;
        return {
          'streak': _userModel!.strk,
          'changed': false,
          'awarded': false,
        };
      }
    }

    if (_lastDailyStreakCheckDate == todayStr) {
      return {
        'streak': _userModel!.strk,
        'changed': false,
        'awarded': false,
      };
    }

    final result =
        await BusinessService().registerDailyStreak(_userModel!.uid, config);

    _lastDailyStreakCheckDate = todayStr;

    if (result['changed'] == true) {
      await _loadUserData(_userModel!.uid);
    }

    await _checkWeeklyLogin(config);
    return result;
  }

  Future<void> _checkWeeklyLogin(dynamic config) async {
    if (_userModel == null) return;
    try {
      final pts = config?.weeklyLoginPoints ?? 100;
      final granted = await SupabaseService().invokeFunction(
        'user-account',
        body: {
          'action': 'register_weekly_login',
          'user_uid': _userModel!.uid,
          'pts': pts,
        },
      );
      if (granted.data is Map && (granted.data as Map)['success'] == true) {
        await _loadUserData(_userModel!.uid);
      }
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  Future<void> logout() async {
    await FCMService().unregisterDevice();
    await AuthService().signOut();
    _userModel = null;
    _currentPhone = null;
    _currentEmail = null;
    _currentOtp = null;
    _isNewUser = false;
    _emailSessionHandled = false;
    _lastDailyStreakCheckDate = null;
    // 🚫 GP-004: تفريغ قائمة الحظر عند الخروج — وإلا ورث المستخدمُ التالي
    // على نفس الجهاز فلترةَ من سبقه (عروض تختفي عنه بلا سبب مفهوم).
    _blockedOfferIds = {};
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    try {
      final userId = await AuthService().getSavedUserId();
      if (userId != null) await _loadUserData(userId);
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  /// ✅ تحديث متفائل: تعيين حالة التوثيق "قيد المراجعة" فوراً
  /// يمنع المستخدم من الضغط على زر طلب التوثيق مرة ثانية أثناء الانتظار
  void setVerificationPending() {
    if (_userModel != null) {
      // إنشاء نسخة جديدة بحالة vrf=1 (قيد المراجعة)
      _userModel = UserModel(
        uid: _userModel!.uid,
        nm: _userModel!.nm,
        ph: _userModel!.ph,
        eml: _userModel!.eml,
        ad: _userModel!.ad,
        role: _userModel!.role,
        sid: _userModel!.sid,
        img: _userModel!.img,
        pt: _userModel!.pt,
        bg: _userModel!.bg,
        bgTs: _userModel!.bgTs,
        bPkg: _userModel!.bPkg,
        pkgEnd: _userModel!.pkgEnd,
        pkgGrace: _userModel!.pkgGrace,
        brk: _userModel!.brk,
        brkCls: _userModel!.brkCls,
        brkNm: _userModel!.brkNm,
        sts: _userModel!.sts,
        banRsn: _userModel!.banRsn,
        ntf: _userModel!.ntf,
        stats: _userModel!.stats,
        wkLgn: _userModel!.wkLgn,
        strk: _userModel!.strk,
        strkDt: _userModel!.strkDt,
        iDel: _userModel!.iDel,
        perm: _userModel!.perm,
        tsCrt: _userModel!.tsCrt,
        tsUpd: _userModel!.tsUpd,
        vrf: 1, // ✅ قيد المراجعة
        usr: _userModel!.usr,
        pwd: _userModel!.pwd,
      );
      notifyListeners();
    }
  }

  /// ✅ إرجاع حالة التوثيق عند فشل الطلب
  void setVerificationReverted() {
    if (_userModel != null) {
      _userModel = UserModel(
        uid: _userModel!.uid,
        nm: _userModel!.nm,
        ph: _userModel!.ph,
        eml: _userModel!.eml,
        ad: _userModel!.ad,
        role: _userModel!.role,
        sid: _userModel!.sid,
        img: _userModel!.img,
        pt: _userModel!.pt,
        bg: _userModel!.bg,
        bgTs: _userModel!.bgTs,
        bPkg: _userModel!.bPkg,
        pkgEnd: _userModel!.pkgEnd,
        pkgGrace: _userModel!.pkgGrace,
        brk: _userModel!.brk,
        brkCls: _userModel!.brkCls,
        brkNm: _userModel!.brkNm,
        sts: _userModel!.sts,
        banRsn: _userModel!.banRsn,
        ntf: _userModel!.ntf,
        stats: _userModel!.stats,
        wkLgn: _userModel!.wkLgn,
        strk: _userModel!.strk,
        strkDt: _userModel!.strkDt,
        iDel: _userModel!.iDel,
        perm: _userModel!.perm,
        tsCrt: _userModel!.tsCrt,
        tsUpd: _userModel!.tsUpd,
        vrf: 0, // ✅ غير موثق
        usr: _userModel!.usr,
        pwd: _userModel!.pwd,
      );
      notifyListeners();
    }
  }
}
