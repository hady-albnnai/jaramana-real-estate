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
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_active_lawyers'});
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
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_available_expediters', 'user_uid': ''});
      final data = res.data as Map<String, dynamic>?;
      _availableExpediters = (data != null && data['success'] == true)
          ? ((data['expediters'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []) : [];
    } catch (_) { _availableExpediters = []; }
    notifyListeners();
  }

  Future<bool> createExpeditingTask({required String expediterUid, required int itemType, String targetPropertyNum = '', String targetZone = '', String notes = '', List<Map<String, dynamic>> checklist = const []}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'create_expediting_task', 'user_uid': '',
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
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_lawyer_expediting_tasks', 'user_uid': ''});
      final data = res.data as Map<String, dynamic>?;
      _lawyerTasks = (data != null && data['success'] == true)
          ? ((data['tasks'] as List?)?.map((e) => ExpeditingTaskModel.fromMap(Map<String, dynamic>.from(e as Map))).toList() ?? []) : [];
    } catch (e) { _lawyerTasks = []; }
    notifyListeners();
  }

  Future<void> fetchLawyerAppointments() async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_lawyer_appointments', 'user_uid': ''});
      final data = res.data as Map<String, dynamic>?;
      _lawyerAppointments = (data != null && data['success'] == true)
          ? ((data['appointments'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []) : [];
    } catch (_) { _lawyerAppointments = []; }
    notifyListeners();
  }

  Future<List<ExpeditingTaskModel>> getExpeditingTasks({String? userUid}) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {'action': 'get_my_expediting_tasks', 'user_uid': userUid ?? ''});
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
          body: {'action': 'get_lawyer_consultations', 'user_uid': ''});
      final data = res.data as Map<String, dynamic>?;
      _lawyerConsultations = (data != null && data['success'] == true)
          ? ((data['consultations'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [])
          : [];
    } catch (_) {
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
            'user_uid': actorUid,
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
        'user_uid': actorUid,
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

  Future<bool> requestChecklistRevision({
    required String taskId,
    required String itemKey,
    String notes = '',
  }) async {
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'request_checklist_revision',
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
