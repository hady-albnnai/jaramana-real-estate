/// ثوابت التطبيق العامة
class AppConstants {
  /// اسم التطبيق
  static const String appName = 'المكتب العقاري الالكتروني - جرمانا';

  /// ⚠️ BUG-006 (2026-08-14): كانت هنا قيمة نصية `'1.0.0+2'` تُحدَّث يدوياً،
  /// فتنحرف عن `pubspec.yaml` مع أول رفعة. حُذفت لأن مصدر الحقيقة الوحيد صار
  /// `AppInfoService` الذي يقرأ `versionName+versionCode` من الـAPK نفسه.
  ///
  /// استخدم: `AppInfoService.displayVersion` للعرض،
  /// و`AppInfoService.version` / `.buildNumber` للإرسال للسيرفر.
  @Deprecated('استخدم AppInfoService — يقرأ الإصدار الحقيقي من الـAPK')
  static String get appVersion => '';
}
