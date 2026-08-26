import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/broker_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/fit_tile.dart';
import '../../widgets/guide_anchor.dart';
import '../../core/guide/guide_help_button.dart';
import '../../core/guide/guide_host.dart';
import '../../core/guide/guide_models.dart';
import '../../core/guide/broker_guide_coordinator.dart';

/// 🤝 لوحة تحكم الوسيط/السمسار — الشاشة الرئيسية
/// تعرض: ترحيب + إحصائيات سريعة + بطاقات تنقل للأقسام
class BrokerDashboardScreen extends StatefulWidget {
  const BrokerDashboardScreen({super.key});

  @override
  State<BrokerDashboardScreen> createState() => _BrokerDashboardScreenState();
}

class _BrokerDashboardScreenState extends State<BrokerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _load();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) await BrokerGuideCoordinator.maybeStart(context);
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final id = auth.userModel?.uid ?? '';
    if (id.isNotEmpty) {
      await context.read<BrokerProvider>().fetchBrokerStats(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final broker = context.watch<BrokerProvider>();
    final name = auth.userModel?.brkNm.isNotEmpty == true
        ? auth.userModel!.brkNm
        : (auth.userModel?.nm ?? 'الوسيط');
    final stats = broker.stats;
    final guideRegistry = GuideHost.maybeRegistryOf(context);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لوحة الوسيط',
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeTitle,
                    fontWeight: FontWeight.bold)),
            Text('أهلاً، $name 🤝',
                style: TextStyle(
                    color: AppTheme.primaryGold.withOpacity(0.8), fontSize: AppTheme.fontSizeSmall)),
          ],
        ),
        actions: [
          GuideHelpButton(
            scope: GuideScope.broker,
            uid: auth.userModel?.uid ?? '',
            onPressed: () => BrokerGuideCoordinator.maybeStart(context, force: true),
          ),
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
      body: RefreshIndicator(
        color: AppTheme.primaryGold,
        onRefresh: _load,
        child: broker.isLoading && stats.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGold))
            : LayoutBuilder(
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
                          // ── شبكة الإحصائيات ──
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
                              mainAxisSpacing: AppTheme.spacingMedium,
                              crossAxisSpacing: AppTheme.spacingMedium,
                              childAspectRatio: AppTheme.responsiveValue(
                                context,
                                mobile: 2.3,
                                tablet: 2.4,
                                desktop: 2.5,
                              ),
                            ),
                            itemCount: 4,
                            itemBuilder: (context, index) {
                              switch (index) {
                                case 0:
                                  return _statCard('🏠', 'العروض',
                                      '${stats['totalOffers'] ?? 0}', 'منشور: ${stats['publishedOffers'] ?? 0}');
                                case 1:
                                  return _statCard('📅', 'المواعيد',
                                      '${stats['totalAppointments'] ?? 0}', 'مكتمل: ${stats['completedAppointments'] ?? 0}');
                                case 2:
                                  return _statCard('🤝', 'الصفقات',
                                      '${stats['totalDeals'] ?? 0}', 'مكتمل: ${stats['completedDeals'] ?? 0}');
                                case 3:
                                  return _statCard('💰', 'العمولات',
                                      _fmt(stats['totalCommission']), 'إجمالي محقّق');
                                default:
                                  return const SizedBox.shrink();
                              }
                            },
                          ),
                          AppTheme.gapHeightXXL,
                          if (guideRegistry != null)
                            GuideAnchor(
                              id: GuideStepIds.brokerSections,
                              registry: guideRegistry,
                              child: Text('الأقسام',
                                  style: TextStyle(
                                      color: AppTheme.primaryGold,
                                      fontSize: AppTheme.responsiveFontSize(
                                        context,
                                        mobile: AppTheme.fontSizeSubtitle,
                                        tablet: AppTheme.fontSizeTitle,
                                        desktop: AppTheme.fontSizeHeadline,
                                      ),
                                      fontWeight: FontWeight.bold)))
                          else
                            Text('الأقسام',
                                style: TextStyle(
                                    color: AppTheme.primaryGold,
                                    fontSize: AppTheme.responsiveFontSize(
                                      context,
                                      mobile: AppTheme.fontSizeSubtitle,
                                      tablet: AppTheme.fontSizeTitle,
                                      desktop: AppTheme.fontSizeHeadline,
                                    ),
                                    fontWeight: FontWeight.bold)),
                          AppTheme.gapHeightMedium,

                          // ── بطاقات التنقل ──
                          // 🏠 BUG-003 (أُصلح 2026-08-14): '/broker/offers'
                          // كان مسجَّلاً بالراوتر وله صلاحية brokerOffers
                          // **بلا أي زر يفتحه** — الوسيط لا يصل إلى عروضه
                          // إطلاقاً من لوحته.
                          _navTile(
                            icon: Icons.home_work_outlined,
                            title: 'عروضي',
                            subtitle: 'إدارة العروض المسندة إليك',
                            onTap: () => context.push('/broker/offers'),
                          ),
                          _navTile(
                            icon: Icons.calendar_today_outlined,
                            title: 'طلبات المعاينة',
                            subtitle: 'قبول ورفض مواعيد المعاينة',
                            onTap: () => context.push('/broker/appointments'),
                          ),
                          _navTile(
                            icon: Icons.handshake_outlined,
                            title: 'الصفقات',
                            subtitle: 'الصفقات النشطة والمكتملة',
                            onTap: () => context.push('/broker/deals'),
                          ),
                          _navTile(
                            icon: Icons.bar_chart_outlined,
                            title: 'الإحصائيات',
                            subtitle: 'تقارير الأداء التفصيلية',
                            onTap: () => context.push('/broker/stats'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
        mobile: const EdgeInsets.all(10),
        tablet: AppTheme.paddingAllLarge,
        desktop: AppTheme.paddingAllLarge,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
      ),
      child: // 🧱 UI-OVF-001: محتوى بارتفاع بكسلي ثابت داخل شبكة بنسبة أبعاد ثابتة.
             FitTile(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.responsiveFontSize(
                          context,
                          mobile: AppTheme.fontSizeXS,
                          tablet: AppTheme.fontSizeBody,
                        ))),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppTheme.primaryGold,
                  fontSize: AppTheme.responsiveFontSize(
                    context,
                    mobile: AppTheme.fontSizeTitle,
                    tablet: AppTheme.fontSizeLarge,
                    desktop: AppTheme.fontSizeXL,
                  ),
                  fontWeight: FontWeight.bold)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeXS,
                  tablet: AppTheme.fontSizeCaption,
                ),
              )),
        ],
      )),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryGold.withOpacity(0.15),
          child: Icon(icon, color: AppTheme.primaryGold),
        ),
        title: Text(title,
            style: TextStyle(
                color: AppTheme.textWhite,
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.responsiveFontSize(
                  context,
                  mobile: AppTheme.fontSizeBody,
                  tablet: AppTheme.fontSizeMedium,
                ))),
        subtitle: Text(subtitle,
            style: TextStyle(
              color: AppTheme.textGrey,
              fontSize: AppTheme.responsiveFontSize(
                context,
                mobile: AppTheme.fontSizeSmall,
                tablet: AppTheme.fontSizeBody,
              ),
            )),
        trailing: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold, size: 16),
        onTap: onTap,
      ),
    );
  }
}
