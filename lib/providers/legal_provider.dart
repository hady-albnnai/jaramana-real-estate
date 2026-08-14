import 'package:flutter/material.dart';
import '../models/lawyer_profile_model.dart';
import '../models/expediting_task_model.dart';
import '../core/network/supabase_service.dart';

class LegalProvider with ChangeNotifier {
  List<LawyerProfileModel> _activeLawyers = [];
  bool _isLoading = false;
  String? _error;
  List<LawyerProfileModel> get activeLawyers => _activeLawyers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ═══════════════════════════════════════════════════════════════
  // 🔴 إصلاح حرج 2026-08-14 — هوية الفاعل (actor uid)
  //
  // كانت 9 دوال تُرسل `'user_uid': ''` فارغاً، والإيدج يتحقق من الجلسة عبر
  // هذا الحقل بالجسم ⇒ كلها ترتد `USER_UID_REQUIRED`، ولوحة المحامي **عمياء
  // بالكامل**: الاستشارات/المواعيد/المهام/المعقّبون فارغة دائماً، وكل إجراء
  // يفشل. العطل بقي مخفياً لأن الكود كان يبتلع الخطأ بـ`catch (_) { = [] }`
  // فيتنكّر الفشل بهيئة «لا توجد بيانات» — نفس حادثة §13 (No-Silent-Probes).
  //
  // الحل: تُحفظ الهوية مرة واحدة عند تهيئة الشاشة وتُستخدم في كل نداء.
  // ═══════════════════════════════════════════════════════════════
  String _actorUid = '';
  String get actorUid => _actorUid;

  /// تُستدعى من الشاشات فور توفر المستخدم (لوحة المحامي/المعقّب).
  void setActor(String uid) {
    if (uid.isNotEmpty) _actorUid = uid;
  }

  /// تُستخدم في كل نداء: تفضّل الهوية الممرّرة ثم المحفوظة.
  String _uidOr(String uid) => uid.isNotEmpty ? uid : _actorUid;

  /// ⚠️ لا تبتلع الأخطاء: تُسجّل الخطأ الحقيقي بدل إرجاع قائمة فارغة صامتة.
  bool _ok(Map<String, dynamic>? data, String fallbackMsg) {
    if (data != null && data['success'] == true) {
      _error = null;
      return true;
    }
    _error = data?['error']?.toString() ?? fallbackMsg;
    return false;
  }

  Map<String, dynamic>? _lawyerProfile;
  bool _profileSetupComplete = false;
  bool get profileSetupComplete => _profileSetupComplete;
  Map<String, dynamic>? get lawyerProfile => _lawyerProfile;

  List<Map<String, dynamic>> _availableExpediters = [];
  List<Map<String, dynamic>> get availableExpediters => _availableExpediters;
  List<ExpeditingTaskModel> _lawyerTasks = [];
  List<ExpeditingTaskModel> get lawyerTasks => _lawyerTasks;
  List<Map<String, dynamic>> _lawyerAppointments = [];
  List<Map<String, dynamic>> get lawyerAppointments => _lawyerAppointments;
  List<Map<String, dynamic>> _lawyerConsultations = [];
  List<Map<String, dynamic>> get lawyerConsultations => _lawyerConsultations;
  List<ExpeditingTaskModel> _expeditingTasks = [];
  List<ExpeditingTaskModel> get expeditingTasks => _expeditingTasks;

