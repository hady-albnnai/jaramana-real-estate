import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/notification_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/services/notification_router.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/empty_state.dart';

/// 🔔 شاشة الإشعارات — قائمة + تعليم كمقروء + تنقّل حسب نوع الإشعار
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isNotEmpty) {
      context.read<NotificationProvider>().fetchNotifications(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NotificationProvider>();
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: Text(prov.notifications.length >= 100
            ? 'الإشعارات — أحدث 100'
            : 'الإشعارات'),
        actions: [
          if (prov.notifications.any((n) => !n.isRead))
            TextButton(
              onPressed: () => prov.markAllAsRead(uid).then((_) => _load()),
              child: const Text('تعليم الكل',
                  style: TextStyle(color: AppTheme.primaryGold)),
            ),
        ],
      ),
      body: prov.isLoading && prov.notifications.isEmpty
          ? ShimmerLoading.tileList()
          : prov.notifications.isEmpty
              ? const EmptyState(
                  message: 'لا توجد إشعارات حالياً',
                  icon: Icons.notifications_off_outlined,
                )
              : RefreshIndicator(
                  color: AppTheme.primaryGold,
                  onRefresh: () async => _load(),
                  child: ListView.builder(
                    padding: AppTheme.paddingAllMedium,
                    itemCount: prov.notifications.length,
                    itemBuilder: (_, i) => _tile(prov.notifications[i], prov),
                  ),
                ),
    );
  }

  Widget _tile(NotificationModel n, NotificationProvider prov) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: n.isRead
            ? AppTheme.surfaceBlack
            : AppTheme.primaryGold.withOpacity(0.08),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
            color: n.isRead
                ? Colors.white12
                : AppTheme.primaryGold.withOpacity(0.4)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryGold.withOpacity(0.15),
          child: Icon(_iconForType(n.tp), color: AppTheme.primaryGold),
        ),
        title: Text(n.ttl,
            style: TextStyle(
                color: AppTheme.textWhite,
                fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTheme.gapHeightXS,
            Text(n.bdy,
                style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
            AppTheme.gapHeightXS,
            Text(AppUtils.formatTimestamp(n.tsCrt),
                style: TextStyle(
                    color: AppTheme.textGrey.withOpacity(0.7), fontSize: AppTheme.fontSizeCaption)),
          ],
        ),
        // 2026-08-14: السهم يظهر فقط إن كان للإشعار وجهة فعلية — عرضه على
        // إشعار معلوماتي وعدٌ كاذب يُحبط المستخدم أكثر من غياب التنقّل.
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!n.isRead)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: AppTheme.primaryGold, shape: BoxShape.circle),
            ),
          if (_tappable(n)) ...[
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios,
                color: AppTheme.textGrey, size: 13),
          ],
        ]),
        onTap: () {
          final uid = context.read<AuthProvider>().userModel?.uid ?? '';
          if (!n.isRead && uid.isNotEmpty) {
            prov.markAsRead(uid, n.id).then((_) => _load());
          }
          _navigateForNotification(n);
        },
      ),
    );
  }

  IconData _iconForType(int tp) {
    switch (tp) {
      case 0:
        return Icons.home_work; // عروض
      case 1:
        return Icons.assignment; // طلبات
      case 2:
        return Icons.calendar_today; // مواعيد
      case 3:
        return Icons.payments; // مالية
      case 4:
        return Icons.account_circle; // حساب
      case 5:
        return Icons.star; // تقييم
      default:
        return Icons.notifications;
    }
  }

  int get _role => context.read<AuthProvider>().userModel?.role ?? 0;

  bool _tappable(NotificationModel n) => NotificationRouter.isTappable(
        act: n.act, refId: n.refId, tp: n.tp, role: _role,
      );

  /// 🧭 التنقّل عبر الموجّه الموحّد (نفسه الذي يستخدمه إشعار Push)
  ///
  /// كان يوجّه بـ`tp` فيعرف حالتين فقط من ست ⇒ 38% من الإشعارات لا تستجيب
  /// للضغط. والآن بـ`act` (35+ قيمة) لأن قياساً حياً أثبت أن `tp` غير موثوق
  /// (`photography_reminder_1h` مسجَّل بـtp=1 وtp=2 معاً).
  void _navigateForNotification(NotificationModel n) {
    final target = NotificationRouter.resolve(
      act: n.act, refId: n.refId, tp: n.tp, role: _role,
    );
    if (target.isDenied) {
      AppTheme.showSnackBar(
        context,
        SnackBar(content: Text(target.deniedReason ?? 'غير متاح')),
      );
      return;
    }
    if (!target.hasRoute) return; // معلوماتي — لا وجهة
    context.push(target.route!);
  }
}
