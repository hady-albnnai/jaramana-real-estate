import '../network/supabase_service.dart';
import '../constants/db_constants.dart';
import '../../models/config_model.dart';
import '../../models/offer_model.dart';
import '../../models/user_model.dart';

/// خدمة المنطق الخلفي المركزية (Business Logic)
///
/// تجمع العمليات غير المرئية: النقاط، البادجات، الحصص، الباقات،
/// المطابقة التلقائية، Streak، وتوليد منشورات السوشال ميديا.
///
/// تعتمد على دوال RPC الموجودة في Supabase حيثما أمكن:
/// `add_points`, `update_user_badge`, `calculate_commission`, `check_offer_duplicate`.
/// نتيجة منح نقاط مفصّلة (2026-07-27): تميّز النجاح عن بلوغ الحد اليومي عن الرفض
class AwardResult {
  final bool awarded;
  final bool limitReached;
  final int limit;
  final int points;
  final String? error;

  const AwardResult._({
    required this.awarded,
    this.limitReached = false,
    this.limit = 0,
    this.points = 0,
    this.error,
  });

  const AwardResult.awarded(int pts)
      : this._(awarded: true, points: pts);
  const AwardResult.dailyLimit(int limit)
      : this._(awarded: false, limitReached: true, limit: limit);
  const AwardResult.rejected(String err)
      : this._(awarded: false, error: err);
}

class BusinessService {
  BusinessService._internal();
  static final BusinessService _instance = BusinessService._internal();
  factory BusinessService() => _instance;

  SupabaseService get _sb => SupabaseService();

  // ═══════════════════════════════════════
  // 4.3 نظام النقاط (عبر RPC add_points)
  // ═══════════════════════════════════════