  Future<void> fetchActiveLawyers() async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      // 2026-08-14: كان بلا user_uid فيرتد USER_UID_REQUIRED (نفس العطل الذي
      // شلّ لوحة المحامي) — يمنع نافذة «اختر المحامي» بشاشة الإدارة.
      final res = await SupabaseService().invokeFunction('legal-actions',
          body: {'action': 'get_active_lawyers', 'user_uid': _actorUid});
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        final list = data['lawyers'] as List? ?? [];
        _activeLawyers = list.map((e) => LawyerProfileModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      } else { _error = data?['error']?.toString() ?? 'فشل'; }
    } catch (e) { _error = e.toString(); }
    finally { _isLoading = false; notifyListeners(); }
  }

  Future<bool> upsertLawyerProfile({required String targetUid, required String whatsappPhone, String officeAddress = '', String specialization = 'عقارات وسيارات', Map<String, dynamic> avl = const {}}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'admin_upsert_lawyer', 'user_uid': targetUid, 'target_uid': targetUid,
        'whatsapp_phone': whatsappPhone, 'office_address': officeAddress,
        'specialization': specialization, 'avl': avl,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) { _profileSetupComplete = true; notifyListeners(); return true; }
      return false;
    } catch (e) { return false; }
  }

  /// تعود true فقط إذا وُجد ملف محامي برقم واتساب فعلي
  Future<bool> checkLawyerProfile(String uid) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_lawyer_profile', 'user_uid': uid});
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        final profile = data['profile'] as Map<String, dynamic>?;
        if (profile != null && profile['found'] == true) {
          final wa = (profile['whatsapp_phone'] ?? '').toString().trim();
          if (wa.isNotEmpty) { _lawyerProfile = profile; _profileSetupComplete = true; notifyListeners(); return true; }
        }
      }
      _profileSetupComplete = false; notifyListeners(); return false;
    } catch (e) { _profileSetupComplete = false; notifyListeners(); return false; }
  }

  Future<void> fetchAvailableExpediters() async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_available_expediters', 'user_uid': _actorUid});
      final data = res.data as Map<String, dynamic>?;
      _availableExpediters = _ok(data, 'تعذّر جلب المعقّبين')
          ? ((data!['expediters'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []) : [];
    } catch (e) { _error = e.toString(); _availableExpediters = []; }
    notifyListeners();
  }

  Future<bool> createExpeditingTask({required String expediterUid, required int itemType, String targetPropertyNum = '', String targetZone = '', String notes = '', List<Map<String, dynamic>> checklist = const []}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'create_expediting_task', 'user_uid': _actorUid,
        'expediter_uid': expediterUid, 'item_type': itemType,
        'target_property_num': targetPropertyNum, 'target_zone': targetZone,
        'lawyer_notes': notes, 'checklist': checklist,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) { await fetchLawyerTasks(); return true; }
      return false;
    } catch (e) { return false; }
  }

  Future<bool> completeExpeditingTask({required String taskId, String notes = ''}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'complete_expediting_task',
        'user_uid': _actorUid,
        'task_id': taskId,
        'expediter_notes': notes,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        await getExpeditingTasks();
        return true;
      }
      _error = data?['error']?.toString() ?? 'فشل إتمام المهمة';
      return false;
    } catch (e) { _error = e.toString(); return false; }
  }

  Future<bool> approveExpeditingTask({required String taskId}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'approve_expediting_task',
        'user_uid': _actorUid,
        'task_id': taskId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        await fetchLawyerTasks();
        return true;
      }
      _error = data?['error']?.toString() ?? 'فشل اعتماد المهمة';
      return false;
    } catch (e) { _error = e.toString(); return false; }
  }

  Future<void> fetchLawyerTasks() async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_lawyer_expediting_tasks', 'user_uid': _actorUid});
      final data = res.data as Map<String, dynamic>?;
      _lawyerTasks = _ok(data, 'تعذّر جلب المهام')
          ? ((data!['tasks'] as List?)?.map((e) => ExpeditingTaskModel.fromMap(Map<String, dynamic>.from(e as Map))).toList() ?? []) : [];
    } catch (e) { _error = e.toString(); _lawyerTasks = []; }
    notifyListeners();
  }

  Future<void> fetchLawyerAppointments() async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_lawyer_appointments', 'user_uid': _actorUid});
      final data = res.data as Map<String, dynamic>?;
      _lawyerAppointments = _ok(data, 'تعذّر جلب المواعيد')
          ? ((data!['appointments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []) : [];
    } catch (e) { _error = e.toString(); _lawyerAppointments = []; }
    notifyListeners();
  }

  Future<List<ExpeditingTaskModel>> getExpeditingTasks({String? userUid}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_my_expediting_tasks', 'user_uid': _uidOr(userUid ?? '')});
      final data = res.data as Map<String, dynamic>?;
      _expeditingTasks = (data != null && data['success'] == true)
          ? ((data['tasks'] as List?)?.map((e) => ExpeditingTaskModel.fromMap(Map<String, dynamic>.from(e as Map))).toList() ?? []) : [];
    } catch (e) { _expeditingTasks = []; }
    notifyListeners(); return _expeditingTasks;
  }

  Future<bool> updateChecklistItem({
    required String taskId,
    required String itemKey,
    required int status,
    String inputValue = '',
    String attachmentUrl = '',
    String attachmentBase64 = '',
    String attachmentContentType = 'image/jpeg',
    String notes = '',
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'update_checklist_item',
        'user_uid': _actorUid,
        'task_id': taskId,
        'item_key': itemKey,
        'status': status,
        'input_value': inputValue,
        'attachment_url': attachmentUrl,
        if (attachmentBase64.isNotEmpty) 'attachment_base64': attachmentBase64,
        if (attachmentBase64.isNotEmpty) 'attachment_content_type': attachmentContentType,
        'notes': notes,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) return true;
      _error = data?['error']?.toString() ?? 'فشل تحديث الوثيقة';
      return false;
    } catch (e) { _error = e.toString(); return false; }
  }

  Future<void> fetchLawyerConsultations() async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions',
          body: {'action': 'get_lawyer_consultations', 'user_uid': _actorUid});
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'تعذّر جلب الاستشارات')) {
        _lawyerConsultations = (data!['consultations'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
      } else {
        _lawyerConsultations = [];
      }
    } catch (e) {
      _error = e.toString();
      _lawyerConsultations = [];
    }
    notifyListeners();
  }

  /// 2026-08-14: أُضيف actorUid — الإيدج يتحقق من الجلسة عبر user_uid بالجسم،
  /// وتمريره فارغاً كان يُفشل نداء المستخدم العادي (إلغاء طلبه) بـUNAUTHORIZED.
  Future<bool> updateConsultationStatus(
      {required String id, required int status, String actorUid = ''}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions',
          body: {
            'action': 'update_consultation_status',
            'user_uid': _uidOr(actorUid),
            'consultation_id': id,
            'status': status,
          });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        await fetchLawyerConsultations();
        return true;
      }
      _error = data?['error']?.toString() ?? 'فشل التحديث';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  /// ⚖️ رفض المحامي مُوجَّه بالسبب (2026-08-14)
  /// السبب يحدد الإجراء التلقائي على السيرفر:
  /// need_info → الحالة 5 (المستخدم يستكمل) · unavailable/out_of_scope →
  /// إعادة إسناد تلقائية · illegal → رفض نهائي + تصعيد للإدارة.
  Future<Map<String, dynamic>?> rejectConsultation({
    required String id,
    required String reasonCode,
    String reasonNote = '',
    String actorUid = '',
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'reject_consultation',
        'user_uid': _uidOr(actorUid),
        'consultation_id': id,
        'reason_code': reasonCode,
        'reason_note': reasonNote,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        await fetchLawyerConsultations();
        return data;
      }
      _error = data?['error']?.toString() ?? 'فشل الرفض';
      return null;
    } catch (e) {
      _error = e.toString();
      return null;
    }
  }

  /// 🟢 تبديل حالة توفر المحامي (2026-08-14)
  /// كان is_active يُقرأ بمكانين بلا أي كاتب ⇒ مجمّد على true للجميع.
  Future<Map<String, dynamic>?> setAvailability({
    required String lawyerUid,
    required bool available,
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'set_lawyer_availability',
        'user_uid': lawyerUid,
        'available': available,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) return data;
      _error = data?['error']?.toString() ?? 'فشل تحديث حالة التوفر';
      return null;
    } catch (e) {
      _error = e.toString();
      return null;
    }
  }

  /// 🔁 المستخدم يستكمل البيانات الناقصة (الحالة 5 → 0)
  Future<bool> resubmitConsultation({
    required String id,
    required String userUid,
    required String subject,
    List<String> attachments = const [],
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'resubmit_consultation',
        'user_uid': userUid,
        'consultation_id': id,
        'subject': subject,
        'attachments': attachments,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) return true;
      _error = data?['error']?.toString() ?? 'فشل إرسال البيانات';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🗓️ أوقات المحامي والمواعيد (2026-08-14)
  // قرار المالك: المحامي يضبط أوقاته سلفاً (إلزامي) والعميل لا يرى غيرها.
  // ═══════════════════════════════════════════════════════════════

  /// أوقات المحامي الحالية من ملفه ({"sun":["09:00-13:00"], ...})
  Map<String, List<String>> get availabilitySlots {
    final raw = _lawyerProfile?['avl'];
    final out = <String, List<String>>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is List) out[k.toString()] = v.map((e) => e.toString()).toList();
      });
    }
    return out;
  }

  /// هل ضبط المحامي أوقاته؟ (بدونها لا يستطيع استخدام الشاشة)
  bool get hasAvailability => availabilitySlots.values.any((l) => l.isNotEmpty);

  Future<bool> saveAvailabilitySlots({
    required String lawyerUid,
    required Map<String, List<String>> avl,
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'set_availability_slots',
        'user_uid': _uidOr(lawyerUid),
        'avl': avl,
      });
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'فشل حفظ الأوقات')) {
        _lawyerProfile = {...?_lawyerProfile, 'avl': data!['avl']};
        notifyListeners();
        return true;
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// السلوتات الحرة (للعميل قبل حجز الجلسة الحضورية)
  Future<Map<String, dynamic>> fetchFreeSlots({String lawyerUid = '', int days = 14}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'get_free_slots',
        'user_uid': _actorUid,
        if (lawyerUid.isNotEmpty) 'lawyer_uid': lawyerUid,
        'days': days,
      });
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'تعذّر جلب المواعيد المتاحة')) {
        return {
          'slots': (data!['slots'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
          'lawyer_alias': data['lawyer_alias']?.toString() ?? '',
        };
      }
      return {'slots': <String>[], 'lawyer_alias': ''};
    } catch (e) {
      _error = e.toString();
      return {'slots': <String>[], 'lawyer_alias': ''};
    }
  }

  /// 📎 روابط موقّعة لمستندات الاستشارة (كانت تُعرض كعدد بلا إمكانية فتح)
  Future<List<Map<String, String>>> fetchConsultationFiles(String consultationId) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'get_consultation_files',
        'user_uid': _actorUid,
        'consultation_id': consultationId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'تعذّر فتح المستندات')) {
        return ((data!['files'] as List?) ?? [])
            .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
            .toList();
      }
      return [];
    } catch (e) {
      _error = e.toString();
      return [];
    }
  }

  /// 📅 تصرف المحامي بموعد: confirm | complete | cancel
  Future<bool> lawyerAppointmentAction({
    required String appointmentId,
    required String apptAction,
    String reason = '',
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'lawyer_appointment_action',
        'user_uid': _actorUid,
        'appointment_id': appointmentId,
        'appt_action': apptAction,
        'reason': reason,
      });
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'فشل تنفيذ الإجراء')) {
        await fetchLawyerAppointments();
        await fetchLawyerConsultations();
        return true;
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 👔 أدوات الإدارة للاستشارات (2026-08-14)
  // الفجوة: بعد رفض كل المحامين تبقى الاستشارة يتيمة بلا أي أداة إدارية.
  // ═══════════════════════════════════════════════════════════════
  List<Map<String, dynamic>> _adminConsultations = [];
  List<Map<String, dynamic>> get adminConsultations => _adminConsultations;

  Future<void> fetchAdminConsultations({bool onlyOrphan = false}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'admin_list_consultations',
        'user_uid': _actorUid,
        'only_orphan': onlyOrphan,
      });
      final data = res.data as Map<String, dynamic>?;
      _adminConsultations = _ok(data, 'تعذّر جلب الاستشارات')
          ? ((data!['consultations'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [])
          : [];
    } catch (e) {
      _error = e.toString();
      _adminConsultations = [];
    }
    notifyListeners();
  }

  /// إسناد يدوي بعد تنسيق الإدارة الخارجي مع المحامين
  Future<bool> adminAssignConsultation({
    required String consultationId,
    required String lawyerUid,
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'admin_assign_consultation',
        'user_uid': _actorUid,
        'consultation_id': consultationId,
        'lawyer_uid': lawyerUid,
      });
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'فشل الإسناد')) {
        await fetchAdminConsultations();
        return true;
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// منح رصيد استشارة (بدل الاسترداد النقدي — المبلغ يبقى بالخزينة)
  Future<bool> adminGrantCredit({
    required String userUid,
    required int serviceType,
    required String reason,
    String sourceConsultationId = '',
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'admin_grant_credit',
        'user_uid': _actorUid,
        'user_uid_target': userUid,
        'service_type': serviceType,
        'reason': reason,
        if (sourceConsultationId.isNotEmpty)
          'source_consultation_id': sourceConsultationId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (_ok(data, 'فشل منح الرصيد')) {
        await fetchAdminConsultations();
        return true;
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 🎁 رصيد المستخدم المتاح (تعرضه شاشة الاستشارة بدل زر الدفع)
  Future<List<Map<String, dynamic>>> fetchMyCredits(String userUid) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'my_consultation_credits',
        'user_uid': _uidOr(userUid),
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        return ((data['credits'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 🔔 العميل ينبّه المحامي المتأخر (كان الفعل موجوداً بالسيرفر بلا واجهة)
  /// الحارس الخادمي: مرّت ساعة على الأقل + الحالة 0 + المالك فقط.
  Future<Map<String, dynamic>?> reactivateConsultation({
    required String consultationId,
    required String userUid,
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'reactivate_consultation',
        'user_uid': _uidOr(userUid),
        'consultation_id': consultationId,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _error = null;
        return data;
      }
      _error = data?['error']?.toString() ?? 'فشل التنبيه';
      return null;
    } catch (e) {
      _error = e.toString();
      return null;
    }
  }

  /// 🔀 تحويل الاستشارة الهاتفية إلى جلسة حضورية بموعد مختار
  Future<Map<String, dynamic>?> convertToOnsite({
    required String consultationId,
    required String userUid,
    required String slot,
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'convert_to_onsite',
        'user_uid': _uidOr(userUid),
        'consultation_id': consultationId,
        'slot': slot,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        _error = null;
        return data;
      }
      _error = data?['error']?.toString() ?? 'فشل التحويل';
      return null;
    } catch (e) {
      _error = e.toString();
      return null;
    }
  }

  Future<bool> requestChecklistRevision({
    required String taskId,
    required String itemKey,
    String notes = '',
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'request_checklist_revision',
        'user_uid': _actorUid,
        'task_id': taskId,
        'item_key': itemKey,
        'revision_notes': notes,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        await fetchLawyerTasks();
        return true;
      }
      _error = data?['error']?.toString() ?? 'فشل طلب إعادة الوثيقة';
      return false;
    } catch (e) { _error = e.toString(); return false; }
  }
}
