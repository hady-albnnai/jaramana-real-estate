import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/e2e.dart';

/// شاشة أقسام الإدارة.
///
/// الهدف منها أن تكون محطة تنقل مستقلة، بحيث يرجع المستخدم إليها من الشاشات
/// الفرعية بدلاً من الرجوع مباشرة إلى لوحة المدير.
class AdminSectionsScreen extends StatefulWidget {
  const AdminSectionsScreen({super.key});

  @override
  State<AdminSectionsScreen> createState() => _AdminSectionsScreenState();
}

class _AdminSectionsScreenState extends State<AdminSectionsScreen> {
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final adminUid = auth.userModel?.uid ?? '';
    final counts = await context.read<AdminProvider>().getActionCounts(adminUid);
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().userModel;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('أقسام الإدارة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : ListView(
              padding: AppTheme.paddingAllLarge,
              children: [
                const Text(
                  'صفحات متابعة وإدارة وليست صفحات تنفيذ ميداني خاصة بالمنفذ أو المصور.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                ),
                AppTheme.gapHeightLarge,
                _section('التنظيم', [
                  if (PermissionService.has(user, PermissionKeys.manageStaff))
                    _tile(Icons.badge_outlined, 'إدارة الموظفين', '/admin/employee-management'),
                  if (PermissionService.has(user, PermissionKeys.manageUsers))
                    _tile(Icons.people_outline, 'إدارة الحسابات والعملاء', '/admin/users'),
                  if (PermissionService.has(user, PermissionKeys.managePermissions))
                    _tile(Icons.admin_panel_settings_outlined, 'الصلاحيات', '/admin/permissions'),
                  if (PermissionService.has(user, PermissionKeys.officeOperations))
                    _tile(Icons.support_agent_outlined, 'عمليات المكتب', '/admin/office-operations'),
                  if (PermissionService.has(user, PermissionKeys.officeOperations))
                    _tile(Icons.gavel_outlined, 'الاستشارات القانونية', '/admin/legal-consultations'),
                  if (PermissionService.has(user, PermissionKeys.addOfferAdmin))
                    _tile(Icons.add_home_work, 'إضافة عرض', '/admin/add-offer'),
                ]),
                _section('المراجعات والرقابة', [
                  if (PermissionService.has(user, PermissionKeys.reviewOffers))
                    _tile(Icons.fact_check_outlined, 'مراجعة العروض', '/admin/review-offers', badge: _counts['pendingOffers'] ?? 0),
                  if (PermissionService.has(user, PermissionKeys.mediaReview))
                    _tile(Icons.photo_library_outlined, 'إدارة الوسائط', '/admin/media-review'),
                  if (PermissionService.has(user, PermissionKeys.reviewVerifications))
                    _tile(Icons.verified_user_outlined, 'طلبات التوثيق', '/admin/review-verifications', badge: _counts['pendingVerifications'] ?? 0),
                  if (PermissionService.has(user, PermissionKeys.fraudSuspects))
                    _tile(Icons.security, 'كشف الاحتيال', '/admin/fraud-suspects'),
                ]),
                _section('متابعة العمليات', [
                  if (PermissionService.has(user, PermissionKeys.manageAppointments))
                    _tile(Icons.calendar_month_outlined, 'المواعيد والمتابعة', '/admin/appointments'),
                  if (PermissionService.has(user, PermissionKeys.completionRequests))
                    _tile(Icons.assignment_turned_in_outlined, 'طلبات الإتمام', '/admin/completion-requests'),
                  if (PermissionService.has(user, PermissionKeys.photographyManagement))
                    _tile(Icons.add_a_photo_outlined, 'إدارة مهام التصوير', '/admin/photography-management'),
                  if (PermissionService.has(user, PermissionKeys.manageRequests))
                    _tile(Icons.assignment_outlined, 'طلبات العملاء', '/admin/requests'),
                ]),
                _section('المالية والتقارير', [
                  if (user?.isManager == true)
                    _tile(Icons.account_balance_wallet_outlined,
                        'واردات الشركة', '/admin/revenue'),
                  if (PermissionService.has(user, PermissionKeys.managePayments))
                    _tile(Icons.payments_outlined, 'المدفوعات', '/admin/payments', badge: _counts['pendingPayments'] ?? 0),
                  if (PermissionService.has(user, PermissionKeys.manageDeals))
                    _tile(Icons.handshake_outlined, 'الصفقات', '/admin/deals'),
                  if (PermissionService.has(user, PermissionKeys.manageReports))
                    _tile(Icons.flag_outlined, 'التبليغات', '/admin/reports', badge: _counts['openReports'] ?? 0),
                  if (PermissionService.has(user, PermissionKeys.viewAnalytics))
                    _tile(Icons.analytics_outlined, 'التحليلات', '/admin/analytics'),
                  if (PermissionService.has(user, PermissionKeys.resourceUsage))
                    _tile(Icons.cloud_queue_outlined, 'استهلاك السيرفر والتخزين', '/admin/resource-usage'),
                  if (PermissionService.has(user, PermissionKeys.manageConfig))
                    _tile(Icons.tune_outlined, 'الإعدادات', '/admin/config'),
                ]),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          ...children,
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, String route, {int badge = 0}) {
    return E2E(
      id: e2eRouteId(route),
      button: true,
      child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppTheme.primaryGold.withOpacity(0.12),
        child: Icon(icon, color: AppTheme.primaryGold),
      ),
      title: Text(title, style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
      trailing: badge > 0
          ? CircleAvatar(
              radius: 11,
              backgroundColor: AppTheme.errorRed,
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: AppTheme.fontSizeXS)),
            )
          : const Icon(Icons.chevron_left, color: AppTheme.textGrey),
      onTap: () => context.push(route),
      ),
    );
  }
}
