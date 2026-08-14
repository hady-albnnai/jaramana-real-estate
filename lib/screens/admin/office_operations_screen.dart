import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/permission_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/admin_provider.dart';
import '../../widgets/fit_tile.dart';

/// مركز عمليات المكتب — شاشة تشغيلية مركزة لموظف المكتب/الإدارة.
/// تعتمد على الجداول الحالية ولا تضيف نموذج بيانات جديد.
class OfficeOperationsScreen extends StatefulWidget {
  const OfficeOperationsScreen({super.key});

  @override
  State<OfficeOperationsScreen> createState() => _OfficeOperationsScreenState();
}

class _OfficeOperationsScreenState extends State<OfficeOperationsScreen> {
  bool _loading = true;
  Map<String, int> _counts = {};
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final results = await Future.wait([
      admin.getActionCounts(adminUid),
      admin.getStats(adminUid),
    ]);
    if (!mounted) return;
    setState(() {
      _counts = Map<String, int>.from(results[0] as Map);
      _stats = Map<String, dynamic>.from(results[1] as Map);
      _loading = false;
    });
  }

  int get _totalPending =>
      (_counts['pendingOffers'] ?? 0) +
      (_counts['pendingPayments'] ?? 0) +
      (_counts['openReports'] ?? 0) +
      (_counts['pendingVerifications'] ?? 0);

  List<Map<String, dynamic>> _getShortcutItems(dynamic user) {
    final items = <Map<String, dynamic>>[];
    
    if (PermissionService.has(user, PermissionKeys.reviewOffers)) {
      items.add({
        'icon': Icons.rate_review_outlined,
        'title': 'مراجعة العروض',
        'route': '/admin/review-offers',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.managePayments)) {
      items.add({
        'icon': Icons.payment,
        'title': 'إدارة المدفوعات',
        'route': '/admin/payments',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.manageAppointments)) {
      items.add({
        'icon': Icons.event,
        'title': 'إدارة المواعيد',
        'route': '/admin/appointments',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.manageUsers)) {
      items.add({
        'icon': Icons.people,
        'title': 'إدارة المستخدمين',
        'route': '/admin/users',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.reviewVerifications)) {
      items.add({
        'icon': Icons.verified_user,
        'title': 'طلبات التوثيق',
        'route': '/admin/review-verifications',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.manageReports)) {
      items.add({
        'icon': Icons.flag,
        'title': 'التبليغات',
        'route': '/admin/reports',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.manageStaff)) {
      items.add({
        'icon': Icons.admin_panel_settings,
        'title': 'إدارة الموظفين',
        // 🔧 BUG-001 (أُصلح 2026-08-14): كان '/admin/employees' — مسار **غير
        // مسجَّل إطلاقاً** في app_router ⇒ المدير يضغط الزر فتظهر شاشة خطأ
        // go_router. المسار الصحيح المسجَّل هو '/admin/employee-management'
        // (وهو ما يستخدمه بند «أقسام الإدارة» السليم).
        'route': '/admin/employee-management',
      });
    }
    
    if (PermissionService.has(user, PermissionKeys.viewAnalytics)) {
      items.add({
        'icon': Icons.analytics,
        'title': 'التحليلات',
        'route': '/admin/analytics',
      });
    }
    
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('مركز عمليات المكتب'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: _load,
              child: ListView(
                padding: AppTheme.paddingAllLarge,
                children: [
                  _headerCard(),
                  AppTheme.gapHeightLarge,
                  _sectionTitle('الأولويات'),
                  if (PermissionService.has(auth.userModel, PermissionKeys.reviewOffers))
                    _priorityTile(
                    icon: Icons.fact_check_outlined,
                    title: 'عروض بانتظار المراجعة',
                    count: _counts['pendingOffers'] ?? 0,
                    route: '/admin/review-offers',
                    color: AppTheme.warningOrange,
                  ),
                  if (PermissionService.has(auth.userModel, PermissionKeys.managePayments))
                    _priorityTile(
                    icon: Icons.payments_outlined,
                    title: 'مدفوعات بانتظار الموافقة',
                    count: _counts['pendingPayments'] ?? 0,
                    route: '/admin/payments',
                    color: AppTheme.successGreen,
                  ),
                  if (PermissionService.has(auth.userModel, PermissionKeys.manageReports))
                    _priorityTile(
                    icon: Icons.flag_outlined,
                    title: 'تبليغات مفتوحة',
                    count: _counts['openReports'] ?? 0,
                    route: '/admin/reports',
                    color: AppTheme.errorRed,
                  ),
                  if (PermissionService.has(auth.userModel, PermissionKeys.reviewVerifications))
                    _priorityTile(
                    icon: Icons.verified_user_outlined,
                    title: 'طلبات توثيق',
                    count: _counts['pendingVerifications'] ?? 0,
                    route: '/admin/review-verifications',
                    color: AppTheme.infoBlue,
                  ),
                  AppTheme.gapHeightXL,
                  _sectionTitle('اختصارات التشغيل'),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: AppTheme.getGridColumns(
                        context,
                        mobile: 2,
                        tablet: 3,
                        desktop: 4,
                      ),
                      crossAxisSpacing: AppTheme.spacingMedium,
                      mainAxisSpacing: AppTheme.spacingMedium,
                      childAspectRatio: AppTheme.responsiveValue(
                        context,
                        mobile: 1.6,
                        tablet: 1.8,
                        desktop: 2.0,
                      ),
                    ),
                    itemCount: _getShortcutItems(auth.userModel).length,
                    itemBuilder: (context, index) {
                      final item = _getShortcutItems(auth.userModel)[index];
                      return _shortcut(item['icon'], item['title'], item['route']);
                    },
                  ),
                  AppTheme.gapHeightXL,
                  _sectionTitle('ملخص سريع'),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: AppTheme.getGridColumns(
                        context,
                        mobile: 2,
                        tablet: 2,
                        desktop: 4,
                      ),
                      crossAxisSpacing: AppTheme.spacingMedium,
                      mainAxisSpacing: AppTheme.spacingMedium,
                      childAspectRatio: AppTheme.responsiveValue(
                        context,
                        mobile: 1.6,
                        tablet: 1.8,
                        desktop: 2.0,
                      ),
                    ),
                    itemCount: 4,
                    itemBuilder: (context, index) {
                      switch (index) {
                        case 0:
                          return _stat('المستخدمون', _stats['totalUsers'] ?? 0, Icons.people_outline);
                        case 1:
                          return _stat('العروض', _stats['totalOffers'] ?? 0, Icons.home_work_outlined);
                        case 2:
                          return _stat('المواعيد', _stats['totalAppointments'] ?? 0, Icons.event_available_outlined);
                        case 3:
                          return _stat('الصفقات', _stats['totalDeals'] ?? 0, Icons.handshake_outlined);
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.primaryGold.withOpacity(0.12),
              borderRadius: AppTheme.radiusLarge,
            ),
            child: const Icon(Icons.support_agent, color: AppTheme.primaryGold, size: 30),
          ),
          AppTheme.gapWidthMedium,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'لوحة متابعة الأعمال اليومية',
                  style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold),
                ),
                AppTheme.gapHeightXS,
                Text(
                  _totalPending == 0
                      ? 'لا توجد عناصر عاجلة حالياً.'
                      : 'يوجد $_totalPending عنصر يحتاج متابعة.',
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _priorityTile({
    required IconData icon,
    required String title,
    required int count,
    required String route,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: AppTheme.radiusMedium,
          ),
          child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        onTap: () => context.push(route),
      ),
    );
  }

  Widget _shortcut(IconData icon, String title, String route) {
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: AppTheme.radiusLarge,
      child: Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusLarge,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.18)),
        ),
        // 🧱 UI-OVF-001: نفس الشبكة، نفس الخطر — عنوان بسطرين يفيض.
        child: FitTile.column(
          children: [
            Icon(icon, color: AppTheme.primaryGold, size: 32),
            AppTheme.gapHeightSmall,
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String title, dynamic value, IconData icon) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.16)),
      ),
      // 🧱 UI-OVF-001: كان هنا فيضان 0.66px مؤكَّد على شاشة المالك.
      child: FitTile.column(
        children: [
          Icon(icon, color: AppTheme.primaryGold),
          AppTheme.gapHeightSmall,
          Text('$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.primaryGold, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
        ],
      ),
    );
  }
}
