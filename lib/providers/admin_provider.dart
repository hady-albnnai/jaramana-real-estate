import 'package:flutter/foundation.dart';
import '../models/offer_model.dart';
import '../models/user_model.dart';
import '../models/appointment_model.dart';
import '../models/deal_model.dart';
import '../models/payment_model.dart';
import '../models/report_model.dart';
import '../models/request_model.dart';
import '../services/admin/staff_admin_service.dart';
import '../services/admin/payments_admin_service.dart';
import '../services/admin/reports_admin_service.dart';
import '../services/admin/offers_admin_service.dart';
import '../services/admin/stats_admin_service.dart';
import '../services/admin/appointments_admin_service.dart';
import '../services/admin/deals_admin_service.dart';
import '../services/admin/verifications_admin_service.dart';
import '../services/admin/users_admin_service.dart';

/// Provider لوحة الإدارة (role >= UserRole.minAdmin)
/// يجمع كل عمليات الإدارة: العروض، المستخدمون، المواعيد، الصفقات،
/// المدفوعات، التبليغات، الإحصائيات.
class AdminProvider with ChangeNotifier {
  final StaffAdminService _staffAdmin = StaffAdminService();
  final PaymentsAdminService _paymentsAdmin = PaymentsAdminService();
  final ReportsAdminService _reportsAdmin = ReportsAdminService();
  final OffersAdminService _offersAdmin = OffersAdminService();
  final StatsAdminService _statsAdmin = StatsAdminService();
  final AppointmentsAdminService _appointmentsAdmin = AppointmentsAdminService();
  final DealsAdminService _dealsAdmin = DealsAdminService();
  final VerificationsAdminService _verificationsAdmin = VerificationsAdminService();
  final UsersAdminService _usersAdmin = UsersAdminService();

  final bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// تحديث خارجي آمن — بديل عن استدعاء notifyListeners من خارج الكلاس
  /// (محمي في إصدارات Flutter الحديثة). السلوك مطابق حرفياً.
  void refresh() {
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }


  void _clearErrorSilently() {
    _error = null;
  }

  void _syncServiceError(String? err) {
    if (err == null) {
      _clearErrorSilently();
    } else {
      _error = err;
    }
  }

  void _syncStaffError() => _syncServiceError(_staffAdmin.lastError);
  void _syncPaymentsError() => _syncServiceError(_paymentsAdmin.lastError);
  void _syncReportsError() => _syncServiceError(_reportsAdmin.lastError);
  void _syncOffersError() => _syncServiceError(_offersAdmin.lastError);
  void _syncStatsError() => _syncServiceError(_statsAdmin.lastError);
  void _syncAppointmentsError() => _syncServiceError(_appointmentsAdmin.lastError);
  void _syncDealsError() => _syncServiceError(_dealsAdmin.lastError);
  void _syncVerificationsError() => _syncServiceError(_verificationsAdmin.lastError);
  void _syncUsersError() => _syncServiceError(_usersAdmin.lastError);


  // ═══════════════════════════════════════
  // 1) العروض (مراجعة)
  // ═══════════════════════════════════════
  Future<List<OfferModel>> getPendingOffers(String adminUid) async {
    final list = await _offersAdmin.getPendingOffers(adminUid);
    _syncOffersError();
    return list;
  }

  Future<List<OfferModel>> getSocialQueue(String adminUid) async {
    final list = await _offersAdmin.getSocialQueue(adminUid);
    _syncOffersError();
    return list;
  }

