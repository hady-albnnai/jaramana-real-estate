import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/fit_tile.dart';

/// داشبورد نائب المدير (role = 5)
class DeputyDashboardScreen extends StatelessWidget {
  const DeputyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;
    final name = user?.nm ?? 'نائب المدير';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: AppTheme.scaffoldBackground,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لوحة نائب المدير',
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeTitle)),
            Text('أهلاً، $name',
                style: const TextStyle(
                    color: AppTheme.primaryGold,
                    fontSize: AppTheme.fontSizeSmall)),
          ],
        ),
        actions: [
          if (PermissionService.has(user, PermissionKeys.manageStaff))
            IconButton(
              icon: const Icon(Icons.people, color: AppTheme.primaryGold),
              onPressed: () => context.push('/admin/employee-management'),
              tooltip: 'إدارة الموظفين',
            ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: user == null
            ? Future.value({})
            : context.read<AdminProvider>().getStaffStatsInternal(user.uid),
        builder: (context, snapshot) {
          final stats = snapshot.data ?? {};
          final loading = snapshot.connectionState == ConnectionState.waiting;

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = AppTheme.getMaxContentWidth(context);
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: SingleChildScrollView(
                    padding: AppTheme.responsivePadding(
                      context,
                      mobile: AppTheme.paddingAllMedium,
                      tablet: AppTheme.paddingAllLarge,
                      desktop: AppTheme.paddingAllXL,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('نظرة عامة',
                            style: TextStyle(
                                color: AppTheme.primaryGold,
                                fontSize: AppTheme.responsiveFontSize(
                                  context,
                                  mobile: AppTheme.fontSizeSubtitle,
                                  tablet: AppTheme.fontSizeTitle,
                                ),
                                fontWeight: FontWeight.bold)),
                        AppTheme.gapHeightMedium,
                        if (loading)
                          const Center(
                              child: CircularProgressIndicator(
                                  color: AppTheme.primaryGold))
                        else ...[
                          // شبكة الإحصائيات المتجاوبة
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: AppTheme.getGridColumns(
                                context,
                                mobile: 2,
                                tablet: 2,
                                desktop: 4,
                              ),
                              mainAxisSpacing: AppTheme.spacingMedium,
                              crossAxisSpacing: AppTheme.spacingMedium,
                              childAspectRatio: AppTheme.responsiveValue(
                                context,
                                mobile: 1.4,
                                tablet: 1.6,
                                desktop: 1.8,
                              ),
                            ),
                            itemCount: 4,
                            itemBuilder: (context, index) {
                              switch (index) {
                                case 0:
                                  return _statCard(
                                      context,
                                      '👥',
                                      'المستخدمون',
                                      _value(stats['total_users']),
                                      'إجمالي الحسابات');
                                case 1:
                                  return _statCard(
                                      context,
                                      '🏠',
                                      'العروض النشطة',
                                      _value(stats['active_offers']),
                                      'منشورة حالياً');
                                case 2:
                                  return _statCard(
                                      context,
                                      '💰',
                                      'دفعات معلقة',
                                      _value(stats['pending_payments']),
                                      'بانتظار الموافقة');
                                case 3:
                                  return _statCard(
                                      context,
                                      '✅',
                                      'توثيقات معلقة',
                                      _value(stats['pending_verifications']),
                                      'قيد المراجعة');
                                default:
                                  return const SizedBox.shrink();
                              }
                            },
                          ),
                        ],
                        AppTheme.gapHeightXXL,
                        Text('الوصول السريع',
                            style: TextStyle(
                                color: AppTheme.primaryGold,
                                fontSize: AppTheme.responsiveFontSize(
                                  context,
                                  mobile: AppTheme.fontSizeSubtitle,
                                  tablet: AppTheme.fontSizeTitle,
                                ),
                                fontWeight: FontWeight.bold)),
                        AppTheme.gapHeightMedium,
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: AppTheme.getGridColumns(
                              context,
                              mobile: 2,
                              tablet: 3,
                              desktop: 4,
                            ),
                            mainAxisSpacing: AppTheme.spacingMedium,
                            crossAxisSpacing: AppTheme.spacingMedium,
                            childAspectRatio: AppTheme.responsiveValue(
                              context,
                              mobile: 1.6,
                              tablet: 1.8,
                              desktop: 2.0,
                            ),
                          ),
                          itemCount: _getNavItems(user).length,
                          itemBuilder: (context, index) {
                            final item = _getNavItems(user)[index];
                            return _navCard(
                                context, item['icon'], item['title'], item['route']);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _getNavItems(dynamic user) {
    final items = <Map<String, dynamic>>[];
    if (PermissionService.has(user, PermissionKeys.manageStaff)) {
      items.add({
        'icon': Icons.people,
        'title': 'إدارة الموظفين',
        'route': '/admin/employee-management'
      });
    }
    if (PermissionService.has(user, PermissionKeys.reviewOffers)) {
      items.add({
        'icon': Icons.fact_check,
        'title': 'مراجعة العروض',
        'route': '/admin/review-offers'
      });
    }
    if (PermissionService.has(user, PermissionKeys.manageAppointments)) {
      items.add({
        'icon': Icons.calendar_month,
        'title': 'المواعيد',
        'route': '/admin/appointments'
      });
    }
    if (PermissionService.has(user, PermissionKeys.managePayments)) {
      items.add({
        'icon': Icons.payments,
        'title': 'المدفوعات',
        'route': '/admin/payments'
      });
    }
    if (PermissionService.has(user, PermissionKeys.completionRequests)) {
      items.add({
        'icon': Icons.assignment_turned_in,
        'title': 'طلبات الإتمام',
        'route': '/admin/completion-requests'
      });
    }
    if (PermissionService.has(user, PermissionKeys.reviewVerifications)) {
      items.add({
        'icon': Icons.verified_user,
        'title': 'طلبات التوثيق',
        'route': '/admin/review-verifications'
      });
    }
    return items;
  }

  String _value(dynamic value) => (value ?? 0).toString();

  Widget _statCard(
      BuildContext context, String emoji, String label, String value, String sub) {
    return Container(
      padding: AppTheme.responsivePadding(
        context,
        mobile: AppTheme.paddingAllMedium,
        tablet: AppTheme.paddingAllLarge,
        desktop: AppTheme.paddingAllLarge,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.2)),
      ),
      child: // 🧱 UI-OVF-001: محتوى بارتفاع بكسلي ثابت داخل شبكة بنسبة أبعاد ثابتة.
             FitTile(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji,
              style: TextStyle(
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeHeadline,
                  tablet: AppTheme.fontSizeLarge,
                ),
              )),
          AppTheme.gapHeightSmall,
          Text(label,
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeSmall,
                  tablet: AppTheme.fontSizeBody,
                ),
              )),
          Text(value,
              style: TextStyle(
                color: AppTheme.primaryGold,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeHeadline,
                  tablet: AppTheme.fontSizeLarge,
                  desktop: AppTheme.fontSizeXL,
                ),
                fontWeight: FontWeight.bold,
              )),
          Text(sub,
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeCaption,
                  tablet: AppTheme.fontSizeSmall,
                ),
              )),
        ],
      )),
    );
  }

  Widget _navCard(
      BuildContext context, IconData icon, String title, String route) {
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: AppTheme.radiusLarge,
      child: Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusLarge,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
        ),
        child: // 🧱 UI-OVF-001: محتوى بارتفاع بكسلي ثابت داخل شبكة بنسبة أبعاد ثابتة.
               FitTile(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primaryGold, size: 30),
            AppTheme.gapHeightSmall,
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: AppTheme.responsiveFontSize(
                    context,
                    mobile: AppTheme.fontSizeBody,
                    tablet: AppTheme.fontSizeMedium,
                  ),
                )),
          ],
        )),
      ),
    );
  }
}
