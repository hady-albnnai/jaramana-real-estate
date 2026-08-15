/// قواعد موحدة للتحقق من مدخلات المستخدم في الواجهة.
///
/// ملاحظة: هذه القواعد لتحسين تجربة المستخدم فقط. الحماية الحقيقية يجب أن
/// تبقى في السيرفر/RPCs أيضاً.
class InputValidators {
  const InputValidators._();

  static const int nameMin = 2;
  static const int nameMax = 60;
  static const int usernameMin = 3;
  static const int usernameMax = 30;
  static const int passwordMin = 8;
  static const int titleMax = 120;
  static const int descriptionMax = 2000;
  static const int notesMax = 1000;
  static const int reasonMax = 500;

  static String normalizeSpaces(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String cleanText(String value, {int maxLength = 1000}) {
    final cleaned = normalizeSpaces(value)
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
  }

  static String? validateName(String? value) {
    final v = normalizeSpaces(value ?? '');
    if (v.length < nameMin) return 'الاسم قصير جداً';
    if (v.length > nameMax) return 'الاسم طويل جداً';
    if (RegExp(r'[<>]').hasMatch(v)) return 'الاسم يحتوي رموزاً غير مسموحة';
    return null;
  }

  static String normalizeDigits(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
    const latin = '01234567890123456789';
    var result = input;
    for (int i = 0; i < arabic.length; i++) {
      result = result.replaceAll(arabic[i], latin[i % 10]);
    }
    return result;
  }

  static String? validateUsername(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v.length < usernameMin || v.length > usernameMax) {
      return 'اسم المستخدم يجب أن يكون بين 3 و 30 حرفاً';
    }
    if (!RegExp(r'^([a-z0-9_.]+|[\u0600-\u06FF0-9_.]+)$').hasMatch(v)) {
      return 'يسمح فقط بالأحرف العربية أو اللاتينية (دون خلط) والأرقام و _ و .';
    }
    return null;
  }

  static String? validateRequiredUsername(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'اسم المستخدم مطلوب';
    return validateUsername(v);
  }

  static String? validatePassword(String? value) {
    final v = value ?? '';
    if (v.length < passwordMin) return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
    if (v.length > 128) return 'كلمة المرور طويلة جداً';
    return null;
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// 📞 PHONE-001 (2026-08-15) — المصدر الوحيد لتطبيع الهاتف السوري
  /// ═══════════════════════════════════════════════════════════════════
  /// بلاغ المالك: «في طلب تصوير عقاري ما زال رقم الهاتف الافتراضي يحوي
  /// +963 وهذا يمنع استكمال الطلب — يقول: يرجى إدخال هاتف سوري صحيح».
  ///
  /// السبب الجذري: قاعدة البيانات تخزّن الهاتف بالصيغة الدولية
  /// (`+963988888888` — مؤكَّد حياً)، بينما التحقق في الشاشات يطلب
  /// `^09[3-9]\d{7}$` المحلية ⇒ تعبئة الحقل من `user.ph` مباشرةً تُنتج
  /// قيمة **مرفوضة دائماً** ومشوّهة بصرياً في حقل RTL.
  ///
  /// وكانت دالة التطبيع **مكرّرة في 5 ملفات** بنسخ متطابقة، وبعض الشاشات
  /// لا تستدعيها إطلاقاً ⇒ العطل يظهر في بعضها دون بعض. هذه هي النسخة
  /// الوحيدة المعتمدة، وكل الشاشات تستخدمها.
  ///
  /// أمثلة: `+963988888888` → `0988888888` · `963988888888` → `0988888888`
  ///        `0988888888` → كما هي · `988888888` → `0988888888`
  static String toLocalSyrianPhone(String? phone) {
    var cleaned = normalizeDigits(phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return '';
    // 00963… (صيغة الاتصال الدولي) ثم 963… (بعد إزالة +)
    if (cleaned.startsWith('00963')) cleaned = cleaned.substring(5);
    if (cleaned.startsWith('963')) cleaned = cleaned.substring(3);
    if (!cleaned.startsWith('0')) cleaned = '0$cleaned';
    return cleaned;
  }

  /// هل الرقم سوري محمول صالح بعد التطبيع؟ (المرجع الوحيد للفحص)
  static bool isValidSyrianMobile(String? phone) =>
      RegExp(r'^09[3-9]\d{7}$').hasMatch(toLocalSyrianPhone(phone));

  static String? validateSyrianPhone(String? value) {
    final v = normalizeDigits(value ?? '').trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (v.isEmpty) return 'رقم الهاتف مطلوب';
    final local = RegExp(r'^09\d{8}$').hasMatch(v);
    final intl = RegExp(r'^\+9639\d{8}$').hasMatch(v) || RegExp(r'^9639\d{8}$').hasMatch(v);
    if (!local && !intl) return 'رقم الهاتف غير صالح';
    return null;
  }

  static String? validateTitle(String? value) {
    final v = cleanText(value ?? '', maxLength: titleMax + 1);
    if (v.isEmpty) return 'العنوان مطلوب';
    if (v.length > titleMax) return 'العنوان طويل جداً';
    return null;
  }

  static String? validateDescription(String? value) {
    final v = cleanText(value ?? '', maxLength: descriptionMax + 1);
    if (v.length > descriptionMax) return 'الوصف طويل جداً';
    return null;
  }

  static String? validateNotes(String? value) {
    final v = cleanText(value ?? '', maxLength: notesMax + 1);
    if (v.length > notesMax) return 'الملاحظات طويلة جداً';
    return null;
  }

  static String? validatePositivePrice(num? value) {
    if (value == null || value <= 0) return 'السعر غير صالح';
    if (value > 999999999999) return 'السعر أكبر من الحد المسموح';
    return null;
  }
}
