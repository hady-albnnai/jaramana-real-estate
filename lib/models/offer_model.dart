class OfferModel {
  final String id;
  final String usrId;
  final String brkId;
  final double brkPct;
  final int typ;
  final int trx;
  final int cat;
  final int sub;
  final String contactPh;
  final String ttl;
  final double prc;
  final int cur;
  final Map<String, dynamic> loc;
  final String descript;
  final List<String> imgs;
  final String vdo;
  final int docTp;
  final String docImg;
  final String exactLoc;
  final Map<String, dynamic> specs;
  final double com;
  final int sts;
  final String rsn;
  final int vws;
  final int fvs;
  final int iPub;
  final int iSoc;
  final int? offerNumber; // رقم العرض التسلسلي — يظهر للجمهور
  final int socPub;

  /// تحليل متسامح لمواعيد المعاينة — أي قيمة غير متوقعة (boolean/نص/خراب)
  /// تُحوَّل لصيغة آمنة أو تُتجاهل بدل ما تكسّر جلبة العروض كاملة (درس 2026-07-27).
  static Map<String, List<String>> _parseAvl(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, List<String>>{};
    raw.forEach((k, v) {
      final key = k.toString();
      if (v is List) {
        out[key] = v.map((e) => e.toString()).toList();
      } else if (key == 'any') {
        // أي قيمة غير-قائمة على مفتاح any (مثل {"any": true} من لصقة يدوية قديمة)
        // = «جاهز بأي وقت» — نفس النافذة التي يكتبها التطبيق
        out[key] = const ['00:00-23:59'];
      }
      // أي مفتاح آخر بقيمة خراب يُتجاهل بصمت — لا نكسّر الجلبة بسببه أبداً
    });
    return out;
  }
  final String socTxt;
  final int iDup;
  final String dupOf;
  // 📸 2026-08-20: وسم عرض طلب التصوير (photo_req) — لعرض عداد الحصة بدقة
  final int photoReq;
  // avl: أيام وفترات المواعيد المتاحة للمعاينة
  // البنية: {"wed": ["10:00-13:00", "15:00-17:00"], "fri": ["09:00-11:00"]}
  final Map<String, List<String>> avl;
  // من أضاف العرض (للإدارة فقط — لا يظهر للجمهور)
  final String? addedBy;
  // ─── ترقيات (spd) ───
  final int iPin; // مثبّت في الأعلى
  final int iBst; // boosted
  final int iFms; // عرض مميّز (Featured)
  final DateTime? pinEnd;
  final DateTime? bstEnd;
  final DateTime? fmsEnd;
  final int dscPct; // خصم % على عمولة المكتب
  final DateTime? dscEnd;
  // ───────────────────
  final int iDel;
  final DateTime tsCrt;
  final DateTime? tsPub;
  final DateTime? tsEnd;
  final DateTime? tsRen;

  // حقول مؤقتة لنسبة التطابق (لا تُحفظ في قاعدة البيانات)
  int? matchScore;
  Map<String, int>? matchBreakdown;

  /// تاريخ انتهاء العرض الفعلي
  DateTime get expirationDate {
    if (tsEnd != null) return tsEnd!;
    // 🔁 2026-09-22 (قرار المالك): العمر الافتراضي 90 يوماً — مرحلة بناء المحتوى
    if (tsPub != null) return tsPub!.add(const Duration(days: 90));
    return tsCrt.add(const Duration(days: 90));
  }

  /// عدد الأيام المتبقية حتى انتهاء العرض
  int get daysUntilExpiration {
    final diff = expirationDate.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// 🏢 تسمية مهنية لمالك العرض (هوية المكتب) — حقل عابر لا يُحفظ في DB.
  /// يُحقن من Provider بعد جلب بيانات المالك. مرجع: docs/LOGIC_SPEC.md §1.
  /// إذا كان null لا تُعرض، إذا كان غير null يُعرض بدل أي إشارة لاسم المالك.
  String? ownerLabel;

  OfferModel({
    required this.id,
    required this.usrId,
    this.brkId = '',
    this.brkPct = 0,
    required this.typ,
    required this.trx,
    required this.cat,
    this.sub = 0,
    this.contactPh = '',
    required this.ttl,
    required this.prc,
    this.cur = 1,
    Map<String, dynamic>? loc,
    this.descript = '',
    List<String>? imgs,
    this.vdo = '',
    this.docTp = 0,
    this.docImg = '',
    this.exactLoc = '',
    Map<String, dynamic>? specs,
    this.com = 0,
    this.sts = 0,
    this.rsn = '',
    this.vws = 0,
    this.fvs = 0,
    this.iPub = 0,
    this.iSoc = 0,
    this.offerNumber,
    this.socPub = 0,
    this.socTxt = '',
    this.iDup = 0,
    this.dupOf = '',
    this.photoReq = 0,
    Map<String, List<String>>? avl,
    this.addedBy,
    this.iPin = 0,
    this.iBst = 0,
    this.iFms = 0,
    this.pinEnd,
    this.bstEnd,
    this.fmsEnd,
    this.dscPct = 0,
    this.dscEnd,
    this.iDel = 0,
    required this.tsCrt,
    this.tsPub,
    this.tsEnd,
    this.tsRen,
  })  : loc = loc ?? {'r': 0, 'd': ''},
        imgs = imgs ?? [],
        specs = specs ?? {},
        avl = avl ?? {};

  factory OfferModel.fromSupabase(Map<String, dynamic> data, String id) {
    return OfferModel(
      id: id,
      usrId: data['usr_id'] ?? '',
      brkId: data['brk_id'] ?? '',
      brkPct: (data['brk_pct'] ?? 0).toDouble(),
      typ: data['typ'] ?? 0,
      trx: data['trx'] ?? 0,
      cat: data['cat'] ?? 0,
      sub: data['sub'] ?? 0,
      contactPh: data['contact_ph'] ?? '',
      ttl: data['ttl'] ?? '',
      prc: (data['prc'] ?? 0).toDouble(),
      cur: data['cur'] ?? 1,
      loc: data['loc'] != null
          ? Map<String, dynamic>.from(data['loc'] as Map)
          : {'r': 0, 'd': ''},
      descript: data['descript'] ?? '',
      imgs: data['imgs'] != null
          ? List<String>.from(data['imgs'] as List)
          : [],
      vdo: data['vdo'] ?? '',
      docTp: data['doc_tp'] ?? 0,
      docImg: data['doc_img'] ?? '',
      exactLoc: data['exact_loc'] ?? '',
      specs: data['specs'] != null
          ? Map<String, dynamic>.from(data['specs'] as Map)
          : {},
      com: (data['com'] ?? 0).toDouble(),
      sts: data['sts'] ?? 0,
      rsn: data['rsn'] ?? '',
      vws: data['vws'] ?? 0,
      fvs: data['fvs'] ?? 0,
      iPub: data['i_pub'] ?? 0,
      iSoc: data['i_soc'] ?? 0,
      offerNumber: data['offer_number'] as int?,
      socPub: data['soc_pub'] ?? 0,
      socTxt: data['soc_txt'] ?? '',
      iDup: data['i_dup'] ?? 0,
      dupOf: data['dup_of'] ?? '',
      photoReq: data['photo_req'] ?? 0,
      avl: _parseAvl(data['avl']),
      addedBy: data['added_by'],
      iPin: data['i_pin'] ?? 0,
      iBst: data['i_bst'] ?? 0,
      iFms: data['i_fms'] ?? 0,
      pinEnd: data['pin_end'] != null ? DateTime.parse(data['pin_end']) : null,
      bstEnd: data['bst_end'] != null ? DateTime.parse(data['bst_end']) : null,
      fmsEnd: data['fms_end'] != null ? DateTime.parse(data['fms_end']) : null,
      dscPct: data['dsc_pct'] ?? 0,
      dscEnd: data['dsc_end'] != null ? DateTime.parse(data['dsc_end']) : null,
      iDel: data['i_del'] ?? 0,
      tsCrt: DateTime.parse(data['ts_crt']),
      tsPub: data['ts_pub'] != null ? DateTime.parse(data['ts_pub']) : null,
      tsEnd: data['ts_end'] != null ? DateTime.parse(data['ts_end']) : null,
      tsRen: data['ts_ren'] != null ? DateTime.parse(data['ts_ren']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'usr_id': usrId,
      'brk_id': brkId.isEmpty ? null : brkId,
      'brk_pct': brkPct,
      'typ': typ, 'trx': trx, 'cat': cat, 'sub': sub,
      'contact_ph': contactPh,
      'ttl': ttl, 'prc': prc, 'cur': cur, 'loc': loc,
      'descript': descript, 'imgs': imgs, 'vdo': vdo,
      'doc_tp': docTp, 'doc_img': docImg, 'exact_loc': exactLoc,
      'specs': specs, 'com': com, 'sts': sts, 'rsn': rsn,
      'vws': vws, 'fvs': fvs, 'i_pub': iPub, 'i_soc': iSoc,
      'soc_pub': socPub, 'soc_txt': socTxt, 'i_dup': iDup,
      'dup_of': dupOf.isEmpty ? null : dupOf,
      'photo_req': photoReq,
      'avl': avl,
      'added_by': addedBy,
      'i_pin': iPin, 'i_bst': iBst, 'i_fms': iFms,
      'pin_end': pinEnd?.toIso8601String(),
      'bst_end': bstEnd?.toIso8601String(),
      'fms_end': fmsEnd?.toIso8601String(),
      'dsc_pct': dscPct,
      'dsc_end': dscEnd?.toIso8601String(),
      'i_del': iDel,
      'ts_crt': tsCrt.toIso8601String(),
      'ts_pub': tsPub?.toIso8601String(),
      'ts_end': tsEnd?.toIso8601String(),
      'ts_ren': tsRen?.toIso8601String(),
    };
  }
}
