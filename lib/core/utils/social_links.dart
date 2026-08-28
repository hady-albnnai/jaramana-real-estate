import 'package:flutter/material.dart';

/// 🔗 تعريف شبكة تواصل واحدة معروفة.
class SocialNetwork {
  /// المفتاح المخزَّن في `app_config → txts.socialPages`. لاتيني حصراً.
  final String key;

  /// الاسم العربي المعروض للمستخدم.
  final String label;

  /// الأيقونة المعروضة.
  final IconData icon;

  /// مثال يوضع في حقل الإدارة.
  final String hint;

  const SocialNetwork({
    required this.key,
    required this.label,
    required this.icon,
    required this.hint,
  });
}

/// 🌐 الشبكات الاجتماعية — مصدر واحد للحقيقة تستخدمه الواجهتان معاً.
///
/// **المشكلة التي حُلّت (2026-08-14):** كانت الصفحات الإضافية تُدخَل بحقلين
/// نصيين حرَّين (اسم + رابط)، فينتج:
///   1. كل الصفحات تظهر بأيقونة `Icons.link` رمادية واحدة — تيك توك وتلغرام
///      وواتساب بلا تمييز بصري.
///   2. الاسم يظهر كما كتبه المدير — `tiktok` بالإنكليزية وسط واجهة عربية.
///   3. خطأ إملائي واحد (`tik tok` بدل `tiktok`) يكسر أي معالجة لاحقة.
///
/// الآن: المدير يختار من قائمة منسدلة، والمفتاح والأيقونة والاسم العربي
/// كلها تُشتق تلقائياً. الخيار `other` يبقى متاحاً للشبكات غير المدرجة.
class SocialLinks {
  SocialLinks._();

  /// الشبكات المدعومة رسمياً. الترتيب هنا هو ترتيب العرض بالنافذة.
  static const List<SocialNetwork> known = [
    SocialNetwork(
      key: 'facebook',
      label: 'فيسبوك',
      icon: Icons.facebook,
      hint: 'https://facebook.com/YourPage',
    ),
    // 2026-08-28: صفحة فيسبوك ثانية للمكتب — تُخزَّن في txts.socialPages.facebook2
    // وتُعرض بأيقونة فيسبوك واسم عربي بدل أيقونة رابط رمادية ومفتاح خام.
    SocialNetwork(
      key: 'facebook2',
      label: 'فيسبوك — صفحة ثانية',
      icon: Icons.facebook,
      hint: 'https://facebook.com/YourSecondPage',
    ),
    SocialNetwork(
      key: 'instagram',
      label: 'إنستغرام',
      icon: Icons.camera_alt_outlined,
      hint: 'https://instagram.com/YourPage',
    ),
    SocialNetwork(
      key: 'whatsapp',
      label: 'واتساب',
      icon: Icons.chat_bubble_outline,
      hint: 'https://wa.me/963xxxxxxxxx',
    ),
    SocialNetwork(
      key: 'telegram',
      label: 'تلغرام',
      icon: Icons.send_outlined,
      hint: 'https://t.me/YourChannel',
    ),
    SocialNetwork(
      key: 'tiktok',
      label: 'تيك توك',
      icon: Icons.music_note_outlined,
      hint: 'https://tiktok.com/@YourAccount',
    ),
    SocialNetwork(
      key: 'youtube',
      label: 'يوتيوب',
      icon: Icons.play_circle_outline,
      hint: 'https://youtube.com/@YourChannel',
    ),
    SocialNetwork(
      key: 'x',
      label: 'إكس (تويتر)',
      icon: Icons.alternate_email,
      hint: 'https://x.com/YourAccount',
    ),
    SocialNetwork(
      key: 'snapchat',
      label: 'سناب شات',
      icon: Icons.photo_camera_outlined,
      hint: 'https://snapchat.com/add/YourAccount',
    ),
    SocialNetwork(
      key: 'linkedin',
      label: 'لينكد إن',
      icon: Icons.work_outline,
      hint: 'https://linkedin.com/company/YourPage',
    ),
    SocialNetwork(
      key: 'website',
      label: 'الموقع الإلكتروني',
      icon: Icons.language,
      hint: 'https://example.com',
    ),
  ];

