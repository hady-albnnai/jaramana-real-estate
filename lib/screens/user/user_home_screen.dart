import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../models/offer_model.dart';
import '../../providers/offer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/offer_filters.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/error_widget.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/services/permission_service.dart';

/// الشاشة الرئيسية للمستخدم بعد تسجيل الدخول
/// تحتوي على: بحث + فلتر + عروض + BottomNavigationBar
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final _searchCtrl = TextEditingController();
  int? _filterType; // null=الكل, 0=عقار, 1=سيارة
  int? _filterTrx;  // null=الكل, 0=بيع, 1=إيجار
  bool _isSearching = false;

  // 🎛️ الفلاتر المتقدمة — الودجت المشترك offer_filters.dart (معايير مطابقة الطلبات، 2026-07-27)
  final OfferFiltersData _advF = OfferFiltersData();

  // 🔒 Fix: نحتفظ بمرجع OfferProvider لاستخدامه في dispose بأمان
  OfferProvider? _offerProvRef;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final config = Provider.of<ConfigProvider>(context, listen: false);
      await config.loadConfig();
      if (!mounted) return;
      final offerProv = Provider.of<OfferProvider>(context, listen: false);
      _offerProvRef = offerProv; // حفظ المرجع
      offerProv.fetchOffers();
      offerProv.subscribeRealtime(); // تحديث فوري للعروض

      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.isLoggedIn) {
        final uid = auth.userModel?.uid ?? '';
        if (uid.isNotEmpty) {
          Provider.of<NotificationProvider>(context, listen: false)
              .fetchNotifications(uid);
        }
        final res = await auth.registerStreak(config.config);
        if (mounted && res['awarded'] == true) {
          AppUtils.showPointsAwarded(context, 50, label: 'نقطة دخول يومي');
        }
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _offerProvRef?.unsubscribeRealtime();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty && _filterType == null && _filterTrx == null) {
      await context.read<OfferProvider>().fetchOffers();
      if (mounted) setState(() => _isSearching = false);
      return;
    }
    setState(() => _isSearching = true);
    await context.read<OfferProvider>().searchOffers(
          query: query.isEmpty ? null : query,
          type: _filterType,
          transaction: _filterTrx,
        );
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _filterType = null;
      _filterTrx  = null;
      _isSearching = false;
    });
    context.read<OfferProvider>().fetchOffers();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final offerProv = Provider.of<OfferProvider>(context);
    final userName = auth.userModel?.nm ?? 'مستخدم';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مرحباً، $userName 👋',
              style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: AppTheme.fontSizeTitle,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'اكتشف عقارك المثالي 🏠',
              style: TextStyle(
                color: AppTheme.primaryGold.withOpacity(0.7),
                fontSize: AppTheme.fontSizeSmall,
              ),
            ),
          ],
        ),
        actions: [
          if (_roleShortcutRoute(auth) != null)
            IconButton(
              icon: Icon(_roleShortcutIcon(auth), color: AppTheme.primaryGold),
              tooltip: _roleShortcutTooltip(auth),
              onPressed: () => context.push(_roleShortcutRoute(auth)!),
            ),
          // أيقونة الإشعارات مع badge لعدد غير المقروء
          Consumer<NotificationProvider>(
            builder: (context, notif, _) {
              final count = notif.unreadCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none,
                        color: AppTheme.primaryGold),
                    onPressed: () => context.push('/user/notifications'),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: AppTheme.paddingAllSmall,
                        constraints:
                            const BoxConstraints(minWidth: 18, minHeight: 18),
                        decoration: const BoxDecoration(
                          color: AppTheme.errorRed,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppTheme.fontSizeXS,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // المفضلة — نقلت من الشريط السفلي لأيقونة هنا (إضافة عرض صارت بتبويب عروضي)
          IconButton(
            icon: const Icon(Icons.favorite_outline, color: AppTheme.primaryGold),
            tooltip: 'المفضلة',
            onPressed: () => context.push('/user/favorites'),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث + زر الفلاتر الظاهر (يفتح الفلاتر الكاملة — معايير مطابقة الطلبات)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: AppTheme.textWhite),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _doSearch(),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن عقار أو سيارة...',
                      prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGold),
                      suffixIcon: _searchCtrl.text.isNotEmpty || _isSearching
                          ? IconButton(
                              icon: const Icon(Icons.close, color: AppTheme.textGrey),
                              onPressed: _clearSearch,
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.surfaceBlack,
                      border: OutlineInputBorder(
                        borderRadius: AppTheme.radiusMedium,
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                AppTheme.gapWidthSmall,
                // زر «فلاتر» الذهبي المشترك — نفس الشكل عند الزائر والمستخدم
                OfferFiltersButton(count: _advF.activeCount, onTap: _openFilters),
              ],
            ),
          ),

          // ─── خدمات المكتب (استشارة قانونية + تصوير عقاري) ───
          if (!auth.isInternal)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              child: SizedBox(
                height: 85,
                child: Row(
                  children: [
                    Expanded(
                      child: _serviceTile(
                        context,
                        icon: Icons.gavel_rounded,
                        title: 'استشارة قانونية',
                        subtitle: '⚖️ من 500 ل.س',
                        route: '/legal/consultations',
                      ),
                    ),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: _serviceTile(
                        context,
                        icon: Icons.photo_camera_rounded,
                        title: 'تصوير عقاري',
                        subtitle: '📸 مصوّر محترف',
                        route: '/user/photography',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // فئات العروض (فلاتر متزامنة مع الجميع)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              children: [
                _buildChip('الكل', _filterType == null && _filterTrx == null, () {
                  setState(() { _filterType = null; _filterTrx = null; });
                  _doSearch();
                }),
                AppTheme.gapWidthSmall,
                _buildChip('🏠 عقار', _filterType == 0, () {
                  setState(() => _filterType = _filterType == 0 ? null : 0);
                  _doSearch();
                }),
                AppTheme.gapWidthSmall,
                _buildChip('🚗 سيارة', _filterType == 1, () {
                  setState(() => _filterType = _filterType == 1 ? null : 1);
                  _doSearch();
                }),
                AppTheme.gapWidthSmall,
                _buildChip('بيع', _filterTrx == 0, () {
                  setState(() => _filterTrx = _filterTrx == 0 ? null : 0);
                  _doSearch();
                }),
                AppTheme.gapWidthSmall,
                _buildChip('إيجار', _filterTrx == 1, () {
                  setState(() => _filterTrx = _filterTrx == 1 ? null : 1);
                  _doSearch();
                }),
              ],
            ),
          ),

          AppTheme.gapHeightSmall,

          // قائمة العروض
          // مؤشّر العمل دون اتصال
          if (offerProv.fromCache && offerProv.offers.isNotEmpty)
            Container(
              width: double.infinity,
              color: AppTheme.warningOrange.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Text('📡 وضع دون اتصال — عرض بيانات محفوظة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption)),
            ),
          Expanded(
            child: offerProv.isLoading && offerProv.offers.isEmpty
                ? ShimmerLoading.offerList()
                : (offerProv.error != null && offerProv.offers.isEmpty)
                    ? AppErrorWidget(
                        message: offerProv.error!,
                        onRetry: () => offerProv.fetchOffers(),
                      )
                    : offerProv.offers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.home_work,
                                    size: 80,
                                    color: AppTheme.textGrey.withOpacity(0.3)),
                                AppTheme.gapHeightXL,
                                const Text(
                                  'لا توجد عروض متاحة حالياً',
                                  style: TextStyle(
                                      color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle),
                                ),
                                AppTheme.gapHeightXL,
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      context.push('/user/add-offer'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('أضف أول عرض لك'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => offerProv.fetchOffers(),
                            color: AppTheme.primaryGold,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 15),
                              itemCount:
                                  _advF.apply(offerProv.offers).length,
                              itemBuilder: (context, index) {
                                final offer =
                                    _advF.apply(offerProv.offers)[index];
                                return OfferCard(offer: offer);
                              },
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 0),
    );
  }


  String? _roleShortcutRoute(AuthProvider auth) {
    final user = auth.userModel;
    if (user == null) return null;
    if (user.isSenior) return '/admin/dashboard';
    if (user.isEmployee) return '/employee/home';
    if (user.isSupervisor) return '/executor/tasks';
    if (PermissionService.has(user, PermissionKeys.photographerTasks)) {
      return '/photographer/tasks';
    }
    if (user.isPhotographer) return '/photographer/tasks';
    if (user.isBroker || user.role == UserRole.broker) return '/broker/dashboard';
    return null;
  }

  IconData _roleShortcutIcon(AuthProvider auth) {
    final route = _roleShortcutRoute(auth);
    if (route == '/admin/dashboard') return Icons.admin_panel_settings_outlined;
    if (route == '/photographer/tasks') return Icons.camera_alt_outlined;
    if (route == '/broker/dashboard') return Icons.handshake_outlined;
    return Icons.dashboard_outlined;
  }

  String _roleShortcutTooltip(AuthProvider auth) {
    final route = _roleShortcutRoute(auth);
    if (route == '/admin/dashboard') return 'لوحة الإدارة';
    if (route == '/photographer/tasks') return 'مهام المصور';
    if (route == '/broker/dashboard') return 'لوحة الوسيط';
    return 'لوحتي';
  }

  // 🎛️ التصفية المحلية — نفس منطق شاشة «العروض المطابقة» للطلبات حرفياً
  // 🎛️ فتح نافذة الفلاتر الكاملة (الودجت المشترك) — مصادر التصنيفات من ConfigProvider
  void _openFilters() {
    final data = (context.read<ConfigProvider>().config?.data ?? <String, dynamic>{});
    showOfferFiltersSheet(
      context,
      f: _advF,
      showProp: _filterType != 1, // عقارات: كل الأنواع أو عقار
      showCar:  _filterType != 0, // سيارات: كل الأنواع أو سيارة
      catPropSrc: (data['catProp'] ?? <String, dynamic>{}) as Map<String, dynamic>,
      docTpSrc:   (data['docTp']   ?? <String, dynamic>{}) as Map<String, dynamic>,
      carDocTpSrc:(data['carDocTp']?? <String, dynamic>{}) as Map<String, dynamic>,
      onChanged: () { if (mounted) setState(() {}); },
    );
  }

  Widget _serviceTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required String route}) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Container(
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryGold.withOpacity(0.15),
              AppTheme.surfaceBlack,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppTheme.radiusLarge,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryGold, size: 28),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeBody,
                          fontWeight: FontWeight.bold)),
                  AppTheme.gapHeightXXS,
                  Text(subtitle,
                      style: TextStyle(
                          color: AppTheme.primaryGold.withOpacity(0.7),
                          fontSize: AppTheme.fontSizeCaption)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return FilterChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.deepBlack : AppTheme.textWhite,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          fontSize: AppTheme.fontSizeSmall,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.primaryGold,
      backgroundColor: AppTheme.surfaceBlack,
      checkmarkColor: AppTheme.deepBlack,
      side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.45)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (_) => onTap(),
    );
  }
}

