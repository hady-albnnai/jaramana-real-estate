import 'dart:convert';

class ConfigModel {
  final Map<String, dynamic> data;
  final DateTime? loadedAt;

  ConfigModel({required this.data, this.loadedAt});

  factory ConfigModel.fromJson(Map<String, dynamic> json) {
    return ConfigModel(data: json, loadedAt: DateTime.now());
  }

  int get signupPoints => _getNested('pts.sgn', 1000);
  int get weeklyLoginPoints => _getNested('pts.wkL', 100);
  int get addOfferPoints => _getNested('pts.addO', 500);
  int get dealDonePoints => _getNested('pts.dlD', 2000);
  int get socialSharePoints => _getNested('pts.soc', 100);
  int get sellCommission => _getNested('com.sl', 3);
  Map<String, dynamic> get userQuotas => _getNestedMap('qta.u', {'o': 1, 'r': 3, 'a': 3});
  Map<String, dynamic> get brokerQuotas => _getNestedMap('qta.b', {'o': 5, 'r': 5, 'a': 3});
  Map<String, dynamic> get propertyCategories => _getNestedMap('catProp', {});
  Map<String, dynamic> get vehicleCategories => _getNestedMap('catVeh', {});
  Map<String, dynamic> get documentTypes => _getNestedMap('docTp', {});
  Map<String, dynamic> get carDocumentTypes => _getNestedMap('carDocTp', {});
  Map<String, dynamic> get plateTypes => _getNestedMap('plateTp', {});
  List<dynamic> get locations => _getNestedList('locs', []);
  List<dynamic> get brands => _getNestedList('brnds', []);
  List<dynamic> get colors => _getNestedList('clrs', []);
  List<dynamic> get reportReasons => _getNestedList('rptRsn', []);
  Map<String, dynamic> get badges => _getNestedMap('bdg', {});
  Map<String, dynamic> get packages => _getNestedMap('pkg', {});

  /// عدد أيام السماح بعد انتهاء الباقة — يُقرأ من pkg.grace_days (افتراضي: 3)
  int get pkgGraceDays {
    final pkgMap = packages;
    final val = pkgMap['grace_days'];
    if (val is num) return val.toInt();
    return 3; // fallback آمن
  }

  Map<String, dynamic> get texts => _getNestedMap('txts', {});
  int get usdToSypRate => _getNested('fx.usd_syp', 15000);

  /// رقم واتساب المحادثة الخاصة بطلبات الفيديو (الأساسي - يدخله المدير أو نائبه)
  String get videoRequestWhatsApp => _getNested('txts.videoRequestWhatsApp', '');
  /// رابط تحميل التطبيق — يُدرج أسفل منشورات السوشيال عند تعبئته من الإعدادات (فارغ بانتظار نشر المتجر)
  String get appDownloadLink => _getNested('txts.appDownloadLink', '');

  /// رابط مجموعة الواتساب الاحتياطي (في حال حظر الرقم الخاص)
  String get videoRequestGroupLink => _getNested('txts.videoRequestGroupLink', '');

  /// إعدادات حجز المواعيد (appt) — تُقرأ من app_config
  /// any_from/any_to: دوام المعاينة عندما يكون العرض "جاهز بأي وقت" (avl = any)
  /// gap_mins: الفارق الأدنى بين موعدين على نفس العرض/المشرف (قاعدة الساعة)
  Map<String, dynamic> get appointmentSettings => _getNestedMap('appt', {});

  String get apptAnyFrom {
    final v = appointmentSettings['any_from'];
    return (v is String && v.isNotEmpty) ? v : '09:00';
  }

  String get apptAnyTo {
    final v = appointmentSettings['any_to'];
    return (v is String && v.isNotEmpty) ? v : '21:00';
  }

  int get apptGapMins {
    final v = appointmentSettings['gap_mins'];
    if (v is num) return v.toInt();
    return 60;
  }

  /// قنوات الدفع اليدوية (المرحلة 11)
  /// المفاتيح: haram | sham_cash | balance | bank
  /// كل قناة تحوي: enabled, name, icon, instructions + حقول خاصة بها
  Map<String, dynamic> get payChannels => _getNestedMap('payChannels', {});

  /// قائمة القنوات المفعّلة فقط (للعرض في شاشة الدفع)
  List<MapEntry<String, Map<String, dynamic>>> get enabledPayChannels {
    final all = payChannels;
    final result = <MapEntry<String, Map<String, dynamic>>>[];
    all.forEach((key, value) {
      if (value is Map && value['enabled'] == true) {
        result.add(MapEntry(key, Map<String, dynamic>.from(value)));
      }
    });
    return result;
  }

  // ── صفحات التواصل الاجتماعي (قابلة للتوسعة) ──
  /// رابط صفحة فيسبوك الرسمية (قابل للتعديل من الإدارة)
  String get facebookPage => _getNested('txts.facebook', '');

  /// رابط حساب إنستغرام الرسمي (قابل للتعديل من الإدارة)
  String get instagramPage => _getNested('txts.instagram', '');

  /// صفحات تواصل إضافية (تكتوك، تويتر، إلخ) — map قابل للتوسعة
  /// مثال: { "tiktok": "https://tiktok.com/@sweeda", "linkedin": "..." }
  Map<String, dynamic> get socialPages => _getNestedMap('txts.socialPages', {});