  /// بحث عن شبكة بمفتاحها. يقبل اختلاف حالة الأحرف والمسافات.
  static SocialNetwork? byKey(String rawKey) {
    final k = normalizeKey(rawKey);
    for (final n in known) {
      if (n.key == k) return n;
    }
    return null;
  }

  /// توحيد المفتاح: أحرف صغيرة، بلا مسافات، والمرادفات الشائعة تُطبَّع.
  static String normalizeKey(String raw) {
    var k = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    // مرادفات يكتبها المديرون كثيراً
    const synonyms = <String, String>{
      'twitter': 'x',
      'fb': 'facebook',
      'fb2': 'facebook2',
      'insta': 'instagram',
      'ig': 'instagram',
      'wa': 'whatsapp',
      'yt': 'youtube',
      'site': 'website',
      'web': 'website',
      'snap': 'snapchat',
    };
    k = synonyms[k] ?? k;
    return k;
  }

  /// الاسم العربي المعروض. الشبكات غير المعروفة تُعرض بمفتاحها كما هو.
  static String labelFor(String rawKey) =>
      byKey(rawKey)?.label ?? rawKey.trim();

  /// الأيقونة المناسبة. الشبكات غير المعروفة تأخذ أيقونة رابط عامة.
  static IconData iconFor(String rawKey) =>
      byKey(rawKey)?.icon ?? Icons.link;

  /// ✅ التحقق من الرابط قبل العرض أو الحفظ.
  ///
  /// **قاعدة أمنية:** `https://` حصراً. رفض `http://` (غير مشفَّر) وكل
  /// المخططات الخطرة مثل `javascript:` و`data:` و`file:` — لأن الرابط يُمرَّر
  /// إلى `launchUrl` ويفتحه المستخدم بثقة أنه صفحة المكتب الرسمية.
  ///
  /// كان مسار `txts` هو **القسم الوحيد** في `admin-config` بلا أي تحقُّق،
  /// فكان أي مدير (دور ≥ 5) يستطيع زرع رابط تصيّد داخل «تابعنا على».
  static bool isValidUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    if (s.length > 500) return false;
    if (!s.startsWith('https://')) return false;
    final uri = Uri.tryParse(s);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.host.trim().isEmpty) return false;
    // منع المسافات والمحارف المسيطِرة داخل الرابط
    if (RegExp(r'[\s\u0000-\u001F\u007F]').hasMatch(s)) return false;
    return true;
  }

  /// رسالة الخطأ العربية لحقل رابط غير صالح — تُستخدم في `validator`.
  /// تُرجع `null` عندما يكون الرابط صالحاً أو فارغاً (الفارغ يعني «غير مفعَّل»).
  static String? validateOptionalUrl(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null; // فارغ = البند مخفي، وهذا مسموح
    if (!s.startsWith('https://')) {
      return 'الرابط يجب أن يبدأ بـ https:// حصراً';
    }
    if (!isValidUrl(s)) return 'رابط غير صالح';
    return null;
  }

  /// ✅ التحقق من رقم هاتف سوري للعرض والاتصال.
  /// يقبل `09xxxxxxxx` و`+9639xxxxxxxx` و`9639xxxxxxxx`.
  static bool isValidPhone(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (s.isEmpty) return false;
    return RegExp(r'^(0\d{9}|\+?963\d{9})$').hasMatch(s);
  }

  /// رسالة خطأ عربية لحقل هاتف اختياري.
  static String? validateOptionalPhone(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null; // فارغ = البند مخفي
    if (!isValidPhone(s)) {
      return 'رقم غير صالح — مثال: 0933123456 أو +963933123456';
    }
    return null;
  }

  /// تحويل رقم محلي إلى صيغة wa.me الدولية بلا رمز `+`.
  /// `0958750199` ⇒ `963958750199`. يُرجع نصاً فارغاً إن كان الرقم غير صالح.
  static String toWhatsAppNumber(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[\s()+-]'), '');
    if (s.isEmpty) return '';
    if (s.startsWith('00963')) s = s.substring(2);
    if (s.startsWith('0')) s = '963${s.substring(1)}';
    if (!s.startsWith('963')) s = '963$s';
    return RegExp(r'^963\d{9}$').hasMatch(s) ? s : '';
  }
}
