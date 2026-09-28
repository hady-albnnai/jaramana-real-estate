/// أدوار المستخدم — مرجع: docs/CURRENT_STATUS.md
/// الزائر ليس دوراً في DB — هو حالة بدون تسجيل دخول.
class UserRole {
  static const int user = 0;          // مستخدم عادي
  static const int broker = 1;       // وسيط
  static const int photographer = 2; // مصور — موظف داخلي
  static const int supervisor = 3;   // مشرف — موظف ميداني (ينزل مع الزبائن)
  static const int employee = 4;     // موظف مكتب — عمليات مكتبية
  static const int deputy = 5;       // نائب مدير
  static const int manager = 6;      // مدير — أعلى صلاحية
  static const int lawyer = 7;       // محامي مختص — قسم الاستشارات والتوثيق العقود
  static const int expediter = 8;    // معقب معاملات ميداني — استخراج الثبوتيات

  /// أقل مستوى يُعتبر "موظف داخلي" (مصور فما فوق)
  static const int minInternal = photographer;
  /// أقل مستوى يُعتبر "إدارة" (مشرف فما فوق)
  static const int minAdmin = supervisor;
  /// أقل مستوى يُعتبر "إدارة عليا" (نائب مدير فما فوق)
  static const int minSenior = deputy;

  static String nameOf(int role) {
    switch (role) {
      case user: return 'مستخدم';
      case broker: return 'وسيط';
      case photographer: return 'مصور';
      case supervisor: return 'مشرف';
      case employee: return 'موظف مكتب';
      case deputy: return 'نائب مدير';
      case manager: return 'مدير';
      case lawyer: return 'محامي مختص';
      case expediter: return 'معقب معاملات';
      default: return 'غير معروف';
    }
  }

  /// عدد الأدوار الكلي (للحلقات والـ UI)
  static const int count = 9;
}

/// نموذج المستخدم — أسماء الحقول القصيرة تطابق قاعدة البيانات
class UserModel {
  final String uid;
  final String nm;
  final String ph;
  final String? eml; // الإيميل (المرحلة 7)
  final String ad;
  final int role;
  final String sid;
  final String img;
  final int pt;
  final int bg;
  final DateTime? bgTs;
  final int bPkg;
  final int pkgXoff; // السقف الإضافي من الباقات المكدّسة (التجميع 2026-07-27)
  final DateTime? pkgEnd;
  final DateTime? pkgGrace; // نهاية فترة السماح (pkg_end + 3 أيام)
  final DateTime? permBoostUntil; // 🔓 فتح سقف العروض المؤقت (2026-09-02)
  final int brk;
  final int brkCls;
  final String brkNm;
  final int sts;
  final String banRsn;
  final Map<String, dynamic> ntf;
  final Map<String, dynamic> stats;
  final List<dynamic> wkLgn;
  final int strk;
  final DateTime? strkDt;
  final int iDel;
  final List<String> perm;
  final DateTime tsCrt;
  final DateTime? tsUpd;
  /// ✓ التوثيق الرسمي: 0=غير موثق، 1=قيد المراجعة، 2=موثق بعد مراجعة الإدارة.
  /// مرجع: docs/LOGIC_SPEC.md §2.1
  final int vrf;
  /// اسم المستخدم الفريد (للدخول باسم مستخدم + كلمة مرور)
  final String? usr;
  /// هل تم تعيين كلمة مرور (لا نحتفظ بالقيمة — فقط نعرف هل موجودة)
  final String? pwd;

  UserModel({
    required this.uid,
    required this.nm,
    required this.ph,
    this.eml,
    this.ad = '',
    this.role = 0,
    this.sid = '',
    this.img = '',
    this.pt = 0,
    this.bg = 0,
    this.bgTs,
    this.bPkg = 0,
    this.pkgXoff = 0,
    this.pkgEnd,
    this.pkgGrace,
    this.permBoostUntil,
    this.brk = 0,
    this.brkCls = 0,
    this.brkNm = '',
    this.sts = 0,
    this.banRsn = '',
    Map<String, dynamic>? ntf,
    Map<String, dynamic>? stats,
    List<dynamic>? wkLgn,
    this.strk = 0,
    this.strkDt,
    this.iDel = 0,
    List<String>? perm,
    required this.tsCrt,
    this.tsUpd,
    this.vrf = 0,
    this.usr,
    this.pwd,
  })  : ntf = ntf ?? {'off': 0, 'app': 0, 'fin': 0, 'rat': 0},
        perm = perm ?? const [],
        stats = stats ?? {'off': 0, 'req': 0, 'app': 0, 'dl': 0},
        wkLgn = wkLgn ?? [];


