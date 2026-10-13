import 'package:package_info_plus/package_info_plus.dart';

/// 📦 معلومات النسخة الحقيقية — تُقرأ من حزمة التطبيق نفسها وقت التشغيل.
///
/// **لماذا لا نكتبها نصاً ولا نجعلها قابلة للتعديل من الإدارة؟**
/// كانت النافذة «عن التطبيق» تعرض `1.0.0` كنص حرفي في موضعين، بينما
/// `AppConstants.appVersion` يقول `1.0.0+2` — رقم **وهمي** منفصل عن الواقع،
/// وأي رفعة لجوجل بلاي كانت ستترك الشاشة تكذب على المستخدم.
///
/// وجعلها قابلة للتعديل من لوحة الإدارة أسوأ: يستطيع المدير كتابة `2.5.0`
/// بينما الـAPK المثبَّت فعلياً `1.0.0` ⇒ تقارير أعطال مضلِّلة يستحيل تتبّعها.
///
/// الحل: `package_info_plus` يقرأ `versionName` و`versionCode` من الـAPK
/// المثبَّت. المصدر الوحيد هو `pubspec.yaml` ← `build.gradle.kts` ← الـAPK،
/// فيستحيل أن يكذب الرقم ويتحدّث تلقائياً مع كل رفعة.
///
/// 📋 سياسة Google Play:
///   • `versionName` (مثل `1.0.0`) — يراه المستخدم، نص حر بلا قيود.
///   • `versionCode` (مثل `10`) — عدد صحيح **يجب أن يزيد مع كل رفعة**؛
///     لا يتكرر ولا يتراجع (رقم مستهلَك = رفض فوري)، وحدُّه `2100000000`.
///   • لا يُعرض `versionCode` للمستخدم عادةً — نعرضه بخط صغير لأنه يفيد
///     الدعم الفني في تحديد البناء بالضبط عند تشخيص عطل.
class AppInfoService {
  AppInfoService._();

  static PackageInfo? _cached;

  /// تُستدعى مرة واحدة عند الإقلاع. آمنة للاستدعاء المتكرر.
  ///
  /// ⚠️ §13 No-Silent-Probes: لا نبتلع الخطأ صامتين هنا؛ نتركه فارغاً
  /// **ونعلن ذلك بالواجهة** («الإصدار غير متاح») بدل عرض رقم مخترَع.
  static Future<void> init() async {
    if (_cached != null) return;
    _cached = await PackageInfo.fromPlatform();
  }

  /// هل تمّت التهيئة بنجاح؟ الواجهة تخفي بند الإصدار عندما تكون false.
  static bool get isReady => _cached != null;

  /// اسم الإصدار كما يراه المستخدم بالمتجر — مثل `1.0.0`. فارغ إن لم يُهيَّأ.
  static String get version => _cached?.version ?? '';

  /// رقم البناء (`versionCode`) — مثل `10`. فارغ إن لم يُهيَّأ.
  static String get buildNumber => _cached?.buildNumber ?? '';

  /// اسم الحزمة — `com.hadyalbnnai.jaramanarealestate`. يفيد الدعم الفني.
  static String get packageName => _cached?.packageName ?? '';

  /// اسم التطبيق كما سجّله نظام التشغيل.
  static String get appName => _cached?.appName ?? '';

  /// النص المعروض للمستخدم: `1.0.0` فقط.
  /// 🩹 (2026-08-20): رقم البناء الداخلي `versionCode` (مثل 10) لم يعد يُعرض —
  /// قرار المالك. يبقى متاحاً للدعم الفني عبر `buildNumber`.
  static String get displayVersion {
    if (_cached == null) return '';
    final v = version.trim();
    if (v.isEmpty) return '';
    return v;
  }
}
