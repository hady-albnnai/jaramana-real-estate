import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/supabase_service.dart';
import '../../core/utils/error_utils.dart';
import '../../models/social_account_model.dart';

/// خدمة إدارة حسابات النشر الاجتماعي (Edge Function: social-accounts).
///
/// كل الطلبات تمر عبر السيرفر بمفتاح الخدمة بعد التحقق من جلسة المدير
/// (role≥5) — التوكنات لا تُخزَّن في العميل ولا تعود إليه كاملة أبداً.
class SocialAccountsService {
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

  Future<Map<String, dynamic>> _invoke(
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

      final res = await SupabaseService()
          .invokeFunction('social-accounts', body: body);
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

  /// كل الحسابات غير المحذوفة (توكنات مقنّعة).
  Future<List<SocialAccountModel>> list(String adminUid) async {
    final data = await _invoke('list', {'admin_uid': adminUid});
    if (data['success'] != true || data['accounts'] is! List) return [];
    return (data['accounts'] as List)
        .whereType<Map>()
        .map((d) => SocialAccountModel.fromMap(Map<String, dynamic>.from(d)))
        .toList();
  }

  /// إضافة حساب جديد أو تعديل موجود.
  ///
  /// [id] فارغ = إضافة جديدة (يلزم [accessToken]).
  /// عند التعديل: [accessToken] فارغ = الاحتفاظ بالتوكن الحالي.
  Future<Map<String, dynamic>> save({
    required String adminUid,
    String? id,
    required String platform,
    required String name,
    required String accountExternalId,
    String? accessToken,
    bool isActive = true,
  }) async {
    final body = <String, dynamic>{
      'admin_uid': adminUid,
      'platform': platform,
      'name': name,
      'account_external_id': accountExternalId,
      'is_active': isActive,
    };
    if (id != null && id.isNotEmpty) body['id'] = id;
    if (accessToken != null && accessToken.isNotEmpty) {
      body['access_token'] = accessToken;
    }
    return _invoke('save', body);
  }

  /// إعادة التحقق من الحساب لدى Meta — يرجع الاسم الحقيقي للصفحة/الحساب.
  Future<Map<String, dynamic>> verify(String adminUid, String id) async {
    return _invoke('verify', {'admin_uid': adminUid, 'id': id});
  }

  /// حذف ناعم للحساب.
  Future<bool> delete(String adminUid, String id) async {
    final data = await _invoke('delete', {'admin_uid': adminUid, 'id': id});
    return data['success'] == true;
  }
}
