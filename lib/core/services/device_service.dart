import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/supabase_service.dart';

/// 🔒 Phase 9: خدمة Device Fingerprinting.
///
/// تُولّد معرّف عشوائي (UUID-like) للجهاز عند أول تشغيل وتحفظه في
/// SharedPreferences، ثم تُسجّله في users.device_id عبر RPC register_device.
///
/// الغاية: كشف مزارع الإحالة (نفس الجهاز يفتح عدة حسابات).
/// ملاحظة: ليس معرّفاً صارماً (المستخدم يقدر يمسح التطبيق)؛ لكن يصعّب الاحتيال
/// السطحي ويعمل كطبقة دفاع إضافية مع IP وrate-limit.
class DeviceService {
  static const _kDeviceIdKey = 'jaramana_device_id_v1';
  static DeviceService? _instance;
  DeviceService._();
  factory DeviceService() => _instance ??= DeviceService._();

  String? _cachedId;

  /// إرجاع بصمة الجهاز (تُولَّد مرة واحدة وتُحفظ).
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdKey);
    if (id == null || id.isEmpty) {
      id = _generateId();
      await prefs.setString(_kDeviceIdKey, id);
    }
    _cachedId = id;
    return id;
  }

  /// تسجيل بصمة الجهاز على السيرفر (idempotent).
  /// يُستدعى بعد تسجيل الدخول.
  Future<bool> registerWithServer({String? ipHint}) async {
    try {
      final id = await getDeviceId();
      await SupabaseService().invokeFunction('user-account', body: {'action': 'register_device', 'device_id': id, 'ip_hint': ipHint});
      return true;
    } catch (e) {return false;
    }
  }

  /// إعادة ضبط (للاختبار فقط).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceIdKey);
    _cachedId = null;
  }

  String _generateId() {
    // 32 char hex string بشبه UUID
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    // تنسيق UUID: 8-4-4-4-12
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
