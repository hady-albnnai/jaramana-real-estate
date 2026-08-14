import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/permission_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/executor_provider.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/fit_tile.dart';

/// الشاشة الرئيسية لموظف المكتب — تجمع عمليات المكتب اليومية
class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  int _pendingCompletions = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isNotEmpty) {
      final pending = await context.read<ExecutorProvider>().getPendingRequests(uid);
      if (mounted) {
        setState(() {
          _pendingCompletions = pending.length;
          _loading = false;
        });
      }
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: Column(
          children: [
            const Text('المكتب العقاري',
                style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.bold)),
            Text(user?.nm ?? 'موظف المكتب',
                style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppTheme.primaryGold),
            onPressed: () => context.push('/user/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _loadCounts,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: _loadCounts,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = AppTheme.getMaxContentWidth(context);
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: ListView(
                        padding: AppTheme.responsivePadding(
                          context,
                          mobile: AppTheme.paddingAllMedium,
                          tablet: AppTheme.paddingAllLarge,
                          desktop: AppTheme.paddingAllXL,
                        ),
                        children: [
                  // ─── العمليات الأساسية ───
                  _sectionTitle('العمليات اليومية'),
                  AppTheme.gapHeightSmall,
                  _buildGrid([
                    if (PermissionService.has(user, PermissionKeys.reviewOffers))
                      _item(Icons.fact_check_outlined, 'مراجعة العروض', '/admin/review-offers', AppTheme.infoBlue),
                    if (PermissionService.has(user, PermissionKeys.manageAppointments))
                      _item(Icons.calendar_month_outlined, 'المواعيد', '/admin/appointments', Colors.teal),
                    if (PermissionService.has(user, PermissionKeys.manageRequests))
                      _item(Icons.assignment_outlined, 'طلبات الزبائن', '/admin/requests', AppTheme.warningOrange),
                    if (PermissionService.has(user, PermissionKeys.completionRequests))
                      _item(Icons.assignment_turned_in_outlined, 'طلبات الإتمام', '/admin/completion-requests', AppTheme.successGreen,
                          badge: _pendingCompletions),
                  ]),

                  AppTheme.gapHeightXL,

                  // ─── التصوير والوسائط ───
                  _sectionTitle('التصوير والوسائط'),
                  AppTheme.gapHeightSmall,
                  _buildGrid([
                    if (PermissionService.has(user, PermissionKeys.photographyManagement))
                      _item(Icons.add_a_photo_outlined, 'مهام التصوير', '/admin/photography-management', Colors.cyan),
                    if (PermissionService.has(user, PermissionKeys.mediaReview))
                      _item(Icons.photo_library_outlined, 'إدارة الوسائط', '/admin/media-review', Colors.brown),
                  ]),

                  AppTheme.gapHeightXL,

                  // ─── المستخدمين والتوثيق ───
                  _sectionTitle('المستخدمين'),
                  AppTheme.gapHeightSmall,
                  _buildGrid([
                    if (PermissionService.has(user, PermissionKeys.manageUsers))
                      _item(Icons.people_outline, 'المستخدمون', '/admin/users', Colors.blueGrey),
                    if (PermissionService.has(user, PermissionKeys.reviewVerifications))
                      _item(Icons.verified_user_outlined, 'طلبات التوثيق', '/admin/review-verifications', Colors.amber),
                    if (PermissionService.has(user, PermissionKeys.fraudSuspects))
                      _item(Icons.security_outlined, 'كشف الاحتيال', '/admin/fraud-suspects', AppTheme.errorRed),
                  ]),

                  AppTheme.gapHeightXL,

                  // ─── إضافة عرض ───
                  if (PermissionService.has(user, PermissionKeys.addOfferAdmin))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () => context.push('/admin/add-offer'),
                          icon: const Icon(Icons.add_home_work),
                          label: const Text('إضافة عرض جديد', style: TextStyle(fontSize: AppTheme.fontSizeSubtitle)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryGold,
                            foregroundColor: AppTheme.deepBlack,
                            shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
                          ),
                        ),
                      ),
                    ),

                  AppTheme.gapHeightSmall,

                  // ─── رابط للوحة الإدارة الكاملة ───
                  if (user != null && user.isSenior)
                    TextButton.icon(
                      onPressed: () => context.push('/admin/dashboard'),
                      icon: const Icon(Icons.admin_panel_settings, color: AppTheme.textGrey),
                      label: const Text('لوحة الإدارة الكاملة',
                          style: TextStyle(color: AppTheme.textGrey)),
                    ),

                  const SizedBox(height: 30),
                ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold));
  }

  Widget _buildGrid(List<_MenuItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppTheme.getGridColumns(
          context,
          mobile: 2,
          tablet: 3,
          desktop: 4,
        ),
        mainAxisSpacing: AppTheme.spacingSmall,
        crossAxisSpacing: AppTheme.spacingSmall,
        childAspectRatio: AppTheme.responsiveValue(
          context,
          mobile: 1.6,
          tablet: 1.8,
          desktop: 2.0,
        ),
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _card(items[index]),
    );
  }

  Widget _card(_MenuItem item) {
    return GestureDetector(
      onTap: () => context.push(item.route),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusLarge,
          border: Border.all(color: item.color.withOpacity(0.25)),
        ),
        padding: AppTheme.paddingAllLarge,
        child: // 🧱 UI-OVF-001: محتوى بارتفاع بكسلي ثابت داخل شبكة بنسبة أبعاد ثابتة.
               FitTile(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(item.icon, color: item.color, size: 24),
              if (item.badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed,
                    borderRadius: AppTheme.radiusMedium,
                  ),
                  child: Text('${item.badge}',
                      style: const TextStyle(color: Colors.white, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            AppTheme.gapHeightSmall,
            Text(item.title,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody, fontWeight: FontWeight.w600)),
          ],
        )),
      ),
    );
  }

  _MenuItem _item(IconData icon, String title, String route, Color color, {int badge = 0}) {
    return _MenuItem(icon: icon, title: title, route: route, color: color, badge: badge);
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String route;
  final Color color;
  final int badge;

  _MenuItem({required this.icon, required this.title, required this.route, required this.color, this.badge = 0});
}