  Future<bool> publishOfferToSocial(String adminUid, String offerId) async {
    final ok = await _offersAdmin.publishToSocial(adminUid, offerId);
    _syncOffersError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<Map<String, dynamic>> reviewOffer(String adminUid, String offerId, bool approve,
      {String reason = ''}) async {
    final data = await _offersAdmin.reviewOffer(
      adminUid,
      offerId,
      approve,
      reason: reason,
    );
    _syncOffersError();
    final ok = data['success'] == true;
    if (ok) notifyListeners();
    return data;
  }

  /// نسخة bool للتوافق مع الشاشات القديمة
  Future<bool> reviewOfferBool(String adminUid, String offerId, bool approve,
      {String reason = ''}) async {
    final data = await reviewOffer(adminUid, offerId, approve, reason: reason);
    return data['success'] == true;
  }

  Future<bool> setOfferPriority(String adminUid, String offerId, String priorityType) async {
    final ok = await _offersAdmin.setOfferPriority(adminUid, offerId, priorityType);
    _syncOffersError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> deleteOfferByAdmin(String adminUid, String offerId) async {
    final ok = await _offersAdmin.deleteOfferByAdmin(adminUid, offerId);
    _syncOffersError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<List<OfferModel>> getOffersForMediaReview(String adminUid) async {
    final list = await _offersAdmin.getOffersForMediaReview(adminUid);
    _syncOffersError();
    return list;
  }

  // ═══════════════════════════════════════
  // 2) المستخدمون (إدارة)
  // ═══════════════════════════════════════
  Future<List<UserModel>> getAllUsers({String? search}) async {
    final list = await _usersAdmin.getAllUsers(search: search);
    _syncUsersError();
    return list;
  }

  Future<bool> updateUserRole(String adminUid, String uid, int newRole) async {
    final ok = await _staffAdmin.updateUserRole(adminUid, uid, newRole);
    _syncStaffError();
    if (ok) notifyListeners();
    return ok;
  }

  /// تغيير حالة المستخدم: 0=نشط, 1=مجمّد, 2=محظور
  Future<bool> setUserStatus(String adminUid, String uid, int status, {String reason = ''}) async {
    final ok = await _staffAdmin.setUserStatus(adminUid, uid, status, reason: reason);
    _syncStaffError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> banUser(String adminUid, String uid, String reason) => setUserStatus(adminUid, uid, 2, reason: reason);
  Future<bool> freezeUser(String adminUid, String uid, String reason) => setUserStatus(adminUid, uid, 1, reason: reason);
  Future<bool> activateUser(String adminUid, String uid) => setUserStatus(adminUid, uid, 0);

  Future<bool> softDeleteUser(String uid) async {
    // تم إغلاق soft_delete العام عن العميل. استخدم deleteStaffUser مع adminUid.
    return false;
  }

  Future<bool> updateUserPermissions(String adminUid, String uid, List<String> permissions) async {
    final ok = await _staffAdmin.updateUserPermissions(adminUid, uid, permissions);
    _syncStaffError();
    if (ok) notifyListeners();
    return ok;
  }
  /// 🔓 فتح سقف العروض مؤقتاً (2026-09-02)
  Future<Map<String, dynamic>?> boostUserOffers(String adminUid, String uid, {int hours = 48}) async {
    final res = await _staffAdmin.boostUserOffers(adminUid, uid, hours: hours);
    _syncStaffError();
    if (res != null && res['success'] == true) notifyListeners();
    return res;
  }

  // ═══════════════════════════════════════
  // 🆕 إدارة الموظفين (Employee Management)
  // ═══════════════════════════════════════
  Future<List<UserModel>> getAllStaffUsers(String adminUid) async {
    final users = await _staffAdmin.getAllStaffUsers(adminUid);
    _syncStaffError();
    return users;
  }

  Future<Map<String, dynamic>> createStaffUser({
    required String adminUid,
    required String fullName,
    required String phone,
    String email = '',
    String username = '',
    required int role,
    String address = '',
    String sid = '',
    String img = '',
    List<String> idImagesBase64 = const [],
    String idImageContentType = 'image/jpeg',
  }) async {
    final data = await _staffAdmin.createStaffUser(
      adminUid: adminUid,
      fullName: fullName,
      phone: phone,
      email: email,
      username: username,
      role: role,
      address: address,
      sid: sid,
      img: img,
      idImagesBase64: idImagesBase64,
      idImageContentType: idImageContentType,
    );
    _syncStaffError();
    if (data['success'] == true) notifyListeners();
    return data;
  }

  /// تغيير دور الموظف عبر Edge Function فقط.
  Future<bool> changeUserRole(String adminUid, String targetUid, int newRole) async {
    final ok = await _staffAdmin.updateUserRole(adminUid, targetUid, newRole);
    _syncStaffError();
    if (ok) notifyListeners();
    return ok;
  }

  /// تفعيل/تجميد/حظر الموظف عبر Edge Function فقط.
  Future<bool> toggleUserStatus(
    String adminUid,
    String targetUid,
    int newStatus, {
    String reason = '',
  }) async {
    final ok = await _staffAdmin.setUserStatus(
      adminUid,
      targetUid,
      newStatus,
      reason: reason,
    );
    _syncStaffError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<Map<String, dynamic>> resetStaffPassword({
    required String adminUid,
    required String targetUid,
  }) async {
    final data = await _staffAdmin.resetStaffPassword(
      adminUid: adminUid,
      targetUid: targetUid,
    );
    _syncStaffError();
    if (data['success'] == true) notifyListeners();
    return data;
  }

  /// حذف موظف (soft delete) عبر Edge Function فقط.
  Future<bool> deleteStaffUser(String adminUid, String targetUid) async {
    final ok = await _staffAdmin.deleteStaffUser(adminUid, targetUid);
    _syncStaffError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<List<String>> getStaffIdImageUrls(String adminUid, String targetUid) async {
    final urls = await _staffAdmin.getStaffIdImageUrls(adminUid, targetUid);
    _syncStaffError();
    return urls;
  }

  Future<Map<String, dynamic>> updateStaffIdImages({
    required String adminUid,
    required String targetUid,
    required List<String> idImagesBase64,
    String idImageContentType = 'image/jpeg',
  }) async {
    final data = await _staffAdmin.updateStaffIdImages(
      adminUid: adminUid,
      targetUid: targetUid,
      idImagesBase64: idImagesBase64,
      idImageContentType: idImageContentType,
    );
    _syncStaffError();
    if (data['success'] == true) notifyListeners();
    return data;
  }

  Future<Map<String, dynamic>> getStaffStatsInternal(String userUid) async {
    final stats = await _staffAdmin.getStaffStatsInternal(userUid);
    _syncStaffError();
    return stats;
  }

  // ═══════════════════════════════════════
  // 3) المواعيد (إدارة)
  // ═══════════════════════════════════════
  Future<List<RequestModel>> getAllRequests(String adminUid) async {
    final list = await _appointmentsAdmin.getAllRequests(adminUid);
    _syncAppointmentsError();
    return list;
  }

  Future<bool> closeRequest(
    String adminUid,
    String requestId,
    int status, {
    String reason = 'closed_by_admin',
    String note = '',
  }) async {
    final ok = await _appointmentsAdmin.closeRequest(
      adminUid: adminUid,
      requestId: requestId,
      status: status,
      reason: reason,
      note: note,
    );
    _syncAppointmentsError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<List<AppointmentModel>> getAllAppointments(String adminUid) async {
    final list = await _appointmentsAdmin.getAllAppointments(adminUid);
    _syncAppointmentsError();
    return list;
  }

  Future<bool> updateAppointmentStatus(String adminUid, String apptId, int status,
      {String adminNote = ''}) async {
    final ok = await _appointmentsAdmin.updateAppointmentStatus(
      adminUid,
      apptId,
      status,
      adminNote: adminNote,
    );
    _syncAppointmentsError();
    if (ok) notifyListeners();
    return ok;
  }

  /// فرض موعد من قبل الإدارة
  Future<bool> forceAppointment(String apptId, String adminId) async {
    final ok = await _appointmentsAdmin.forceAppointment(apptId, adminId);
    _syncAppointmentsError();
    if (ok) notifyListeners();
    return ok;
  }

  // ═══════════════════════════════════════
  // 4) الصفقات (إدارة)
  // ═══════════════════════════════════════
  Future<List<DealModel>> getAllDeals(String adminUid) async {
    final list = await _dealsAdmin.getAllDeals(adminUid);
    _syncDealsError();
    return list;
  }

  /// إنشاء صفقة (استمارة المندوب)
  Future<bool> createDeal(String adminUid, DealModel deal) async {
    final ok = await _dealsAdmin.createDeal(adminUid, deal);
    _syncDealsError();
    if (ok) notifyListeners();
    return ok;
  }

  /// إتمام صفقة (sts=1) + تسجيل العمولة
  Future<bool> completeDeal(String dealId, String adminId,
      {double? commission, String? note}) async {
    final ok = await _dealsAdmin.completeDeal(
      dealId,
      adminId,
      commission: commission,
      note: note,
    );
    _syncDealsError();
    if (ok) notifyListeners();
    return ok;
  }

  // ═══════════════════════════════════════
  // 5) المدفوعات (إدارة)
  // ═══════════════════════════════════════
  Future<List<PaymentModel>> getAllPayments(String adminUid, {int? status}) async {
    final list = await _paymentsAdmin.getAllPayments(adminUid, status: status);
    _syncPaymentsError();
    return list;
  }

  Future<String?> getPaymentProofUrl(String paymentId, String adminId) async {
    final url = await _paymentsAdmin.getPaymentProofUrl(paymentId, adminId);
    _syncPaymentsError();
    return url;
  }

  Future<bool> approvePayment(String paymentId, String adminId) async {
    final ok = await _paymentsAdmin.approvePayment(paymentId, adminId);
    _syncPaymentsError();
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> rejectPayment(String paymentId, String adminId, [String reason = '']) async {
    final ok = await _paymentsAdmin.rejectPayment(paymentId, adminId, reason);
    _syncPaymentsError();
    if (ok) notifyListeners();
    return ok;
  }

  /// ↩️ عكس اعتماد دفعة (IMP-001) — مدير فقط + سبب إلزامي.
  Future<bool> reversePayment(String paymentId, String adminId, String reason) async {
    final ok = await _paymentsAdmin.reversePayment(paymentId, adminId, reason);
    _syncPaymentsError();
    if (ok) notifyListeners();
    return ok;
  }

  // ═══════════════════════════════════════
  // 6) التبليغات (إدارة)
  // ═══════════════════════════════════════
  Future<List<ReportModel>> getAllReports(String adminUid, {int? status}) async {
    final list = await _reportsAdmin.getAllReports(adminUid, status: status);
    _syncReportsError();
    return list;
  }

  /// اتخاذ إجراء على تبليغ
  /// action: 0=لا إجراء, 1=تحذير, 2=تجميد, 3=حظر
  Future<bool> handleReport(String reportId, int action, String adminId,
      {String note = '', int duration = 0}) async {
    final ok = await _reportsAdmin.handleReport(
      reportId,
      action,
      adminId,
      note: note,
      duration: duration,
    );
    _syncReportsError();
    if (ok) notifyListeners();
    return ok;
  }

  // ═══════════════════════════════════════
  // 7) الإحصائيات الشاملة
  // ═══════════════════════════════════════
  Future<Map<String, dynamic>> getStats(String adminUid) async {
    final stats = await _statsAdmin.getStats(adminUid);
    _syncStatsError();
    return stats;
  }

  Future<Map<String, dynamic>> getResourceUsage(String adminUid) async {
    final usage = await _statsAdmin.getResourceUsage(adminUid);
    _syncStatsError();
    return usage;
  }

  /// عدّاد سريع للعناصر التي تحتاج إجراء (للوحة الرئيسية)
  Future<Map<String, int>> getActionCounts(String adminUid) async {
    final counts = await _statsAdmin.getActionCounts(adminUid);
    _syncStatsError();
    return counts;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🛡️ إدارة طلبات التوثيق (Verification Management)
  // مرجع: docs/LOGIC_SPEC.md §2.1
  // ═══════════════════════════════════════════════════════════════

  /// جلب المستخدمين الذين قدّموا طلب توثيق (vrf=1) لمراجعتهم.
  Future<List<Map<String, dynamic>>> getPendingVerifications(String adminUid) async {
    final list = await _verificationsAdmin.getPendingVerifications(adminUid);
    _syncVerificationsError();
    return list;
  }

  /// اعتماد توثيق مستخدم: vrf 1 → 2 (موثق رسمياً).
  Future<bool> approveVerification(String adminUid, String userId) async {
    final ok = await _verificationsAdmin.approveVerification(adminUid, userId);
    _syncVerificationsError();
    if (ok) notifyListeners();
    return ok;
  }

  /// رفض توثيق مستخدم: vrf 1 → 0 (يحتاج إعادة رفع).
  Future<bool> rejectVerification(String adminUid, String userId,
      {String reason = ''}) async {
    final ok = await _verificationsAdmin.rejectVerification(
      adminUid,
      userId,
      reason: reason,
    );
    _syncVerificationsError();
    if (ok) notifyListeners();
    return ok;
  }

}
