import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/supabase_service.dart';
import '../../core/utils/error_utils.dart';
import '../../models/payment_model.dart';

/// خدمة إدارة المدفوعات للإدارة.
/// تفصل منطق RPCs المالية عن AdminProvider لتقليل تضخمه.
class PaymentsAdminService {
  String? _lastError;
  String? get lastError => _lastError;

  void clearError() => _lastError = null;

  void _setError(Object? error) {
    _lastError = ErrorUtils.arabicMessage(error);
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<Map<String, dynamic>> _invokeAdminPayments(
    String action,
    Map<String, dynamic> body,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('staff_session_token');
      if (sessionToken != null && sessionToken.isNotEmpty) {
        body['staff_session_token'] = sessionToken;
      }
      body['action'] = action;
      final res = await SupabaseService().invokeFunction('admin-payments', body: body);
      final data = _asMap(res.data);
      if (data == null) {
        _setError('EMPTY_RESPONSE');
        return {'success': false, 'error': 'EMPTY_RESPONSE'};
      }
      if (data['success'] == true) {
        clearError();
      } else {
        _setError(data['error'] ?? 'UNKNOWN_ERROR');
      }
      return data;
    } catch (e) {
      _setError(e);
      return {'success': false, 'error': ErrorUtils.normalize(e)};
    }
  }

  Future<List<PaymentModel>> getAllPayments(String adminUid, {int? status}) async {
    final data = await _invokeAdminPayments('list', {'admin_uid': adminUid});
    if (data['success'] != true || data['payments'] is! List) return [];
    var list = (data['payments'] as List)
        .map((d) => PaymentModel.fromSupabase(
            Map<String, dynamic>.from(d as Map), d['id'] as String))
        .toList();
    if (status != null) {
      list = list.where((p) => p.sts == status).toList();
    }
    return list;
  }

  /// رابط مؤقت لإثبات الدفع الخاص — يُولَّد خادمياً بعد التحقق من الإدارة.
  Future<String?> getPaymentProofUrl(String paymentId, String adminId) async {
    final data = await _invokeAdminPayments('signed_proof_url', {
      'admin_uid': adminId,
      'payment_id': paymentId,
    });
    if (data['success'] != true) return null;
    final url = data['signed_url']?.toString() ?? '';
    return url.isEmpty ? null : url;
  }

  Future<bool> approvePayment(String paymentId, String adminId) async {
    final data = await _invokeAdminPayments('approve', {
      'admin_uid': adminId,
      'payment_id': paymentId,
    });
    return data['success'] == true;
  }

  Future<bool> rejectPayment(String paymentId, String adminId, [String reason = '']) async {
    final data = await _invokeAdminPayments('reject', {
      'admin_uid': adminId,
      'payment_id': paymentId,
      'reason': reason,
    });
    return data['success'] == true;
  }

  /// ↩️ عكس اعتماد دفعة — مدير فقط، وسبب إلزامي (IMP-001، 2026-08-14).
  ///
  /// لم يكن هناك أي مسار للتراجع: احتيال يُكتشف بعد الاعتماد كان يستلزم
  /// تعديل SQL يدوياً على قاعدة الإنتاج. السيرفر يتراجع عن الأثر أيضاً
  /// (الباقة تُلغى · الإعلان المميّز يُسحب) ويُشعر المستخدم بالسبب.
  Future<bool> reversePayment(String paymentId, String adminId, String reason) async {
    final data = await _invokeAdminPayments('reverse', {
      'admin_uid': adminId,
      'payment_id': paymentId,
      'reason': reason,
    });
    return data['success'] == true;
  }
}