  /// إضافة نقاط لمستخدم (تستدعي Edge Function التي تحدّث البادج تلقائياً)
  Future<bool> addPoints(String uid, int points) async {
    if (uid.isEmpty || points == 0) return false;
    try {
      final res = await _sb.invokeFunction('user-account', body: {
        'action': 'award_points',
        'user_uid': uid,
        'event_type': 'manual_add',
        'points': points,
      });
      return res.data?['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// منح نقاط آمنة (تتحقق من الحدود اليومية لمنع التلاعب)
  Future<bool> awardPointsSafe(String uid, String eventType, int points) async {
    if (uid.isEmpty || points == 0) return false;
    try {
      final res = await _sb.invokeFunction('user-account', body: {
        'action': 'award_points',
        'user_uid': uid,
        'event_type': eventType,
        'points': points,
      });
      return res.data?['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // تم حذف _addPointsFallback لأن التحديثات المباشرة للـ users محظورة أمنياً
  // والاعتماد الآن كلياً على Edge Functions.

  /// منح نقاط حدث معيّن باستخدام مفاتيح الـ Config (pts.*)
  /// أمثلة المفاتيح: 'sgn','wkL','addO','dlD','strk','soc','att','ref'
  Future<bool> awardEvent(String uid, ConfigModel? config, String eventKey,
      {int fallback = 0, String? offerId}) async {
    final r = await awardEventDetailed(uid, config, eventKey,
        fallback: fallback, offerId: offerId);
    return r.awarded;
  }

  /// نسخة مفصّلة: تميّز «نجح» عن «بلغ الحد اليومي» عن رفض آخر —
  /// حتى لا تعرض الواجهة منحة وهمية عند رفض السيرفر (2026-07-27)
  Future<AwardResult> awardEventDetailed(
      String uid, ConfigModel? config, String eventKey,
      {int fallback = 0, String? offerId}) async {
    // الإدارة لا تحتاج نقاط
    try {
      final user = await _sb.client.from(DbTables.users).select('role').eq('id', uid).maybeSingle();
      if (user != null && (user['role'] as int? ?? 0) >= UserRole.minAdmin) {
        return const AwardResult.rejected('admin_role');
      }
    } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    final pts = _ptsFromConfig(config, eventKey, fallback);
    if (pts == 0) return const AwardResult.rejected('no_points');

    // ✅ Via user-rewards Edge Function
    try {
      // offer_id يمرّر حتى يحسم السيرفر ملكية العرض (منع نقاط الإعجاب بالذات)
      final res = await _sb.invokeFunction('user-rewards', body: {
        'action': 'award_points',
        'user_uid': uid,
        'event_key': eventKey,
        'points': pts, // يتجاهلها السيرفر بعد تحصين 2026-07-27 (القيمة من الكونفغ هناك)
        if (offerId != null) 'offer_id': offerId,
      });
      final data = res.data;
      if (data is Map) {
        if (data['success'] == true) return AwardResult.awarded(pts);
        final err = (data['error'] ?? '').toString();
        if (err == 'DAILY_LIMIT_REACHED') {
          return AwardResult.dailyLimit((data['limit'] as num?)?.toInt() ?? 0);
        }
        return AwardResult.rejected(err.isEmpty ? 'rejected' : err);
      }
      return data == true
          ? AwardResult.awarded(pts)
          : const AwardResult.rejected('rejected');
    } catch (_) {
      return const AwardResult.rejected('network');
    }
  }

  int _ptsFromConfig(ConfigModel? config, String key, int fallback) {
    if (config == null) return fallback;
    final ptsMap = config.data['pts'];
    final v = ptsMap is Map ? ptsMap[key] : null;
    // القيم المهيكلة {l, p} (مثل like/cmt/shr) تُقرأ من p
    if (v is num) return v.toInt();
    if (v is Map && v['p'] is num) return (v['p'] as num).toInt();
    return fallback;
  }

  /// قيمة نقاط حدث ما من الكونفغ (بنية {l,p} مدعومة) — للعرض الصحيح في الرسائل
  int pointsFor(ConfigModel? config, String key, int fallback) =>
      _ptsFromConfig(config, key, fallback);

  /// خصم نقاط (عقوبة) — pen.* في الـ Config (قيم سالبة)
  Future<bool> applyPenalty(String uid, ConfigModel? config, String penKey,
      {int fallback = 0}) async {
    int pts = fallback;
    if (config != null) {
      final penMap = config.data['pen'];
      if (penMap is Map && penMap[penKey] is num) {
        pts = (penMap[penKey] as num).toInt();
      }
    }
    if (pts == 0) return false;
    return addPoints(uid, pts); // القيمة سالبة فتُخصم، لا نحتاج لسقف يومي للخصم
  }

  // ═══════════════════════════════════════
  // 4.4 نظام الباقات والحصص (Quotas)
  // ═══════════════════════════════════════

  /// التحقق من إمكانية نشر عرض جديد حسب حصة المستخدم/الوسيط والباقة.
  ///
  /// يُرجع خريطة: {allowed: bool, used: int, limit: int, reason: String}
  Future<Map<String, dynamic>> canPublishOffer({
    required String uid,
    required int role,
    required int packageType,
    DateTime? pkgEnd,   // تاريخ انتهاء الباقة
    DateTime? pkgGrace, // تاريخ انتهاء فترة السماح
    ConfigModel? config,
  }) async {
    try {
      if (role >= UserRole.employee) {
        return {
          'allowed': true,
          'used': 0,
          'limit': 999999,
          'reason': '',
        };
      }
      // 🔒 Phase 8: نحسب الفعّالة + المحذوفة حديثاً (آخر 24 ساعة)
      // لمنع ثغرة "احذف لتنشر" — Scam #4 في التقرير الأمني
      final since24h =
          DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      List active = [];
      List recentlyDeleted = [];
      try {
        active = await _sb.client
            .from(DbTables.offers)
            .select('id')
            .eq('usr_id', uid)
            .eq('i_del', 0)
            .inFilter('sts', [0, 1, 2, 5]);
      } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }

      try {
        recentlyDeleted = await _sb.client
            .from(DbTables.offers)
            .select('id')
            .eq('usr_id', uid)
            .eq('i_del', 1)
            .gte('ts_crt', since24h);
      } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }

      final used = active.length + recentlyDeleted.length;

      // نمرر pkgEnd + pkgGrace لـ offerQuota لفحص الباقة الفعلية
      final limit = offerQuota(config,
          role: role, packageType: packageType,
          pkgEnd: pkgEnd, pkgGrace: pkgGrace);

      final allowed = used < limit;
      return {
        'allowed': allowed,
        'used': used,
        'limit': limit,
        'reason': allowed
            ? ''
            : 'وصلت للحد الأقصى ($limit عرض خلال 24 ساعة، شامل المحذوف). '
                'رقّ باقتك لنشر المزيد.',
      };
    } catch (e) {// 🔒 Phase 8: عند الفشل الكامل نمنع (fail-closed) بدل السماح للأمان
      return {
        'allowed': false,
        'used': 0,
        'limit': 0,
        'reason': 'تعذّر التحقق من حصتك (مشكلة مؤقتة في الاتصال أو الاستعلام). حاول لاحقاً أو رقّ باقتك.',
      };
    }
  }

  /// حساب حصة العروض مع فحص انتهاء الباقة
  /// إذا انتهت pkg_end → نعتبر المستخدم على الباقة المجانية (0)
  int offerQuota(ConfigModel? config,
      {required int role, required int packageType,
       DateTime? pkgEnd, DateTime? pkgGrace}) {
    if (role >= UserRole.employee) return 999999;

    // حساب الباقة الفعلية مع مراعاة فترة السماح (pkg_grace)
    final now = DateTime.now();
    int effectivePkg;
    if (packageType <= 0) {
      effectivePkg = 0;
    } else if (pkgGrace != null && pkgGrace.isAfter(now)) {
      // ضمن فترة السماح → نفس مزايا الباقة
      effectivePkg = packageType;
    } else if (pkgGrace == null && pkgEnd != null && pkgEnd.isAfter(now)) {
      // سجل قديم بدون grace → نعتمد على pkg_end
      effectivePkg = packageType;
    } else {
      effectivePkg = 0;
    }

    if (config != null) {
      // 1) حد الباقة الفعلية (pkg.{effectivePkg}.o) — له الأولوية
      final pkgMap = config.data['pkg'];
      if (pkgMap is Map && pkgMap['$effectivePkg'] is Map) {
        final o = (pkgMap['$effectivePkg'] as Map)['o'];
        if (o is num) return o.toInt();
      }
      // 2) حصة حسب الدور (qta.b للوسيط، qta.u للمستخدم)
      final isBroker = role == UserRole.broker;
      final quotas = isBroker ? config.brokerQuotas : config.userQuotas;
      final o = quotas['o'];
      if (o is num) return o.toInt();
    }
    // قيم افتراضية آمنة
    return role == UserRole.broker ? 5 : 1;
  }

  /// حصة الطلبات (qta.u.r / qta.b.r)
  int requestQuota(ConfigModel? config, {required int role}) {
    if (config != null) {
      final quotas = role == UserRole.broker ? config.brokerQuotas : config.userQuotas;
      final r = quotas['r'];
      if (r is num) return r.toInt();
    }
    return role == UserRole.broker ? 5 : 3;
  }

  Future<Map<String, dynamic>> canPublishRequest({
    required String uid,
    required int role,
    ConfigModel? config,
  }) async {
    // الإدارة معفاة من الحصة
    if (role >= UserRole.employee) {
      return {'allowed': true, 'used': 0, 'limit': 999999, 'reason': ''};
    }
    try {
      final response = await _sb.invokeFunction(
        'user-requests',
        body: {
          'action': 'can_publish',
          'user_uid': uid,
        },
      );
      final data = response.data;
      if (data is Map && data['success'] == true && data['result'] is Map) {
        final result = Map<String, dynamic>.from(data['result'] as Map);
        final reason = result['reason']?.toString() ?? '';
        return {
          'allowed': result['allowed'] == true,
          'used': result['used'] ?? 0,
          'limit': result['limit'] ?? requestQuota(config, role: role),
          'reason': reason == 'QUOTA_EXCEEDED'
              ? 'وصلت للحد الأقصى (${result['limit']} طلب).'
              : reason,
        };
      }
      return {
        'allowed': false,
        'used': 0,
        'limit': 0,
        'reason': 'تعذّر التحقق من حصتك، حاول لاحقاً.',
      };
    } catch (e) {
      return {
        'allowed': false, 'used': 0, 'limit': 0,
        'reason': 'تعذّر التحقق من حصتك، حاول لاحقاً.',
      };
    }
  }

  // ═══════════════════════════════════════
  // 4.2 المطابقة التلقائية (Requests ↔ Offers)
  // ═══════════════════════════════════════

  /// إيجاد العروض المنشورة المطابقة لطلب
  /// (حسب نوع العنصر + نوع المعاملة + العملة + نطاق السعر ±20%).
  Future<List<OfferModel>> matchOffersForRequest({
    required int elementType,
    required int transactionType,
    required double targetPrice,
    required int currency,
    double tolerance = 0.20,
  }) async {
    try {
      var q = _sb.client
          .from(DbTables.offers)
          .select(kOfferPublicColumns)
          .eq('i_del', 0)
          .eq('i_pub', 1)
          .eq('typ', elementType)
          .eq('trx', transactionType)
          .eq('cur', currency);

      if (targetPrice > 0) {
        final min = targetPrice * (1 - tolerance);
        final max = targetPrice * (1 + tolerance);
        q = q.gte('prc', min).lte('prc', max);
      }

      final res = await q.order('ts_crt', ascending: false).limit(20);
      return (res as List)
          .map((d) =>
              OfferModel.fromSupabase(Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
    } catch (e) {return [];
    }
  }

  /// إيجاد الطلبات المطابقة لعرض (الاتجاه المعاكس).
  Future<List<Map<String, dynamic>>> matchRequestsForOffer({
    required int elementType,
    required int transactionType,
    required double price,
    required int currency,
    double tolerance = 0.20,
  }) async {
    try {
      var q = _sb.client
          .from(DbTables.requests)
          .select()
          .eq('i_del', 0)
          .eq('elm', elementType)
          .eq('typ', transactionType)
          .eq('cur', currency);
      if (price > 0) {
        final min = price * (1 - tolerance);
        final max = price * (1 + tolerance);
        q = q.gte('prc', min).lte('prc', max);
      }
      final res = await q.limit(20);
      return (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {return [];
    }
  }

  // ═══════════════════════════════════════
  // 4.5 نظام Streak (تسجيل دخول يومي متتالي)
  // ═══════════════════════════════════════

  /// تسجيل دخول اليوم وتحديث سلسلة الأيام المتتالية.
  /// يمنح نقاط Streak عند الاستمرار، ويعيد الحالة الجديدة.
  /// يستخدم توقيت سوريا (UTC+3) لتحديد بداية اليوم (بعد 12 ليلاً بدمشق).
  Future<Map<String, dynamic>> registerDailyStreak(
      String uid, ConfigModel? config) async {
    try {
      final strkPts = _ptsFromConfig(config, 'strk', 50);
      // ✅ Via user-rewards Edge Function (safe)
      final res = await _sb.invokeFunction('user-rewards', body: {
        'action': 'daily_streak',
        'user_uid': uid,
        'points': strkPts,
      });
      final data = res.data as Map<String, dynamic>?;
      return data?['data'] ?? {'streak': 0, 'changed': false, 'awarded': false};
    } catch (e) {
      return {'streak': 0, 'changed': false, 'awarded': false};
    }
  }

  // ═══════════════════════════════════════
  // 4.6 توليد نص منشور السوشال ميديا
  // ═══════════════════════════════════════

  /// توليد نص جاهز للنشر على وسائل التواصل من بيانات العرض.
  /// توليد نص جاهز للنشر على وسائل التواصل من بيانات العرض.
  /// ⚠️ قاعدة صارمة بطلب المالك: لا معلومات تواصل لصاحب العرض أبداً —
  /// نتجاهل offer.contactPh تماماً، والتواصل حصراً عبر واتساب المكتب.
  String generateSocialPost(OfferModel offer, {ConfigModel? config}) {
    final buffer = StringBuffer();
    final isProperty = offer.typ == 0;
    final trx = offer.trx == 0 ? 'للبيع' : 'للإيجار';
    final emoji = isProperty ? '🏠' : '🚗';
    final cur = offer.cur == 0 ? '\$' : 'ل.س';
    final title = offer.ttl.trim().isNotEmpty
        ? offer.ttl.trim()
        : '${isProperty ? 'عقار' : 'سيارة'} $trx';

    buffer.writeln('$emoji $title');
    buffer.writeln('');
    buffer.writeln('📌 $trx');

    // التصنيف الرئيسي/الفرعي من الإعدادات
    final catLine = _categoryLine(offer, config);
    if (catLine != null) buffer.writeln(catLine);

    if (offer.prc > 0) {
      buffer.writeln('💰 السعر: ${_fmtPrice(offer.prc)} $cur');
    }

    final city = offer.loc['city']?.toString().trim() ?? '';
    if (city.isNotEmpty) buffer.writeln('📍 المنطقة: $city');
    final d = offer.loc['d']?.toString().trim() ?? '';
    if (d.isNotEmpty) buffer.writeln('📍 الموقع: $d');

    // المواصفات حسب النوع (بدون لوحة/سند — بيانات حساسة لا تنشر)
    final specsLine = isProperty ? _propertySpecsLine(offer) : _carSpecsLine(offer);
    if (specsLine != null) buffer.writeln(specsLine);

    if (offer.descript.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln(offer.descript);
    }

    // التواصل — حصراً واتساب المكتب (رقم من الإعدادات، قابل للتغيير من التطبيق)
    buffer.writeln('');
    final wa = (config?.videoRequestWhatsApp ?? '').trim();
    buffer.writeln('📱 التواصل والمعاينة حصراً عبر واتساب المكتب العقاري الإلكتروني:');
    if (wa.isNotEmpty) buffer.writeln(wa);

    // 📲 رابط تحميل التطبيق — يُدرج فقط إذا ضُبط من الإعدادات (فارغ الآن بانتظار نشر المتجر)
    final appLink = (config?.appDownloadLink ?? '').trim();
    if (appLink.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('📲 لمتابعة كل العروض حمّل تطبيق «عقارات السويداء»:');
      buffer.writeln(appLink);
    }

    // هاشتاغات
    buffer.writeln('');
    buffer.write('#عقارات_السويداء #السويداء ');
    buffer.write(isProperty ? '#عقارات #${offer.trx == 0 ? 'بيع' : 'إيجار'}' : '#سيارات #مركبات');

    return buffer.toString();
  }

  /// سطر التصنيف: «🏷️ التصنيف: سيارة — سياحية» (يحل الاسم من خرائط الإعدادات بأمان)
  String? _categoryLine(OfferModel offer, ConfigModel? config) {
    final cats = offer.typ == 0
        ? (config?.propertyCategories ?? const {})
        : (config?.vehicleCategories ?? const {});
    final entry = cats[offer.cat.toString()];
    var main = '';
    if (entry is Map) {
      main = (entry['nm'] ?? '').toString();
    } else if (entry != null) {
      main = entry.toString();
    }
    var sub = offer.specs['custom_sub']?.toString().trim() ?? '';
    if (sub.isEmpty && entry is Map && entry['sub'] is List) {
      final subs = entry['sub'] as List;
      if (offer.sub >= 0 && offer.sub < subs.length) sub = subs[offer.sub].toString();
    }
    if (main.isEmpty && sub.isEmpty) return null;
    final joined = [main, sub].where((e) => e.isNotEmpty).join(' — ');
    return '🏷️ التصنيف: $joined';
  }

  /// سطر مواصفات السيارة (بدون اللوحة — بيانات توثيق لا تنشر)
  String? _carSpecsLine(OfferModel offer) {
    final s = offer.specs;
    String g(String k) => s[k]?.toString().trim() ?? '';
    final parts = <String>[
      if (g('brand').isNotEmpty) 'ماركة ${g('brand')}',
      if (g('model').isNotEmpty) 'موديل ${g('model')}',
      if (g('year').isNotEmpty) 'سنة ${g('year')}',
      if (g('color').isNotEmpty) 'اللون ${g('color')}',
      if (g('fuel').isNotEmpty) 'وقود ${g('fuel')}',
      if (g('transmission').isNotEmpty) 'ناقل ${g('transmission')}',
    ];
    if (parts.isEmpty) return null;
    return '🔧 المواصفات: ${parts.join(' • ')}';
  }

  /// سطر مواصفات العقار (بدون الملاحظات القانونية — بيانات حساسة لا تنشر)
  String? _propertySpecsLine(OfferModel offer) {
    final s = offer.specs;
    String g(String k) => s[k]?.toString().trim() ?? '';
    final parts = <String>[
      if (g('area').isNotEmpty) 'مساحة ${g('area')} م²',
      if (g('finishing').isNotEmpty) 'إكساء ${g('finishing')}',
      if (g('floor').isNotEmpty) 'طابق ${g('floor')}',
      if (g('direction').isNotEmpty) 'اتجاه ${g('direction')}',
    ];
    if (parts.isEmpty) return null;
    return '📐 المواصفات: ${parts.join(' • ')}';
  }

  String _fmtPrice(double p) {
    final s = p.toStringAsFixed(0);
    // إضافة فواصل آلاف
    final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(re, (m) => ',');
  }

  /// تعليم العرض بأنه جاهز/منشور على السوشال (soc_pub) + حفظ النص
  /// يُستخدم للمشاركة اليدوية من قبل المستخدم
  Future<bool> markSocialPublished(String offerId, String text,
      {String? userId}) async {
    try {
      if (userId == null || userId.isEmpty) return false;
      // ✅ Via user-offers Edge (mark_social_published action)
      final res = await _sb.invokeFunction('user-offers', body: {
        'action': 'mark_social_published',
        'user_uid': userId,
        'offer_id': offerId,
        'text': text,
      });
      return res.data?['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════
  // مساعد: كشف التكرار قبل النشر (RPC check_offer_duplicate)
  // ═══════════════════════════════════════
  Future<bool> isDuplicateOffer({
    required String title,
    required double price,
    required Map<String, dynamic> loc,
    required String uid,
  }) async {
    try {
      // ✅ Via user-offers Edge (check_duplicate action)
      final res = await _sb.invokeFunction('user-offers', body: {
        'action': 'check_duplicate',
        'user_uid': uid,
        'title': title,
        'price': price,
        'loc': loc,
      });
      return res.data?['is_duplicate'] == true;
    } catch (e) {return false;
    }
  }

  // ═══════════════════════════════════════
  // 4.7 إدارة إحصائيات المستخدم (Stats)
  // ═══════════════════════════════════════

  /// تحديث إحصائيات المستخدم (off, req, app, dl)
  Future<void> updateUserStat(String uid, String statKey) async {
    try {
      // جلب القيمة الحالية
      final row = await _sb.client.from(DbTables.users).select('stats').eq('id', uid).single();
      Map<String, dynamic> stats = Map<String, dynamic>.from(row['stats'] ?? {});
      
      // زيادة العداد بمقدار 1
      final currentVal = (stats[statKey] ?? 0) as int;
      stats[statKey] = currentVal + 1;

      await _sb.client.from(DbTables.users).update({
        'stats': stats,
        'ts_upd': DateTime.now().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  // ═══════════════════════════════════════
  // 4.8 هوية المكتب (Office Identity)
  // مرجع: docs/LOGIC_SPEC.md — القسم الأول
  // ═══════════════════════════════════════

  /// تحويل بيانات المستخدم إلى تسمية مهنية تُعرض للعامة.
  /// تُخفي اسم المالك الحقيقي لحماية الخصوصية وتعزيز هوية "المكتب".
  ///
  /// قواعد التسمية (محدّثة 2026-06-16):
  /// - إدارة/موظف (Role >= 4)         → "إدارة المكتب العقاري الالكتروني"
  /// - وسيط + موثق رسمياً (vrf=2)      → "وسيط معتمد ✓"
  /// - وسيط + غير موثق                → "وسيط شريك"
  /// - مستخدم + موثق رسمياً            → "عميل موثق ✓"
  /// - مستخدم + رتبة ≥ خبير            → "عميل مميز ⭐"
  /// - مستخدم عادي                     → "عميل"
  String getUserPublicLabel(UserModel user) {
    if (user.isInternal) {
      return 'إدارة المكتب العقاري الالكتروني';
    }

    final isBroker = user.isBroker;
    final isOfficial = user.isVerifiedOfficial;
    final badge = user.bg;

    String label;
    if (isBroker) {
      label = isOfficial ? 'وسيط معتمد ✓' : 'وسيط شريك';
    } else {
      if (isOfficial) {
        label = 'عميل موثق ✓';
      } else if (badge >= 3) {
        label = 'خبير عقارات ⭐'; // تم تحديث التسمية لتناسب المنطق الجديد
      } else if (badge >= 2) {
        label = 'عميل موثوق 🤝';
      } else if (badge >= 1) {
        label = 'عميل نشط 📈';
      } else {
        label = 'عميل 🔰';
      }
    }

    return 'منشور بواسطة المكتب العقاري الالكتروني • $label';
  }

  /// تسمية داخلية للموظفين (للإدارة فقط)
  /// تظهر من هو الموظف الذي قام بالنشر فعلياً.
  String getStaffInternalLabel(UserModel user) {
    return '${user.nm} (${user.roleName})';
  }

  // ═══════════════════════════════════════
  // 4.9 نظام المطابقة المتقدم (Match Score)
  // ═══════════════════════════════════════

  /// يحسب نسبة التطابق بين الطلب والعرض
  /// يرجع:
  /// - score: النسبة العامة (0-100)
  /// - breakdown: تفصيل النسب لكل عامل
  /// - details: نص توضيحي للعرض
  Map<String, dynamic> calculateMatchScore({
    required Map<String, dynamic> request,
    required OfferModel offer,
  }) {
    int totalScore = 0;
    final Map<String, int> breakdown = {};

    // 1. نوع العنصر (25%)
    final int? reqTyp = request['typ'] as int?;
    if (reqTyp != null && reqTyp == offer.typ) {
      totalScore += 25;
      breakdown['type'] = 25;
    } else {
      totalScore += 12;
    }

    // 2. نوع المعاملة (20%)
    final int? reqTrx = request['trx'] as int?;
    if (reqTrx != null && reqTrx == offer.trx) {
      totalScore += 20;
      breakdown['transaction'] = 20;
    } else {
      totalScore += 10;
    }

    // 3. السعر (±35%) (30%)
    final double? reqPrice = (request['price'] as num?)?.toDouble();
    if (reqPrice != null && reqPrice > 0) {
      final double diff = (offer.prc - reqPrice).abs() / reqPrice;
      if (diff <= 0.35) {
        final int priceScore = (30 * (1 - diff)).round();
        totalScore += priceScore;
        breakdown['price'] = priceScore;
      }
    } else {
      totalScore += 15;
    }

    // 4. المنطقة (15%)
    final String? reqCity = request['city']?.toString().toLowerCase();
    final String? offerCity = offer.loc['city']?.toString().toLowerCase();
    if (reqCity != null && offerCity != null && reqCity == offerCity) {
      totalScore += 15;
      breakdown['location'] = 15;
    } else if (reqCity == null) {
      totalScore += 8;
    }

    // 5. نقاط إضافية (10%)
    if (offer.imgs.isNotEmpty) totalScore += 5;
    if (offer.descript.length > 20) totalScore += 5;

    final int finalScore = totalScore.clamp(0, 100);

    return {
      'score': finalScore,
      'breakdown': breakdown,
      'details': _buildScoreDetails(breakdown),
    };
  }

  String _buildScoreDetails(Map<String, int> breakdown) {
    if (breakdown.isEmpty) return 'لا يوجد تطابق كافٍ';
    final parts = breakdown.entries.map((e) => '${e.key}: ${e.value}%').toList();
    return parts.join(' • ');
  }
}
