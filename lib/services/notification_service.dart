import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/network/supabase_service.dart';
import '../core/constants/db_constants.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _localNotif.initialize(initSettings);_listenToNotifications();
  }

  static void _listenToNotifications() {
    try {
      final client = SupabaseService().client;
      final user = client.auth.currentUser;
      if (user == null) return;

      client.from(DbTables.notifications)
          .stream(primaryKey: ['id'])
          .listen((data) {
            for (var row in data) {
              if ((row['uid'] ?? '') == user.id && (row['i_del'] ?? 0) == 0) {
                _showLocalNotif(row['ttl'] ?? '', row['bdy'] ?? '');
              }
            }
          });} catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  static Future<void> _showLocalNotif(String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'jaramana_channel', 'المكتب العقاري الالكتروني - جرمانا',
        importance: Importance.high, priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      await _localNotif.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  static Future<void> showNotification({
    required String title, required String body, String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'jaramana_channel', 'المكتب العقاري الالكتروني - جرمانا',
      importance: Importance.high, priority: Priority.high,
    );
    await _localNotif.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  static Future<void> registerDeviceToken(String token) async {
    try {
      final client = SupabaseService().client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.from(DbTables.userDevices).upsert({
        'uid': user.id, 'device_token': token,
        'platform': 'android', 'is_active': true,
        'ts_upd': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }
}