  static List<String> _parsePermissions(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  factory UserModel.fromSupabase(Map<String, dynamic> data, String id) {
    return UserModel(
      uid: id,
      nm: data['nm'] ?? '',
      ph: data['ph'] ?? '',
      eml: data['eml'] as String?,
      ad: data['ad'] ?? '',
      role: data['role'] ?? 0,
      sid: data['sid'] ?? '',
      img: data['img'] ?? '',
      pt: data['pt'] ?? 0,
      bg: data['bg'] ?? 0,
      bgTs: data['bg_ts'] != null ? DateTime.parse(data['bg_ts']) : null,
      bPkg: data['b_pkg'] ?? 0,
      pkgXoff: data['pkg_xoff'] ?? 0,
      pkgEnd:   data['pkg_end']   != null ? DateTime.parse(data['pkg_end'])   : null,
      pkgGrace: data['pkg_grace'] != null ? DateTime.parse(data['pkg_grace']) : null,
      permBoostUntil: data['perm_boost_until'] != null
          ? DateTime.parse(data['perm_boost_until'])
          : null,
      brk: data['brk'] ?? 0,
      brkCls: data['brk_cls'] ?? 0,
      brkNm: data['brk_nm'] ?? '',
      sts: data['sts'] ?? 0,
      banRsn: data['ban_rsn'] ?? '',
      ntf: data['ntf'] != null
          ? Map<String, dynamic>.from(data['ntf'] as Map)
          : {'off': 0, 'app': 0, 'fin': 0, 'rat': 0},
      stats: data['stats'] != null
          ? Map<String, dynamic>.from(data['stats'] as Map)
          : {'off': 0, 'req': 0, 'app': 0, 'dl': 0},
      wkLgn: data['wk_lgn'] ?? [],
      strk: data['strk'] ?? 0,
      strkDt: data['strk_dt'] != null ? DateTime.parse(data['strk_dt']) : null,
      iDel: data['i_del'] ?? 0,
      perm: _parsePermissions(data['perm']),
      tsCrt: DateTime.parse(data['ts_crt']),
      tsUpd: data['ts_upd'] != null ? DateTime.parse(data['ts_upd']) : null,
      vrf: data['vrf'] ?? 0,
      usr: data['usr'] as String?,
      // pwd: نحتفظ فقط بمعرفة هل يوجد كلمة مرور (لا نقرأ القيمة الفعلية)
      pwd: data['pwd'] != null ? 'set' : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nm': nm, 'ph': ph, 'ad': ad, 'role': role, 'sid': sid,
      'img': img, 'pt': pt, 'bg': bg,
      'bg_ts': bgTs?.toIso8601String(), 'b_pkg': bPkg, 'pkg_xoff': pkgXoff,
      'pkg_end':   pkgEnd?.toIso8601String(),
      'pkg_grace': pkgGrace?.toIso8601String(),
      'perm_boost_until': permBoostUntil?.toIso8601String(),
      'brk': brk,
      'brk_cls': brkCls, 'brk_nm': brkNm, 'sts': sts,
      'ban_rsn': banRsn, 'ntf': ntf, 'stats': stats,
      'wk_lgn': wkLgn, 'strk': strk,
      'strk_dt': strkDt?.toIso8601String(), 'i_del': iDel,
      'perm': perm,
      'ts_crt': tsCrt.toIso8601String(),
      'ts_upd': tsUpd?.toIso8601String(),
      'vrf': vrf,
      'usr': usr,
    };
  }

  bool get isActive => sts == 0;
  bool get isFrozen => sts == 1;
  bool get isBanned => sts == 2;
  /// 🤝 BRK-001 (2026-08-15) — حالات طلب الوساطة:
  ///   0 ليس وسيطاً · 1 **وسيط معتمد** · 2 طلب قيد المراجعة · 3 طلب مرفوض
  /// (وُسِّعت `brk` بدل عمود جديد كي لا ينكسر أي كود يفحص `brk == 1`.)
  bool get isBroker => brk == 1;

  /// طلب وساطة قيد مراجعة الإدارة — لم يُمنح الدور بعد.
  bool get isBrokerPending => brk == 2;

  /// طلب وساطة رُفض (السبب في `brkRsn` إن توفّر).
  bool get isBrokerRejected => brk == 3;
  bool get isDeleted => iDel == 1;

  /// هل هو موظف داخلي (مصور فما فوق)؟
  bool get isInternal => role >= UserRole.minInternal;
  /// هل هو إداري تشغيلي يصل للوحة الإدارة؟
  /// مهم: الأدوار القانونية 7/8 أعلى رقمياً لكنها ليست إدارة.
  bool get isAdmin => role >= UserRole.minAdmin && role <= UserRole.manager;
  /// هل هو إدارة عليا (نائب مدير/مدير فقط)؟
  bool get isSenior => role >= UserRole.minSenior && role <= UserRole.manager;
  /// هل هو مصور؟
  bool get isPhotographer => role == UserRole.photographer;
  /// هل هو مشرف (ميداني)؟
  bool get isSupervisor => role == UserRole.supervisor;
  /// هل هو موظف مكتب؟
  bool get isEmployee => role == UserRole.employee;
  /// هل هو نائب مدير؟
  bool get isDeputy => role == UserRole.deputy;
  /// هل هو مدير؟
  bool get isManager => role == UserRole.manager;
  /// هل هو محامي مختص؟
  bool get isLawyer => role == UserRole.lawyer;
  /// هل هو معقب معاملات؟
  bool get isExpediter => role == UserRole.expediter;

  /// الباقة الفعلية مع مراعاة فترة السماح
  /// — إذا كانت ضمن pkg_grace تُعامَل كباقة نشطة
  int get effectivePkg {
    if (bPkg == 0) return 0;
    final now = DateTime.now();
    // نشطة أو ضمن فترة السماح
    if (pkgGrace != null && pkgGrace!.isAfter(now)) return bPkg;
    // قديمة بدون grace: نعتمد على pkg_end
    if (pkgGrace == null && pkgEnd != null && pkgEnd!.isAfter(now)) return bPkg;
    return 0;
  }

  /// 🔓 هل سقف العروض مفتوح مؤقتاً من الإدارة (لم تنته المدة بعد)
  bool get hasActiveOfferBoost =>
      permBoostUntil != null && permBoostUntil!.isAfter(DateTime.now());
  /// هل الباقة نشطة (لم تنته pkg_end)
  bool get isPkgActive =>
      bPkg > 0 && pkgEnd != null && pkgEnd!.isAfter(DateTime.now());

  /// هل في فترة السماح (pkg_end انتهت لكن pkg_grace لم تنته)
  bool get isInGracePeriod {
    if (bPkg == 0 || pkgEnd == null) return false;
    final now = DateTime.now();
    if (pkgEnd!.isAfter(now)) return false; // لم تنته بعد
    if (pkgGrace == null) return false;
    return pkgGrace!.isAfter(now);
  }

  /// أيام السماح المتبقية (0 إذا لم يكن في grace)
  int get graceDaysLeft {
    if (!isInGracePeriod || pkgGrace == null) return 0;
    return pkgGrace!.difference(DateTime.now()).inDays;
  }

  String get roleName => UserRole.nameOf(role);

  /// الرتبة السلوكية (Trust) — مكتسبة بالنشاط والنقاط.
  /// ملاحظة: المعادن (برونزي/فضي/ذهبي) محجوزة للباقات المدفوعة فقط.
  /// مرجع: docs/LOGIC_SPEC.md — القسم الثاني.
  String get badgeName {
    switch (bg) {
      case 1: return '📈 نشط';
      case 2: return '🤝 موثوق';
      case 3: return '🎓 خبير';
      case 4: return '⭐ نخبة';
      default: return '🔰 جديد';
    }
  }

  /// هل عيّن المستخدم كلمة مرور؟
  bool get hasPassword => pwd != null && pwd!.isNotEmpty;

  /// هل عيّن المستخدم اسم مستخدم؟
  bool get hasUsername => usr != null && usr!.isNotEmpty;

  /// هل بدأ المستخدم مسار التوثيق (رفع صورة هوية أو قيد المراجعة)؟
  bool get hasStartedVerification => img.isNotEmpty || vrf == 1;

  /// هل المستخدم موثق رسمياً بعد مراجعة الإدارة؟
  /// مرجع: docs/LOGIC_SPEC.md §2.1
  bool get isVerifiedOfficial => vrf == 2;
}
