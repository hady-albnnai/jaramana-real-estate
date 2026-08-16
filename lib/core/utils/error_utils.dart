import 'package:flutter/foundation.dart';
/// أدوات موحّدة لتطبيع أخطاء السيرفر والـ Edge Functions بدون طباعة في الكود النهائي.
class ErrorUtils {
  const ErrorUtils._();

  static String normalize(Object? error) {
    if (error == null) return 'UNKNOWN_ERROR';

    final raw = error.toString();
    if (raw.isEmpty) return 'UNKNOWN_ERROR';

    final knownCodes = <String>[
      'ADMIN_SESSION_REQUIRED',
      'INVALID_ADMIN_SESSION',
      'SESSION_TOKEN_REQUIRED',
      'INVALID_SESSION',
      'UNAUTHORIZED',
      'NOT_AUTHORIZED',
      'AUTH_MISMATCH',
      'AUTH_TOKEN_REQUIRED',
      'AUTH_TOKEN_INVALID',
      'UNAUTHORIZED_ACCESS',
      'EMAIL_ALREADY_LINKED_TO_DIFFERENT_AUTH_USER',
      'PHONE_ALREADY_EXISTS',
      'USER_NOT_FOUND',
      'USER_NOT_FOUND_OR_INACTIVE',
      'USER_INACTIVE',
      'CANNOT_MODIFY_MANAGER',
      'CANNOT_DELETE_MANAGER',
      'ONLY_MANAGER_CAN_MANAGE_DEPUTIES',
      'ONLY_MANAGER_CAN_CREATE_DEPUTY',
      'INVALID_ROLE',
      'INVALID_STATUS',
      'PHONE_EXISTS',
      'PHONE_REQUIRED',
      'USERNAME_TAKEN',
      'USERNAME_LENGTH',
      'USERNAME_INVALID_CHARS',
      'PASSWORD_TOO_SHORT',
      'WRONG_PASSWORD',
      'NO_PASSWORD_SET',
      'USER_BANNED',
      'USER_FROZEN',
      'EMPTY_RESPONSE',
      'METHOD_NOT_ALLOWED',
      'META_SECRETS_NOT_CONFIGURED',
      'OFFER_NOT_APPROVED',
      'SOCIAL_PUBLISH_NOT_ENABLED',
      'PUBLIC_IMAGE_REQUIRED',
      'PUBLISH_IN_PROGRESS',
      'PARTIAL_OR_TOTAL_FAILURE',
    ];

    for (final code in knownCodes) {
      if (raw.contains(code)) return code;
    }

    // ═══════════════════════════════════════════════════════════════════
    // 🩹 APPT-001 (2026-08-16) — أخطاء قاعدة البيانات الخام (PostgrestException)
    // ═══════════════════════════════════════════════════════════════════
    // بلاغ المالك: ظهر بالسجل نص إنجليزي كامل
    // PostgrestException(message: {"code":"22P02", ... invalid input syntax for
    // type uuid: ""}, code: 400 ...) — وهذا نص خام لا يُعرض للمستخدم أبداً (§19).
    // الحل: انتزاع رمز SQLSTATE (5 محارف) وتحويله لرمز داخلي مترجَم.
    final pg = RegExp(r'"code"\s*:\s*"([0-9A-Za-z]{5})"').firstMatch(raw);
    if (pg != null) {
      final sqlState = pg.group(1)!.toUpperCase();
      final mapped = _pgState[sqlState];
      if (mapped != null) return mapped;
      return 'DB_ERROR';
    }
    if (raw.contains('PostgrestException') ||
        raw.contains('AuthException') ||
        raw.contains('FunctionException') ||
        raw.contains('SocketException') ||
        raw.contains('ClientException') ||
        raw.contains('TimeoutException')) {
      if (raw.contains('SocketException') ||
          raw.contains('ClientException') ||
          raw.contains('Failed host lookup')) {
        return 'NETWORK_ERROR';
      }
      if (raw.contains('TimeoutException')) return 'TIMEOUT';
      return 'DB_ERROR';
    }

    // لا نُعيد نصاً خاماً قد يكون إنجليزياً: أي محتوى لاتيني صرف يُعمَّم.
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(raw);
    if (!hasArabic && RegExp(r'[a-z]').hasMatch(raw)) {
      // رموز الأخطاء الاصطلاحية (SNAKE_CASE) تُترك ليلتقطها القاموس
      final looksLikeCode = RegExp(r'^[A-Z0-9_]+$').hasMatch(raw.trim());
      if (!looksLikeCode) return 'UNKNOWN_ERROR';
    }

    return raw.length > 220 ? raw.substring(0, 220) : raw;
  }

  /// 🩹 APPT-001: خريطة رموز SQLSTATE ← رموز داخلية مترجَمة بالقاموس أدناه.
  static const Map<String, String> _pgState = {
    '22P02': 'DB_INVALID_INPUT',   // invalid input syntax (مثل uuid فارغ)
    '23502': 'DB_MISSING_FIELD',   // not null violation
    '23503': 'DB_LINK_MISSING',    // foreign key violation
    '23505': 'DB_DUPLICATE',       // unique violation
    '23514': 'DB_CHECK_FAILED',    // check violation
    '42501': 'DB_NO_PERMISSION',   // insufficient privilege / RLS
    '42703': 'DB_ERROR',           // undefined column
    '42883': 'DB_ERROR',           // undefined function
    '40001': 'DB_BUSY',            // serialization failure
    '55P03': 'DB_BUSY',            // lock not available
    '57014': 'TIMEOUT',            // query canceled
    'PGRST': 'DB_ERROR',
  };


