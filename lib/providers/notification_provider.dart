import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
import '../core/network/supabase_service.dart';
import '../core/constants/db_constants.dart';

class NotificationProvider with ChangeNotifier {
  /// 🔔 إشارة تحديث فوري (2026-08-19): يطلقها FCMService عند وصول Push
  /// والتطبيق مفتوح، فتستمع إليها الشاشات المفتوحة (شاشة الإشعارات)
  /// وتعيد الجلب لحظياً — بدل استطلاع دوري ثقيل أو انتظار إعادة الدخول.
  /// أُضيفت كإشارة ثابتة عمداً لأن FCMService بلا BuildContext،
  /// والشاشات تُضيف/تزيل مستمعها في initState/dispose.
  static final ValueNotifier<int> refreshSignal = ValueNotifier<int>(0);

  /// طلب تحديث القوائم/الشارات من أي مكان (بلا سياق).
  static void requestRefresh() => refreshSignal.value++;

  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  int _unreadCount = 0;

  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _unreadCount;

  Future<void> fetchNotifications(String userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await SupabaseService().invokeFunction('user-notifications', body: {'action': 'list', 'user_uid': userId}); final data = res.data as Map; final response = data['notifications'];
      _notifications = (response as List)
          .map((d) => NotificationModel.fromSupabase(
              Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await SupabaseService().invokeFunction(
        'user-notifications',
        body: {
          'action': 'mark_read',
          'user_uid': userId,
          'notification_id': notificationId,
        },
      );
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1 && !_notifications[index].isRead) {
        _notifications[index] = NotificationModel.fromSupabase(
          {..._notifications[index].toMap(), 'i_rd': 1},
          _notifications[index].id,
        );
        _unreadCount = _notifications.where((n) => !n.isRead).length;
      }
      notifyListeners();
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  Future<void> markAllAsRead(String userId) async {
    try {
      await SupabaseService().invokeFunction(
        'user-notifications',
        body: {
          'action': 'mark_all_read',
          'user_uid': userId,
        },
      );
      _notifications = _notifications
          .map((n) => NotificationModel.fromSupabase(
              {...n.toMap(), 'i_rd': 1}, n.id))
          .toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  Future<bool> sendNotification({
    required String userId,
    required int type,
    required String title,
    required String body,
    String action = '',
    String refId = '',
  }) async {
    try {
      // ✅ Fix for Bug #9: Use Edge Function to send notification
      final session = SupabaseService().client.auth.currentSession;
      final currentUserId = session?.user.id ?? '';
      
      if (currentUserId.isEmpty) return false;

      final res = await SupabaseService().invokeFunction(
        'user-notifications',
        body: {
          'action': 'send',
          'user_uid': currentUserId,
          'target_uid': userId,
          'type': type,
          'title': title,
          'body': body,
          'ref_id': refId,
          'action_type': action,
        },
      );
      
      final data = res.data as Map?;
      return data?['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> notificationsStream(String userId) {
    return SupabaseService().client
        .from(DbTables.notifications)
        .stream(primaryKey: ['id'])
        .order('ts_crt', ascending: false)
        .map((data) =>
            data.map((d) => Map<String, dynamic>.from(d)).toList());
  }
}