  // ── 📞 أرقام التواصل (2026-08-14) ──
  // كانت تُسمّى developerPhone/developerPhone2 وتحمل رقمين حقيقيين **مطبوخين
  // بالكود كقيمة افتراضية**. عيبان: (1) التسمية خاطئة — المستخدم يفهم أنها
  // أرقام شركة البرمجة لا أرقام تواصل المكتب؛ (2) تفريغ الحقل من الإدارة كان
  // لا يُخفي الرقم لأن الافتراضي غير فارغ ⇒ رقم شخصي يظهر رغم حذفه.
  // القاعدة الآن: **كل الافتراضيات نصوص فارغة** — أي بند فارغ يختفي كلياً،
  // ومصدر القيم الوحيد هو app_config. (قرار المالك: «ما بدي شي افتراضي»)

  /// رقم التواصل الأول — فارغ يخفيه من «عن التطبيق»
  String get contactPhone1 => _getNested('txts.contactPhone1', '');

  /// رقم التواصل الثاني — فارغ يخفيه من «عن التطبيق»
  String get contactPhone2 => _getNested('txts.contactPhone2', '');

  /// رقم واتساب التواصل — فارغ يخفي زر «راسلنا واتساب»
  String get contactWhatsApp => _getNested('txts.contactWhatsApp', '');

  /// فقرة «من نحن» — تُحرَّر من الإدارة بلا إعادة بناء
  String get aboutUsText => _getNested('txts.aboutUs', '');

  /// وصف التطبيق المختصر أسفل النافذة
  String get appDescriptionText => _getNested('txts.appDescription', '');

  /// رابط سياسة الخصوصية (شرط نشر في Google Play)
  String get privacyPolicyUrl => _getNested('txts.privacyPolicyUrl', '');

  /// رابط شروط الاستخدام
  String get termsUrl => _getNested('txts.termsUrl', '');

  /// أساس رابط الإحالة — فارغ ⇒ يُعرض الكود وحده بلا رابط مكسور.
  /// كان `https://sweeda-realestate.com/invite?code=` مطبوخاً بالكود، وهو نطاق
  /// **غير موجود** ⇒ كل رابط دعوة يُشارَك ينتهي بخطأ 404.
  String get referralBaseUrl => _getNested('txts.referralBaseUrl', '');

  /// أسعار «الإعلان المميز» المدفوع بالأسبوع (ل.س) — قابلة للتعديل من السيرفر (fmsp)
  Map<String, dynamic> get featuredAdPrices => _getNestedMap(
      'fmsp', {'w1': 500, 'w2': 950, 'w3': 1350, 'w4': 1800}); // العملة الجديدة (حذف صفرين)

  // ── ⚖️ أسعار الاستشارة القانونية (legalPrice) — أُضيفت 2026-08-14 ──
  // كانت 500/2000 مضمّنة نصاً في 11 موضعاً بالواجهة و3 بالإيدج (مخالفة لقاعدة
  // «لا نصوص ثابتة» بالدستور)، وسبق أن أنتج ذلك تضارباً بين الشاشات
  // (كومِت «تصحيح سعر الاستشارة في الرئيسية من 50,000 إلى 500»).
  Map<String, dynamic> get legalPrices => _getNestedMap(
      'legalPrice', {'phone': 500, 'onsite': 2000, 'renew': 500, 'durationMins': 15});

  /// سعر الاستشارة الهاتفية (ل.س)
  int get legalPhonePrice => _asInt(legalPrices['phone'], 500);

  /// سعر الجلسة الحضورية (ل.س)
  int get legalOnsitePrice => _asInt(legalPrices['onsite'], 2000);

  /// سعر تجديد المحادثة لمدة إضافية (ل.س)
  int get legalRenewPrice => _asInt(legalPrices['renew'], 500);

  /// مدة المحادثة الواحدة بالدقائق
  int get legalDurationMins => _asInt(legalPrices['durationMins'], 15);

  /// سعر الاستشارة حسب نوع الخدمة (0 = هاتفية، 1 = حضورية)
  int legalPriceFor(int serviceType) =>
      serviceType == 1 ? legalOnsitePrice : legalPhonePrice;

  int _asInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// 📸 أجر خدمة التصوير العقاري (ل.س) — قابل للتعديل من الإدارة (photoPrice).
  /// 0 يعني الخدمة مجانية فيُخفى ذكر الأجر من شاشة المستخدم.
  int get photographyPrice => _getNested('photoPrice', 1000);

  /// إعدادات النشر الحقيقي على Meta. التوكنات لا تحفظ هنا؛ تبقى Edge Secrets.
  /// افتراضي true منذ 2026-07-13 — النشر التلقائي بعد الموافقة مباشرة.
  Map<String, dynamic> get socialPublishing =>
      _getNestedMap('socialPublishing', {'autoPublish': true});

  /// عند true تحاول Edge Function النشر مباشرة بعد قبول العرض.
  bool get socialAutoPublish => socialPublishing['autoPublish'] != false;

  T _getNested<T>(String path, T defaultValue) {
    dynamic value = data;
    for (final key in path.split('.')) {
      if (value is Map && value.containsKey(key)) {
        value = value[key];
      } else {
        return defaultValue;
      }
    }
    if (defaultValue is int && value is num) return value.toInt() as T;
    return value is T ? value : defaultValue;
  }

  Map<String, dynamic> _getNestedMap(String path, Map<String, dynamic> defaultValue) {
    dynamic value = data;
    for (final key in path.split('.')) {
      if (value is Map && value.containsKey(key)) {
        value = value[key];
      } else {
        return defaultValue;
      }
    }
    return (value is Map) ? Map<String, dynamic>.from(value) : defaultValue;
  }

  List<dynamic> _getNestedList(String path, List<dynamic> defaultValue) {
    dynamic value = data;
    for (final key in path.split('.')) {
      if (value is Map && value.containsKey(key)) {
        value = value[key];
      } else {
        return defaultValue;
      }
    }
    return (value is List) ? value : defaultValue;
  }

  String toJson() => jsonEncode(data);
}