  /// ═══════════════════════════════════════════════════════════════════
  /// 🗣️ I18N-ERR-001 (2026-08-15) — قاموس شامل لرموز أخطاء السيرفر
  /// ═══════════════════════════════════════════════════════════════════
  /// بلاغ المالك: «رسالة خطأ بالإنجليزي تظهر رمز الخطأ واسمه، وهذا ممنوع
  /// ومحظور بكل التطبيق».
  ///
  /// الفحص كشف أن السيرفر يُصدر **318 رمزاً** والمترجَم منها 39 فقط،
  /// و`default` كان يُعيد الرمز الخام ⇒ 279 رمزاً تظهر إنجليزية للمستخدم.
  ///
  /// هذا القاموس يغطيها كلها، وكل رسالة تجيب: **ماذا حدث؟** و**ماذا أفعل؟**
  static const Map<String, String> _ar = {
    // ── 🩹 APPT-001: أخطاء قاعدة البيانات والشبكة (خط الدفاع الأخير) ──
    'DB_ERROR': 'حدث خلل أثناء الاتصال بالخادم — أعد المحاولة بعد قليل.',
    'DB_INVALID_INPUT': 'إحدى البيانات المُرسلة غير صالحة — أعد فتح الشاشة وحاول مجدداً.',
    'DB_MISSING_FIELD': 'هناك حقل مطلوب لم يُملأ — راجع البيانات وأعد الإرسال.',
    'DB_LINK_MISSING': 'العنصر المرتبط بهذه العملية لم يعد موجوداً — حدّث القائمة.',
    'DB_DUPLICATE': 'هذه البيانات مسجّلة مسبقاً.',
    'DB_CHECK_FAILED': 'القيمة المُدخلة خارج النطاق المسموح.',
    'DB_NO_PERMISSION': 'ليست لديك صلاحية لتنفيذ هذه العملية.',
    'DB_BUSY': 'الخادم مشغول حالياً — أعد المحاولة بعد لحظات.',
    'NETWORK_ERROR': 'تعذّر الاتصال بالإنترنت — تحقق من الشبكة وأعد المحاولة.',
    'TIMEOUT': 'استغرقت العملية وقتاً طويلاً — أعد المحاولة.',

    // ── الجلسة والصلاحيات ──
    'AUTH_REQUIRED': 'يجب تسجيل الدخول أولاً.',
    'AUTH_FAILED': 'تعذّر التحقق من هويتك — سجّل الدخول من جديد.',
    'AUTH_UID_MISMATCH': 'انتهت جلستك — سجّل الدخول من جديد.',
    'AUTH_UID_EMAIL_CONFLICT': 'هذا البريد مرتبط بحساب آخر.',
    'INVALID_AUTH_TOKEN': 'انتهت جلستك — سجّل الدخول من جديد.',
    'STAFF_SESSION_REQUIRED': 'انتهت جلسة العمل — سجّل الدخول من جديد.',
    'SESSION_FAILED': 'تعذّر إنشاء الجلسة — حاول مرة أخرى.',
    'SESSION_VALIDATION_FAILED': 'انتهت جلستك — سجّل الدخول من جديد.',
    'FORBIDDEN': 'ليست لديك صلاحية لهذه العملية.',
    'FORBIDDEN_TARGET_ROLE': 'لا يمكنك تنفيذ هذه العملية على هذا المستخدم.',
    'ADMIN_REQUIRED': 'هذه العملية للإدارة فقط.',
    'ADMIN_ONLY_EVENT': 'هذه العملية للإدارة فقط.',
    'ADMIN_NOT_FOUND_OR_INACTIVE': 'حساب الإدارة غير نشط.',
    'ROLE_NOT_ADMINISTRATIVE': 'هذه العملية تتطلب صلاحية إدارية.',
    'LAWYER_ROLE_REQUIRED': 'هذه العملية للمحامين فقط.',
    'EXPEDITER_ROLE_REQUIRED': 'هذه العملية للمعقّبين فقط.',
    'SELF_ACTION': 'لا يمكنك تنفيذ هذه العملية على نفسك.',
    'CANNOT_MODIFY_SELF': 'لا يمكنك تعديل حسابك بهذه الطريقة.',
    'STAFF_CANNOT_SELF_DELETE': 'لا يمكن لموظف حذف حسابه — راجع الإدارة.',
    'ONLY_MANAGER_CAN_RESTORE': 'الاستعادة للمدير الرئيسي فقط.',
    'ONLY_MANAGER_CAN_REVERSE': 'عكس الدفعة للمدير الرئيسي فقط.',
    'NOT_OWNER': 'هذا العنصر ليس ملكك.',
    'NOT_OFFER_OWNER': 'هذا العرض ليس ملكك.',
    'NOT_PARTICIPANT': 'لست طرفاً في هذه المحادثة.',
    'NOT_YOUR_APPOINTMENT': 'هذا الموعد ليس لك.',
    'NOT_YOUR_TASK': 'هذه المهمة غير مُسندة إليك.',
    'NOT_ASSIGNED_LAWYER': 'هذه الاستشارة مُسندة لمحامٍ آخر.',
    'UNAUTHORIZED_FOLDER': 'لا صلاحية للوصول لهذا الملف.',
    'SECURITY': 'العملية مرفوضة لأسباب أمنية.',
    'FRAUD_DETECTED': 'تعذّر التنفيذ — لا يمكن استخدام نفس الجهاز أو الشبكة.',
    'RATE_LIMIT': 'تجاوزت الحد المسموح — حاول بعد قليل.',
    'TOO_MANY_ATTEMPTS': 'محاولات كثيرة — انتظر قليلاً ثم أعد المحاولة.',
    'OTP_LOCKED': 'أُقفل الإرسال مؤقتاً بسبب المحاولات المتكررة.',

    // ── الحساب والملف الشخصي ──
    'NAME_REQUIRED': 'الاسم مطلوب.',
    'EMAIL_REQUIRED': 'البريد الإلكتروني مطلوب.',
    'EMAIL_INVALID': 'البريد الإلكتروني غير صالح.',
    'PHONE_INVALID': 'رقم الهاتف غير صالح (09xxxxxxxx).',
    'INVALID_PHONE': 'رقم الهاتف غير صالح (09xxxxxxxx).',
    'CONTACT_PHONE_REQUIRED': 'رقم هاتف التواصل مطلوب.',
    'WHATSAPP_REQUIRED': 'رقم واتساب مطلوب.',
    'ADDRESS_REQUIRED': 'العنوان مطلوب.',
    'SID_REQUIRED': 'الرقم الوطني مطلوب.',
    'SID_TOO_LONG': 'الرقم الوطني طويل جداً.',
    'USERNAME_REQUIRED': 'اسم المستخدم مطلوب.',
    'USERNAME_EXISTS': 'اسم المستخدم محجوز — اختر غيره.',
    'PASSWORDS_REQUIRED': 'أدخل كلمة المرور.',
    'PASSWORD_TOO_LONG': 'كلمة المرور طويلة جداً.',
    'NEW_PASSWORD_REQUIRED': 'أدخل كلمة المرور الجديدة.',
    'WRONG_OLD_PASSWORD': 'كلمة المرور الحالية غير صحيحة.',
    'CREDENTIALS_REQUIRED': 'أدخل بيانات الدخول.',
    'MISSING_CREDENTIALS': 'أدخل بيانات الدخول.',
    'INVALID_OR_EXPIRED_OTP': 'رمز التحقق غير صحيح أو انتهت صلاحيته.',
    'INVALID_CODE_FORMAT': 'صيغة الرمز غير صحيحة.',
    'OTP_GENERATION_FAILED': 'تعذّر إرسال رمز التحقق — حاول مرة أخرى.',
    'OTP_GATEWAY_NOT_CONFIGURED': 'خدمة الرسائل غير متاحة حالياً — راسل المكتب.',
    'WHATSAPP_SEND_FAILED': 'تعذّر الإرسال عبر واتساب — حاول مرة أخرى.',
    'GOOGLE_AUTH_FAILED': 'تعذّر الدخول عبر Google.',
    'EMAIL_AUTH_FAILED': 'تعذّر الدخول عبر البريد.',
    'PSEUDO_EMAIL_NOT_ALLOWED': 'هذا البريد غير مسموح.',
    'IDENTITY_NOT_VERIFIED': 'يجب توثيق حسابك أولاً.',
    'FULL_IDENTITY_REQUIRED': 'أكمل بيانات هويتك أولاً.',
    'ALREADY_VERIFIED': 'حسابك موثَّق بالفعل.',
    'VERIFICATION_NOT_PENDING': 'لا يوجد طلب توثيق قيد المراجعة.',
    'MISSING_DOCUMENTS': 'المستندات المطلوبة ناقصة.',
    'ID_IMAGE_TOO_LARGE': 'صورة الهوية كبيرة جداً — اختر صورة أصغر.',
    'BUSINESS_NAME_REQUIRED': 'اسم النشاط التجاري مطلوب.',

    // ── العروض ──
    'OFFER_NOT_FOUND': 'العرض غير موجود.',
    'OFFER_NOT_FOUND_OR_NOT_ALLOWED': 'العرض غير موجود أو لا صلاحية لك عليه.',
    'OFFER_NOT_FOUND_OR_NOT_OWNED': 'العرض غير موجود أو ليس ملكك.',
    'OFFER_NOT_AVAILABLE': 'العرض غير متاح حالياً.',
    'OFFER_ALREADY_PUBLISHED': 'العرض منشور بالفعل.',
    'OFFER_IMAGE_REQUIRED': 'يجب إضافة صورة واحدة على الأقل للعرض.',
    'IMAGES_REQUIRED': 'الصور مطلوبة.',
    'IMAGE_TOO_LARGE': 'الصورة كبيرة جداً — اختر صورة أصغر.',
    'EMPTY_IMAGE': 'الصورة فارغة أو تالفة.',
    'INVALID_IMAGE_DATA': 'ملف الصورة غير صالح.',
    'MEDIA_REQUIRED': 'يجب إرفاق وسائط.',
    'NO_MEDIA': 'لا توجد وسائط مرفقة.',
    'INVALID_MEDIA_ARRAY': 'قائمة الوسائط غير صالحة.',
    'NO_FILES': 'لم تختر أي ملف.',
    'OFFER_LOCKED': 'العرض مقفل حالياً ولا يمكن تعديله.',
    'OFFER_UPDATE_FAILED': 'تعذّر تحديث العرض — حاول مرة أخرى.',
    'OFFER_HAS_PENDING_COMPLETION': 'هذا العرض عليه طلب إتمام قيد المراجعة.',
    'DUPLICATE_OFFER': 'لديك عرض مطابق منشور بالفعل.',
    'QUOTA_EXCEEDED': 'بلغت الحد الأقصى لعدد عروضك — رقِّ باقتك أو احذف عرضاً.',
    'TITLE_REQUIRED': 'العنوان مطلوب.',
    'PRICE_REQUIRED': 'السعر مطلوب.',
    'PRICE_TOO_LARGE': 'السعر كبير جداً.',
    'INVALID_PRICE': 'السعر غير صالح.',
    'REJECTION_REASON_REQUIRED': 'سبب الرفض مطلوب.',
    'INVALID_REJECT_REASON': 'سبب الرفض غير صالح.',
    'INVALID_PRIORITY_TYPE': 'نوع الأولوية غير صالح.',
    'ALREADY_EXTENDED': 'تم استخدام التمديد المجاني مسبقاً.',
    'TOO_EARLY': 'الوقت مبكر على هذه العملية.',

    // ── المواعيد ──
    'APPOINTMENT_NOT_FOUND': 'الموعد غير موجود.',
    'APPOINTMENT_NOT_FOUND_OR_NOT_ALLOWED': 'الموعد غير موجود أو لا صلاحية لك عليه.',
    'APPOINTMENT_ID_REQUIRED': 'معرّف الموعد مطلوب.',
    'APPOINTMENT_FINALIZED': 'هذا الموعد منتهٍ ولا يمكن تعديله.',
    'DUPLICATE_APPOINTMENT': 'لديك موعد مسجَّل على هذا العرض.',
    'CANNOT_BOOK_OWN_OFFER': 'لا يمكنك حجز موعد على عرضك.',
    'DATE_TIME_REQUIRED': 'اختر التاريخ والوقت.',
    'DATE_MUST_BE_FUTURE': 'اختر تاريخاً مستقبلياً.',
    'NEW_DATE_REQUIRED': 'اختر التاريخ الجديد.',
    'PROPOSED_DT_REQUIRED': 'اقترح موعداً بديلاً.',
    'INVALID_APPOINTMENT_TIME': 'وقت الموعد غير صالح.',
    'INVALID_APPT_ACTION': 'إجراء غير صالح على الموعد.',
    'INVALID_APPT_TRANSITION': 'لا يمكن نقل الموعد لهذه الحالة.',
    'TIME_CONFLICT_ON_OFFER': 'هذا الوقت محجوز على العرض — اختر وقتاً آخر.',
    'TIME_NOT_IN_AVAILABLE_SLOTS': 'الوقت خارج أوقات التوفّر المتاحة.',
    'DAY_NOT_AVAILABLE': 'هذا اليوم غير متاح.',
    'NO_AVAILABILITY': 'لا توجد أوقات متاحة حالياً.',
    'SLOT_NO_LONGER_AVAILABLE': 'حُجز هذا الموعد للتو — اختر موعداً بديلاً.',
    'SLOT_REQUIRED_FOR_ONSITE': 'اختر موعد الجلسة أولاً.',
    'CANCEL_REASON_REQUIRED': 'سبب الإلغاء مطلوب.',
    'DECLINE_REASON_REQUIRED': 'سبب الاعتذار مطلوب.',
    'USER_CAN_ONLY_CANCEL_PENDING': 'لا يمكن إلغاء موعد مؤكَّد — راسل المكتب.',
    'NO_SUPERVISOR_AVAILABLE': 'لا يوجد مشرف متاح حالياً — حاول لاحقاً.',
    'SCHEDULE_IN_THE_PAST': 'لا يمكن الجدولة في وقت مضى.',
    'INVALID_SCHEDULE_DATE': 'تاريخ الجدولة غير صالح.',

    // ── الاستشارات القانونية ──
    'CONSULTATION_NOT_FOUND': 'الاستشارة غير موجودة.',
    'CONSULTATION_ID_REQUIRED': 'معرّف الاستشارة مطلوب.',
    'CONSULTATION_NOT_CONFIRMED': 'لم يؤكّد المحامي الاستشارة بعد.',
    'CONSULTATION_NOT_COMPLETED': 'الاستشارة لم تنتهِ بعد.',
    'CONSULTATION_NOT_CONVERTIBLE': 'لا يمكن تحويل هذه الاستشارة.',
    'CONSULTATION_AND_LAWYER_REQUIRED': 'بيانات الاستشارة أو المحامي ناقصة.',
    'OPEN_CONSULTATION_EXISTS': 'لديك استشارة قائمة من هذا النوع — أكملها أو انتظر إغلاقها.',
    'PENDING_CONSULTATION_PAYMENT_EXISTS': 'لديك دفعة قيد المراجعة لهذا النوع — لا حاجة للدفع مرة أخرى.',
    'PENDING_RENEWAL_PAYMENT_EXISTS': 'لديك دفعة تجديد قيد المراجعة.',
    'CONSULTATION_PAYMENT_REQUIRED': 'يجب اعتماد دفعة الاستشارة أولاً قبل إرسال الطلب.',
    'CONSULTATION_V2_NOT_ENABLED': 'المسار الجديد غير مفعّل بعد.',
    'CONSULTATION_INTENT_ID_REQUIRED': 'بيانات طلب الاستشارة ناقصة.',
    'CONSULTATION_INTENT_NOT_FOUND': 'طلب الاستشارة غير موجود أو انتهت صلاحيته.',
    'CONSULTATION_INTENT_NOT_PAYABLE': 'لا يمكن إنشاء دفعة لهذا الطلب في حالته الحالية.',
    'CONSULTATION_INTENT_NOT_RESCHEDULABLE': 'لا يمكن تغيير موعد هذا الطلب في حالته الحالية.',
    'INVALID_CONSULTATION_FLOW': 'مسار الاستشارة غير صالح.',
    'IDEMPOTENCY_KEY_REQUIRED': 'تعذّر تجهيز العملية بأمان — أعد فتح الشاشة.',
    'SLOT_HOLD_EXPIRED': 'انتهت مهلة حجز الموعد — اختر موعداً جديداً دون تكرار بياناتك.',
    'RESERVATION_MISMATCH': 'بيانات حجز الموعد غير متطابقة — اختر الموعد مجدداً.',
    'ASSIGNED_LAWYER_UNAVAILABLE': 'المحامي غير متاح حالياً — اختر الانتظار أو محامياً آخر.',
    'NO_READY_CHAT_SESSION': 'لا توجد مدة محادثة جاهزة للبدء.',
    'CHAT_NOT_READY': 'المحادثة ليست جاهزة للانضمام بعد.',
    'CHAT_SESSION_CREATE_FAILED': 'تعذّر تجهيز جلسة المحادثة — لم يُعتمد الطلب، أعد المحاولة.',
    'RENEWAL_PAYMENT_REQUIRED': 'يجب إنشاء دفعة تجديد وانتظار اعتمادها أولاً.',
    'CONSULTATION_CONCURRENTLY_UPDATED': 'تغيّرت حالة الاستشارة للتو — حدّث الشاشة.',
    'CHAT_ALREADY_STARTED': 'المحادثة مفتوحة بالفعل.',
    'CHAT_CLOSED': 'المحادثة مغلقة حالياً.',
    'CHAT_TIME_EXPIRED': 'انتهى وقت المحادثة — يمكنك طلب تجديد للمتابعة.',
    'CHAT_TIME_NOT_FINISHED': 'لا يمكن إنهاء الاستشارة قبل انتهاء وقتها.',
    'CHAT_RATE_LIMIT': 'أرسلت رسائل كثيرة خلال وقت قصير — انتظر دقيقة.',
    'CLIENT_MESSAGE_ID_REQUIRED': 'تعذّر تجهيز الرسالة — أعد فتح المحادثة.',
    'MESSAGE_TOO_LONG': 'الرسالة طويلة جداً — اختصرها ثم أعد الإرسال.',
    'FILE_NAME_TOO_LONG': 'اسم الملف طويل جداً.',
    'INVALID_VOICE_DURATION': 'مدة الرسالة الصوتية غير صالحة.',
    'INVALID_AUDIO_DURATION': 'التسجيل الصوتي أطول من المدة المسموحة أو تالف.',
    'AUDIO_DURATION_MISMATCH': 'تعذّر التحقق من مدة التسجيل الصوتي.',
    'EXTENSION_WINDOW_EXPIRED': 'انتهت مهلة التمديد المجاني لهذه الاستشارة.',
    'REPORT_ALREADY_OPEN': 'يوجد بلاغ مفتوح لهذه الاستشارة بالفعل.',
    'REPORT_DETAILS_INVALID': 'اكتب تفاصيل واضحة للمشكلة بين 10 و1000 حرف.',
    'CHAT_NOT_STARTED': 'لم تبدأ المحادثة بعد.',
    'ONSITE_HAS_NO_CHAT': 'الجلسة الحضورية موعد في المكتب — بلا محادثة.',
    'NO_LAWYER_ASSIGNED': 'لم يُسنَد محامٍ بعد.',
    'NO_ACTIVE_LAWYERS': 'لا يوجد محامٍ متاح حالياً — حاول لاحقاً.',
    'LAWYER_PICK_FAILED': 'تعذّر اختيار المحامي وتحميل مواعيده — أعد المحاولة.',
    'SLOTS_LOAD_FAILED': 'تعذّر تحميل المواعيد المتاحة — أعد المحاولة.',
    'TARGET_NOT_LAWYER': 'المستخدم المحدد ليس محامياً.',
    'ALREADY_CONVERTED': 'سبق تحويل هذه الاستشارة.',
    'ALREADY_ONSITE': 'الاستشارة حضورية بالفعل.',
    'NOT_AWAITING_INFO': 'لا يوجد طلب استكمال بيانات.',
    'SUBJECT_REQUIRED': 'اكتب موضوع الاستشارة.',
    'SUBJECT_TOO_SHORT': 'موضوع الاستشارة قصير جداً.',
    'CONTENT_REQUIRED': 'اكتب نص الرسالة.',
    'ATTACHMENT_TOO_LARGE': 'المرفق كبير جداً.',
    'INVALID_SERVICE_TYPE': 'نوع الخدمة غير صالح.',
    'INVALID_DURATION_MINS': 'مدة الاستشارة غير صالحة.',
    'INVALID_LEGAL_PRICE': 'سعر الاستشارة غير صالح.',
    'INVALID_REASON_CODE': 'سبب الرفض غير صالح.',
    'REASON_REQUIRED': 'السبب مطلوب.',
    'REASON_NOTE_REQUIRED': 'اكتب تفاصيل السبب.',
    'AVL_OBJECT_REQUIRED': 'حدّد أوقات التوفّر.',
    'INVALID_WORKING_DAYS': 'أيام العمل غير صالحة.',

    // ── المدفوعات والباقات ──
    'PAYMENT_NOT_FOUND': 'الدفعة غير موجودة.',
    'PAYMENT_ID_REQUIRED': 'معرّف الدفعة مطلوب.',
    'PAYMENT_DATA_REQUIRED': 'بيانات الدفعة ناقصة.',
    'PAYMENT_NOT_APPROVED': 'الدفعة لم تُعتمد بعد.',
    'PAYMENT_NOT_PENDING_OR_NOT_FOUND': 'الدفعة غير معلّقة أو غير موجودة.',
    'PENDING_PAYMENT_EXISTS': 'لديك طلب قيد المعالجة — انتظر بتّ الإدارة فيه.',
    'ACTIVE_PACKAGE_EXISTS': 'لديك باقة فعّالة بالفعل.',
    'MISSING_PAYMENT_PROOF_OR_REFERENCE': 'أرفق إثبات الدفع ورقم العملية.',
    'AMOUNT_MISMATCH': 'المبلغ لا يطابق السعر المعلن — أعد فتح الصفحة.',
    'PACKAGE_PRICE_NOT_FOUND': 'سعر الباقة غير مضبوط — راسل المكتب.',
    'FEATURED_PRICE_NOT_FOUND': 'سعر الإعلان المميّز غير مضبوط — راسل المكتب.',
    'FX_RATE_NOT_CONFIGURED': 'سعر الصرف غير مضبوط — راسل المكتب.',
    'INVALID_CONFIGURED_PRICE': 'السعر المضبوط غير صالح — راسل المكتب.',
    'INVALID_PHOTO_PRICE': 'سعر التصوير غير صالح.',
    'UNSUPPORTED_PAYMENT_TYPE': 'نوع الدفع غير مدعوم.',
    'INVALID_CHANNEL': 'قناة الدفع غير صالحة.',
    'CHANNEL_NOT_ALLOWED': 'قناة الدفع غير مفعّلة.',
    'INVALID_FEATURED_AD_META': 'بيانات الإعلان المميّز ناقصة.',
    'REVERSAL_REASON_REQUIRED': 'سبب عكس الدفعة مطلوب.',
    'INSUFFICIENT_POINTS': 'نقاطك غير كافية.',
    'POINTS_INVALID': 'قيمة النقاط غير صالحة.',
    'WEEKLY_BONUS_NOT_DUE': 'مكافأة الأسبوع غير مستحقة بعد.',
    'EVENT_NOT_ALLOWED': 'هذا الإجراء غير مسموح.',
    'EVENT_TYPE_REQUIRED': 'نوع الحدث مطلوب.',

    // ── الطلبات والصفقات والمهام ──
    'REQUEST_NOT_FOUND': 'الطلب غير موجود.',
    'REQUEST_ID_REQUIRED': 'معرّف الطلب مطلوب.',
    'REQUEST_DATA_REQUIRED': 'بيانات الطلب ناقصة.',
    'INVALID_REQUEST_DATA': 'بيانات الطلب غير صالحة.',
    'REQUEST_ALREADY_PROCESSED': 'سبق البتّ في هذا الطلب.',
    'REQUEST_NOT_FOUND_OR_NOT_ACTIVE': 'الطلب غير موجود أو غير نشط.',
    'REQUEST_NOT_FOUND_OR_NOT_ALLOWED': 'الطلب غير موجود أو لا صلاحية لك عليه.',
    'REQUEST_NOT_FOUND_OR_NOT_CANCELLABLE': 'لا يمكن إلغاء هذا الطلب.',
    'REQUEST_NOT_FOUND_OR_NOT_CLOSABLE': 'لا يمكن إغلاق هذا الطلب.',
    'REQUEST_NOT_FOUND_OR_NOT_EDITABLE': 'لا يمكن تعديل هذا الطلب.',
    'REQUEST_NOT_RENEWABLE': 'لا يمكن تجديد هذا الطلب الآن.',
    'REQUEST_OFFER_MISMATCH': 'الطلب لا يطابق العرض.',
    'DUPLICATE_REQUEST': 'لديك طلب مطابق بالفعل.',
    'INVALID_REQUEST_CLOSE_STATUS': 'حالة الإغلاق غير صالحة.',
    'DEAL_NOT_FOUND': 'الصفقة غير موجودة.',
    'DEAL_ID_REQUIRED': 'معرّف الصفقة مطلوب.',
    'DEAL_DATA_REQUIRED': 'بيانات الصفقة ناقصة.',
    'DEAL_NOT_CREATED': 'تعذّر إنشاء الصفقة.',
    'DEAL_ALREADY_COMPLETED': 'الصفقة مكتملة بالفعل.',
    'DEAL_PRICE_TOO_LARGE': 'قيمة الصفقة كبيرة جداً.',
    'INVALID_DEAL_PRICE': 'قيمة الصفقة غير صالحة.',
    'INVALID_COMMISSION_PCT': 'نسبة العمولة غير صالحة.',
    'INVALID_COMMISSION_VALUE': 'قيمة العمولة غير صالحة.',
    'MUST_CONFIRM_BEFORE_COMPLETE': 'يجب التأكيد قبل الإتمام.',
    'TASK_NOT_FOUND': 'المهمة غير موجودة.',
    'TASK_ID_REQUIRED': 'معرّف المهمة مطلوب.',
    'TASK_NOT_FOUND_OR_NOT_ALLOWED': 'المهمة غير موجودة أو لا صلاحية لك عليها.',
    'TASK_ALREADY_PROCESSED': 'سبق تنفيذ هذه المهمة.',
    'TASK_NOT_ASSIGNABLE': 'لا يمكن إسناد هذه المهمة.',
    'TASK_NOT_PENDING': 'المهمة ليست قيد الانتظار.',
    'TASK_AND_OFFER_REQUIRED': 'المهمة والعرض مطلوبان.',
    'TASK_ID_AND_ITEM_KEY_REQUIRED': 'بيانات البند ناقصة.',
    'DUPLICATE_TASK_EXISTS': 'توجد مهمة مطابقة بالفعل.',
    'INVALID_ITEM_TYPE': 'نوع البند غير صالح.',
    'INVALID_OUTCOME': 'النتيجة غير صالحة.',
    'INVALID_DECISION': 'القرار غير صالح.',
    'INVALID_TRANSITION': 'لا يمكن الانتقال لهذه الحالة.',
    'NOT_PENDING': 'العنصر ليس قيد الانتظار.',
    'ONLY_PENDING_CAN_BE_REJECTED': 'يمكن رفض الطلبات المعلّقة فقط.',
    'CONFIRMATION_REQUIRED': 'التأكيد مطلوب.',
    'ACTIVE_PHOTOGRAPHY_REQUEST_EXISTS': 'لديك طلب تصوير قيد التنفيذ.',
    'PHOTOGRAPHER_NOT_FOUND': 'المصوّر غير موجود.',
    'PHOTOGRAPHER_TIME_CONFLICT': 'المصوّر مرتبط بموعد آخر في هذا الوقت.',
    'USER_NOT_A_PHOTOGRAPHER': 'المستخدم المحدد ليس مصوّراً.',
    'EXPEDITER_UID_REQUIRED': 'اختر المعقّب.',

    // ── التقييمات والتبليغات ──
    'ALREADY_RATED': 'قيّمت هذا الطرف مسبقاً.',
    'CANNOT_RATE_SELF': 'لا يمكنك تقييم نفسك.',
    'INVALID_RATING': 'التقييم غير صالح.',
    'INVALID_STARS': 'اختر عدد النجوم من 1 إلى 5.',
    'CANNOT_REPORT_OWN': 'لا يمكنك التبليغ عن عرضك.',
    'DUPLICATE_OPEN_REPORT': 'لديك تبليغ مفتوح على هذا العنصر.',
    'REPORT_NOT_FOUND': 'التبليغ غير موجود.',
    'REPORT_ID_REQUIRED': 'معرّف التبليغ مطلوب.',
    'REPORT_DATA_REQUIRED': 'بيانات التبليغ ناقصة.',
    'INVALID_REPORT_REASON': 'سبب التبليغ غير صالح.',
    'INVALID_TARGET_TYPE': 'نوع العنصر غير صالح.',

    // ── عام وتقني ──
    'MISSING_FIELDS': 'بعض الحقول المطلوبة ناقصة.',
    'MISSING_REQUIRED_FIELDS': 'بعض الحقول المطلوبة ناقصة.',
    'MISSING_CLIENT_DATA': 'بيانات العميل ناقصة.',
    'MISSING_USER_UID': 'بيانات المستخدم ناقصة.',
    'USER_UID_REQUIRED': 'بيانات المستخدم ناقصة.',
    'TARGET_UID_REQUIRED': 'حدّد المستخدم المستهدف.',
    'TARGET_USER_REQUIRED': 'حدّد المستخدم المستهدف.',
    'TARGET_NOT_FOUND': 'المستخدم غير موجود.',
    'TARGET_USER_NOT_FOUND_OR_INACTIVE': 'المستخدم غير موجود أو غير نشط.',
    'TARGET_NOT_STAFF': 'المستخدم المحدد ليس من الطاقم.',
    'USER_NOT_ACTIVE_OR_NOT_FOUND': 'حسابك غير نشط — راجع المكتب.',
    'BLOCKED_UID_REQUIRED': 'حدّد المستخدم المراد حظره.',
    'OFFER_ID_REQUIRED': 'معرّف العرض مطلوب.',
    'OFFER_DATA_REQUIRED': 'بيانات العرض ناقصة.',
    'OFFER_ID_AND_DATE_REQUIRED': 'العرض والتاريخ مطلوبان.',
    'USER_ID_AND_OFFER_REQUIRED': 'المستخدم والعرض مطلوبان.',
    'DEVICE_ID_REQUIRED': 'معرّف الجهاز مطلوب.',
    'DEVICE_TOKEN_REQUIRED': 'رمز الجهاز مطلوب.',
    'DEVICE_TOKEN_INVALID': 'رمز الجهاز غير صالح.',
    'NOTIFICATION_ID_REQUIRED': 'معرّف الإشعار مطلوب.',
    'NOTIFICATION_NOT_FOUND_OR_NOT_ALLOWED': 'الإشعار غير موجود.',
    'NTF_SETTINGS_REQUIRED': 'إعدادات الإشعارات مطلوبة.',
    'INVALID_NOTIFICATION_SETTINGS': 'إعدادات الإشعارات غير صالحة.',
    'AT_LEAST_ONE_CHANNEL_REQUIRED': 'فعّل قناة إشعارات واحدة على الأقل.',
    'PUSH_SECRET_NOT_CONFIGURED': 'خدمة الإشعارات غير مضبوطة — راسل المكتب.',
    'FETCH_TOKENS_FAILED': 'تعذّر جلب بيانات الإشعارات.',
    'PATH_REQUIRED': 'مسار الملف مطلوب.',
    'NO_SIGNED_URL': 'تعذّر إنشاء رابط الملف.',
    'PAYLOAD_REQUIRED': 'البيانات المرسلة ناقصة.',
    'INVALID_ACTION': 'إجراء غير معروف.',
    'UNKNOWN_ACTION': 'إجراء غير معروف.',
    'INVALID_PERMISSION': 'صلاحية غير صالحة.',
    'INVALID_PERMISSIONS': 'الصلاحيات غير صالحة.',
    'INVALID_SOCIAL_PLATFORM': 'المنصة غير مدعومة.',
    'PLATFORM_INVALID': 'المنصة غير مدعومة.',
    'TOO_MANY_SOCIAL_PAGES': 'عدد الصفحات تجاوز الحد.',
    'SOCIAL_PAGES_MUST_BE_OBJECT': 'صيغة صفحات التواصل غير صحيحة.',
    'HISTORY_ENTRY_NOT_FOUND': 'السجل غير موجود.',
    'HISTORY_ID_REQUIRED': 'معرّف السجل مطلوب.',
    'ALREADY_PENDING': 'الطلب قيد المعالجة بالفعل.',
    'VALIDATION_EXCEPTION': 'البيانات المدخلة غير صالحة.',
    'INTERNAL': 'حدث خطأ في الخادم — حاول مرة أخرى.',
    'UPSERT_FAILED': 'تعذّر الحفظ — حاول مرة أخرى.',
    'UPSERT_EMPTY': 'لا توجد بيانات للحفظ.',
    'NO_VALID_FIELDS': 'لا توجد حقول صالحة للحفظ.',
    'NO_KEYS_PROVIDED': 'لا توجد بيانات للحفظ.',
    'NO_SECTIONS_PROVIDED': 'لا توجد أقسام للحفظ.',
    'SECTIONS_OBJECT_REQUIRED': 'صيغة البيانات غير صحيحة.',
    'SECTION_MUST_BE_OBJECT': 'صيغة القسم غير صحيحة.',
    'SECTION_NOT_ALLOWED': 'هذا القسم غير قابل للتعديل.',
    'KEY_NOT_ALLOWED': 'هذا الحقل غير قابل للتعديل.',
    'TEXTS_OBJECT_REQUIRED': 'صيغة النصوص غير صحيحة.',
    'TEXT_KEY_NOT_ALLOWED': 'هذا النص غير قابل للتعديل.',
    'CHANNEL_MUST_BE_OBJECT': 'صيغة قناة الدفع غير صحيحة.',
    'CHANNEL_FIELD_NOT_ALLOWED': 'هذا الحقل غير قابل للتعديل.',
    'OFFICE_FIELD_NOT_ALLOWED': 'هذا الحقل غير قابل للتعديل.',
    'PROFILE_FIELD_NOT_ALLOWED': 'هذا الحقل غير قابل للتعديل.',
    'LEGAL_FIELD_NOT_ALLOWED': 'هذا الحقل غير قابل للتعديل.',
    'ADMIN_UID_REQUIRED': 'بيانات الإدارة ناقصة.',
    'ADMIN_UID_AND_TOKEN_REQUIRED': 'بيانات جلسة الإدارة ناقصة.',
    'UNKNOWN_ERROR': 'حدث خطأ غير متوقع — حاول مرة أخرى.',
  };

