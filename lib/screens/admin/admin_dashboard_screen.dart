import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/e2e.dart';
import '../../widgets/fit_tile.dart';

/// 🛡️ لوحة الإدارة الرئيسية
/// تعرض: إحصائيات عامة + عدّادات الإجراءات المطلوبة + شبكة تنقّل للأقسام
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _stats = {};
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final stats = await admin.getStats(adminUid);
    final counts = await admin.getActionCounts(adminUid);
    if (mounted) {
      setState(() {
        _stats = stats;
        _counts = counts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.userModel?.nm ?? 'المدير';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: E2E(
          id: 'e2e_screen_admin_dashboard',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('لوحة الإدارة',
                  style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: AppTheme.fontSizeTitle,
                      fontWeight: FontWeight.bold)),
              Text('أهلاً، $name 🛡️',
                  style: TextStyle(
                      color: AppTheme.primaryGold.withOpacity(0.8),
                      fontSize: AppTheme.fontSizeSmall)),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined, color: AppTheme.primaryGold),
            tooltip: 'الواجهة الرئيسية',
            onPressed: () => context.go('/user/home'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: _load,
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
                          // ── تنبيهات الإجراءات المطلوبة ──
                          if (_totalActions() > 0) _actionsBanner(),

                          // ── إحصائيات عامة ──
                          AppTheme.gapHeightXS,
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
                              mainAxisSpacing: AppTheme.spacingSmall,
                              crossAxisSpacing: AppTheme.spacingSmall,
                              childAspectRatio: AppTheme.responsiveValue(
                                context,
                                mobile: 1.8,
                                tablet: 2.0,
                                desktop: 2.2,
                              ),
                            ),
                            itemCount: 4,
                            itemBuilder: (context, index) {
                              switch (index) {
                                case 0:
                                  return _statCard('👥', 'المستخدمون',
                                      '${_stats['totalUsers'] ?? 0}',
                                      'نشط: ${_stats['activeUsers'] ?? 0}');
                                case 1:
                                  return _statCard('🏠', 'العروض',
                                      '${_stats['totalOffers'] ?? 0}',
                                      'منشور: ${_stats['publishedOffers'] ?? 0}');
                                case 2:
                                  return _statCard('🤝', 'الصفقات',
                                      '${_stats['totalDeals'] ?? 0}',
                                      'مكتمل: ${_stats['completedDeals'] ?? 0}');
                                case 3:
                                  return _statCard('💰', 'العمولات',
                                      _fmt(_stats['totalCommission']),
                                      'إجمالي محقّق');
                                default:
                                  return const SizedBox.shrink();
                              }
                            },
                          ),

                          AppTheme.gapHeightXXL,
                          Text('الإدارة',
                              style: TextStyle(
                                  color: AppTheme.primaryGold,
                                  fontSize: AppTheme.responsiveFontSize(
                                    context,
                                    mobile: AppTheme.fontSizeSubtitle,
                                    tablet: AppTheme.fontSizeTitle,
                                  ),
                                  fontWeight: FontWeight.bold)),
                          AppTheme.gapHeightMedium,

                          // ── مدخل الأقسام ──
                          _actionCard(
                            Icons.apps_outlined,
                            'أقسام الإدارة',
                            'المراجعات · العمليات · المالية · الإعدادات',
                            () => context.push('/admin/sections'),
                          ),
                          AppTheme.gapHeightXL,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  int _totalActions() =>
      (_counts['pendingOffers'] ?? 0) +
      (_counts['pendingPayments'] ?? 0) +
      (_counts['openReports'] ?? 0) +
      (_counts['pendingVerifications'] ?? 0);

  Widget _actionsBanner() {
    return Container(
      margin: EdgeInsets.only(bottom: AppTheme.spacingXL),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withOpacity(0.12),
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.errorRed.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notification_important, color: AppTheme.errorRed),
          AppTheme.gapWidthMedium,
          Expanded(
            child: Text(
              'لديك ${_totalActions()} عنصر بانتظار الإجراء '
              '(${_counts['pendingOffers'] ?? 0} عرض · '
              '${_counts['pendingPayments'] ?? 0} دفعة · '
              '${_counts['openReports'] ?? 0} تبليغ · '
              '${_counts['pendingVerifications'] ?? 0} توثيق)',
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: AppTheme.fontSizeBody),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(dynamic v) {
    final n = (v ?? 0) as num;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}م';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}ألف';
    return n.toStringAsFixed(0);
  }

  Widget _statCard(String emoji, String label, String value, String sub) {
    return Container(
      padding: AppTheme.responsivePadding(
        context,
        mobile: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tablet: AppTheme.paddingAllMedium,
        desktop: AppTheme.paddingAllLarge,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
      ),
      child: // 🧱 UI-OVF-001: بطاقة إحصاء بارتفاع بكسلي ثابت داخل شبكة بنسبة ثابتة.
             FitTile(child: Row(
        children: [
          Text(emoji,
              style: TextStyle(
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeHeadline,
                  tablet: AppTheme.fontSizeLarge,
                ),
              )),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: AppTheme.responsiveFontSize(
                        context,
                        mobile: AppTheme.fontSizeCaption,
                        tablet: AppTheme.fontSizeSmall,
                      ),
                    )),
                AppTheme.gapHeightXXS,
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.primaryGold,
                        fontSize: AppTheme.responsiveFontSize(
                          context,
                          mobile: AppTheme.fontSizeTitle,
                          tablet: AppTheme.fontSizeHeadline,
                        ),
                        fontWeight: FontWeight.bold)),
                AppTheme.gapHeightXXS,
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: AppTheme.responsiveFontSize(
                        context,
                        mobile: 9,
                        tablet: AppTheme.fontSizeCaption,
                      ),
                    )),
              ],
            ),
          ),
        ],
      )),
    );
  }

  Widget _actionCard(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusLarge,
      child: Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusLarge,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primaryGold, size: 34),
            AppTheme.gapHeightSmall,
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textWhite,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeBody,
                  tablet: AppTheme.fontSizeMedium,
                ),
                fontWeight: FontWeight.w600,
              ),
            ),
            AppTheme.gapHeightXS,
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeXS,
                  tablet: AppTheme.fontSizeCaption,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
