import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/supabase_service.dart';
import '../../core/utils/error_utils.dart';
import '../../models/user_model.dart';
import '../auth_service.dart';

/// خدمة إدارة الموظفين والعمليات الإدارية الحساسة.
///
/// هذه الخدمة تفصل منطق Edge Functions/RPCs عن AdminProvider، وتضمن إرسال
/// staff_session_token مع العمليات الحساسة بعد إصلاح P1/P2.
class StaffAdminService {
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

  Future<Map<String, dynamic>> _invokeStaffFunction(
    String name,
    Map<String, dynamic> body,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('staff_session_token');
      if (sessionToken != null && sessionToken.isNotEmpty) {
        body['staff_session_token'] = sessionToken;
      }

      final res = await SupabaseService().invokeFunction(name, body: body);
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

  Future<List<UserModel>> getAllStaffUsers(String adminUid) async {
    try {
      final token = await AuthService().getStaffSessionToken();
      final response = await SupabaseService().invokeFunction(
        'admin-dashboard',
        body: {
          'action': 'all_staff',
          'admin_uid': adminUid,
          'staff_session_token': token,
        },
      );
      final data = response.data;
      if (data == null || data['success'] != true) throw Exception(data?['error'] ?? 'Error');
      final res = data['staff'] as List;
      clearError();
      return res
          .map((d) => UserModel.fromSupabase(
              Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
    } catch (e) {
      _setError(e);
      return [];
    }
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
  }) {
    return _invokeStaffFunction('create-user', {
      'admin_uid': adminUid,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'username': username,
      'role': role,
      'address': address,
      'sid': sid,
      'img': img,
      'id_images_base64': idImagesBase64,
      'id_image_content_type': idImageContentType,
    });
  }

  Future<bool> updateUserRole(String adminUid, String uid, int newRole) async {
    final data = await _invokeStaffFunction('update-user-role', {
      'admin_uid': adminUid,
      'user_id': uid,
      'role': newRole,
    });
    return data['success'] == true;
  }

  Future<bool> setUserStatus(
    String adminUid,
    String uid,
    int status, {
    String reason = '',
  }) async {
    final data = await _invokeStaffFunction('toggle-user-status', {
      'admin_uid': adminUid,
      'user_id': uid,
      'status': status,
      'reason': reason,
    });
    return data['success'] == true;
  }

  Future<bool> updateUserPermissions(
    String adminUid,
    String uid,
    List<String> permissions,
  ) async {
    final data = await _invokeStaffFunction('update-user-permissions', {
      'admin_uid': adminUid,
      'user_id': uid,
      'permissions': permissions,
    });
    return data['success'] == true;
  }
  /// 🔓 فتح سقف العروض مؤقتاً (2026-09-02) — إشعار فوري يصل المستخدم
  Future<Map<String, dynamic>?> boostUserOffers(
    String adminUid,
    String uid, {
    int hours = 48,
  }) async {
    try {
      return await _invokeStaffFunction('update-user-permissions', {
        'admin_uid': adminUid,
        'user_id': uid,
        'action': 'boost_offers',
        'hours': hours,
      });
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> resetStaffPassword({
    required String adminUid,
    required String targetUid,
  }) {
    return _invokeStaffFunction('reset-user-password', {
      'admin_uid': adminUid,
      'user_id': targetUid,
    });
  }

  Future<bool> deleteStaffUser(String adminUid, String targetUid) async {
    final data = await _invokeStaffFunction('delete-user', {
      'admin_uid': adminUid,
      'user_id': targetUid,
    });
    return data['success'] == true;
  }

  Future<List<String>> getStaffIdImageUrls(String adminUid, String targetUid) async {
    final data = await _invokeStaffFunction('get-staff-id-images', {
      'admin_uid': adminUid,
      'target_uid': targetUid,
    });
    if (data['success'] != true) return const [];
    final urls = data['urls'];
    if (urls is! List) return const [];
    return urls.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  Future<Map<String, dynamic>> updateStaffIdImages({
    required String adminUid,
    required String targetUid,
    required List<String> idImagesBase64,
    String idImageContentType = 'image/jpeg',
  }) {
    return _invokeStaffFunction('update-staff-id-images', {
      'admin_uid': adminUid,
      'target_uid': targetUid,
      'id_images_base64': idImagesBase64,
      'id_image_content_type': idImageContentType,
    });
  }

  Future<Map<String, dynamic>> getStaffStatsInternal(String userUid) async {
    try {
      final token = await AuthService().getStaffSessionToken();
      final response = await SupabaseService().invokeFunction(
        'admin-dashboard',
        body: {
          'action': 'staff_stats',
          'user_uid': userUid,
          'staff_session_token': token,
        },
      );
      final data = response.data;
      if (data == null || data['success'] != true) {
        _setError(data?['error'] ?? 'UNKNOWN');
        return {};
      }
      clearError();
      return Map<String, dynamic>.from(data['stats'] ?? {});
    } catch (e) {
      _setError(e);
      return {};
    }
  }
}