  static String? _lookup(String code) => _ar[code];

  static String arabicMessage(Object? error) {
    final code = normalize(error);
    switch (code) {
      case 'ADMIN_SESSION_REQUIRED':
      case 'INVALID_ADMIN_SESSION':
      case 'SESSION_TOKEN_REQUIRED':
      case 'INVALID_SESSION':
        return 'انتهت جلسة الإدارة أو أنها غير صالحة. سجّل الدخول مجدداً.';
      case 'UNAUTHORIZED':
      case 'NOT_AUTHORIZED':
        return 'ليست لديك صلاحية لتنفيذ هذه العملية.';
      case 'AUTH_MISMATCH':
      case 'AUTH_TOKEN_REQUIRED':
      case 'AUTH_TOKEN_INVALID':
      case 'UNAUTHORIZED_ACCESS':
        return 'جلسة المستخدم غير صالحة أو انتهت. أعد تسجيل الدخول.';
      case 'EMAIL_ALREADY_LINKED_TO_DIFFERENT_AUTH_USER':
        return 'هذا البريد مربوط بحساب آخر. استخدم بريدًا آخر أو سجّل دخولك بالحساب الموجود.';
      case 'USER_NOT_FOUND':
      case 'USER_NOT_FOUND_OR_INACTIVE':
        return 'المستخدم غير موجود أو غير نشط.';
      case 'USER_INACTIVE':
        return 'الحساب غير نشط.';
      case 'CANNOT_MODIFY_MANAGER':
      case 'CANNOT_DELETE_MANAGER':
        return 'لا يمكن تعديل أو حذف المدير الرئيسي.';
      case 'ONLY_MANAGER_CAN_MANAGE_DEPUTIES':
      case 'ONLY_MANAGER_CAN_CREATE_DEPUTY':
        return 'هذه العملية محصورة بالمدير الرئيسي.';
      case 'INVALID_ROLE':
        return 'الدور المحدد غير صالح.';
      case 'INVALID_STATUS':
        return 'حالة الحساب غير صالحة.';
      case 'PHONE_EXISTS':
      case 'PHONE_ALREADY_EXISTS':
        return 'رقم الهاتف مستخدم مسبقاً.';
      case 'PHONE_REQUIRED':
        return 'رقم الهاتف مطلوب.';
      case 'USERNAME_TAKEN':
        return 'اسم المستخدم محجوز.';
      case 'USERNAME_LENGTH':
        return 'اسم المستخدم يجب أن يكون بين 3 و 30 حرفاً.';
      case 'USERNAME_INVALID_CHARS':
        return 'اسم المستخدم يحتوي أحرفاً غير مسموحة.';
      case 'PASSWORD_TOO_SHORT':
        return 'كلمة المرور قصيرة جداً.';
      case 'WRONG_PASSWORD':
        return 'كلمة المرور غير صحيحة.';
      case 'NO_PASSWORD_SET':
        return 'لم يتم تعيين كلمة مرور لهذا الحساب.';
      case 'USER_BANNED':
        return 'الحساب محظور.';
      case 'USER_FROZEN':
        return 'الحساب مجمّد مؤقتاً.';
      case 'EMPTY_RESPONSE':
        return 'لم يصل رد صالح من السيرفر.';
      case 'METHOD_NOT_ALLOWED':
        return 'طريقة الطلب غير مسموحة.';
      case 'META_SECRETS_NOT_CONFIGURED':
        return 'بيانات ربط Meta غير مضبوطة على السيرفر بعد.';
      case 'OFFER_NOT_APPROVED':
        return 'يجب اعتماد العرض ونشره داخل التطبيق أولاً.';
      case 'SOCIAL_PUBLISH_NOT_ENABLED':
        return 'النشر الاجتماعي غير مفعّل لهذا العرض.';
      case 'PUBLIC_IMAGE_REQUIRED':
        return 'يحتاج إنستغرام إلى صورة عامة صالحة واحدة على الأقل.';
      case 'PUBLISH_IN_PROGRESS':
        return 'النشر قيد التنفيذ حالياً؛ انتظر قليلاً ثم حدّث القائمة.';
      case 'PARTIAL_OR_TOTAL_FAILURE':
        return 'تعذر النشر على منصة واحدة أو أكثر؛ أعد المحاولة بأمان.';
      default:
        // 🗣️ I18N-ERR-001: كان يُعيد الرمز الإنجليزي الخام للمستخدم.
        // الآن: القاموس الشامل أولاً، ثم رسالة عربية عامة — ولا يظهر رمز
        // إنجليزي للمستخدم أبداً. الرمز يُسجَّل للتشخيص فقط (§13).
        final mapped = _lookup(code);
        if (mapped != null) return mapped;
        debugPrint('⚠️ [ERR] رمز غير مترجَم: $code');
        return 'تعذّر إتمام العملية — حاول مرة أخرى أو راسل المكتب.';
    }
  }
}
