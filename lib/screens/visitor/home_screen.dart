import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/offer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/offer_filters.dart';
import '../../widgets/shimmer_loading.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/e2e.dart';
import '../../widgets/guide_anchor.dart';
import '../../core/guide/guide_host.dart';
import '../../core/guide/guide_models.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  int? _filterType; // null=الكل, 0=عقار, 1=سيارة
  int? _filterTrx;  // null=الكل, 0=بيع, 1=إيجار
  bool _isSearching = false;

  // 🎛️ الفلاتر المتقدمة — الودجت المشترك offer_filters.dart (نفس معايير شاشة المستخدم)
  final OfferFiltersData _advF = OfferFiltersData();

  @override
  void initState() {
    super.initState();
    // FIX 6: استدعاء fetchOffers عند أول تحميل للزائر
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final offerProv = context.read<OfferProvider>();
      if (offerProv.offers.isEmpty) {
        offerProv.fetchOffers();
      }
      // مصادر تصنيفات الفلاتر (catProp/docTp/carDocTp) — لازمة لقوائم نافذة الفلاتر
      context.read<ConfigProvider>().loadConfig();
    });
  }

  // 🎛️ فتح نافذة الفلاتر الكاملة (الودجت المشترك)
  void _openFilters() {
    final data = (context.read<ConfigProvider>().config?.data ?? <String, dynamic>{});
    showOfferFiltersSheet(
      context,
      f: _advF,
      showProp: _filterType != 1,
      showCar:  _filterType != 0,
      catPropSrc: (data['catProp'] ?? <String, dynamic>{}) as Map<String, dynamic>,
      docTpSrc:   (data['docTp']   ?? <String, dynamic>{}) as Map<String, dynamic>,
      carDocTpSrc:(data['carDocTp']?? <String, dynamic>{}) as Map<String, dynamic>,
      onChanged: () { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty && _filterType == null && _filterTrx == null) {
      // بدون فلاتر → اعرض الكل
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
    final offerProvider = context.watch<OfferProvider>();
    final auth = context.watch<AuthProvider>();
    final guideRegistry = GuideHost.maybeRegistryOf(context);
    // القائمة المرئية = عروض المزوّد بعد تطبيق الفلاتر المتقدمة (المشتركة)
    final offers = _advF.apply(offerProvider.offers);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('المكتب العقاري الالكتروني',
            style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppTheme.textGrey),
            onPressed: () {
              if (!auth.isLoggedIn) {
                AppTheme.showSnackBar(context, SnackBar(
                  content: const Text('سجّل دخولك لرؤية الإشعارات'),
                  action: SnackBarAction(
                      label: 'دخول',
                      onPressed: () => context.push('/login')),
                ));
              } else {
                context.push('/user/notifications');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppTheme.textGrey),
            onPressed: () => context.push('/user/profile'),
          ),
        ],
      ),
      body: Column(children: [
        // ── شريط البحث + زر الفلاتر الذهبي (المشترك مع شاشة المستخدم) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 0),
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
                    hintStyle: const TextStyle(color: AppTheme.textGrey),
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
              if (guideRegistry != null)
                GuideAnchor(
                  id: GuideStepIds.visitorFilters,
                  registry: guideRegistry,
                  child: OfferFiltersButton(
                    count: _advF.activeCount,
                    onTap: _openFilters,
                  ),
                )
              else
                OfferFiltersButton(count: _advF.activeCount, onTap: _openFilters),
            ],
          ),
        ),

        // ── الشرائح (FIX 4: تعمل وتفلتر) ──
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
            children: [
              _chip('الكل',    _filterType == null && _filterTrx == null,
                  () { setState(() { _filterType = null; _filterTrx = null; }); _doSearch(); }),
              AppTheme.gapWidthSmall,
              _chip('🏠 عقار', _filterType == 0,
                  () { setState(() => _filterType = _filterType == 0 ? null : 0); _doSearch(); }),
              AppTheme.gapWidthSmall,
              _chip('🚗 سيارة', _filterType == 1,
                  () { setState(() => _filterType = _filterType == 1 ? null : 1); _doSearch(); }),
              AppTheme.gapWidthSmall,
              _chip('بيع',    _filterTrx == 0,
                  () { setState(() => _filterTrx = _filterTrx == 0 ? null : 0); _doSearch(); }),
              AppTheme.gapWidthSmall,
              _chip('إيجار',  _filterTrx == 1,
                  () { setState(() => _filterTrx = _filterTrx == 1 ? null : 1); _doSearch(); }),
            ],
          ),
        ),

        // ── القائمة ──
        // عداد النتائج عند الفلترة (نصية أو متقدمة)
        if ((_isSearching || _advF.activeCount > 0) && !offerProvider.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '${offers.length} نتيجة',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
            ),
          ),

        Expanded(
          child: offerProvider.isLoading && offerProvider.offers.isEmpty
              // Shimmer بدل الدوامة
              ? SingleChildScrollView(child: ShimmerLoading.offerList())
              : offerProvider.offers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.home_work_outlined,
                              size: 80,
                              color: AppTheme.textGrey.withOpacity(0.3)),
                          AppTheme.gapHeightLarge,
                          Text(
                            _isSearching
                                ? 'لا توجد نتائج مطابقة'
                                : 'لا توجد عروض متاحة حالياً',
                            style: const TextStyle(
                                color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
                          if (_isSearching) ...[
                            AppTheme.gapHeightSmall,
                            TextButton(
                              onPressed: _clearSearch,
                              child: const Text('إلغاء الفلتر',
                                  style: TextStyle(color: AppTheme.primaryGold)),
                            ),
                          ],
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primaryGold,
                      onRefresh: () => context.read<OfferProvider>().fetchOffers(),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (sn) {
                          if (sn.metrics.pixels >=
                                  sn.metrics.maxScrollExtent - 200 &&
                              offerProvider.hasMore &&
                              !offerProvider.loadingMore) {
                            offerProvider.loadMoreOffers();
                          }
                          return false;
                        },
                        child: guideRegistry != null
                            ? GuideAnchor(
                                id: GuideStepIds.visitorOffers,
                                registry: guideRegistry,
                                child: _buildVisitorOffersList(offers, offerProvider),
                              )
                            : _buildVisitorOffersList(offers, offerProvider),
                      ),
                    ),
        ),
      ]),

      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.scaffoldBackground,
        selectedItemColor: AppTheme.primaryGold,
        unselectedItemColor: AppTheme.textGrey,
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_home', button: true, child: Icon(Icons.home)), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_search', button: true, child: Icon(Icons.search)), label: 'بحث'),
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_favorites', button: true, child: Icon(Icons.favorite)), label: 'المفضلة'),
          BottomNavigationBarItem(icon: E2E(id: 'e2e_nav_profile', button: true, child: Icon(Icons.person)), label: 'حسابي'),
        ],
        onTap: (index) {
          if (index == 1) context.push('/search');
          if (index == 2) context.push('/user/favorites');
          if (index == 3) context.push('/user/profile');
        },
      ),
    );
  }

  Widget _buildVisitorOffersList(
      List<dynamic> offers, OfferProvider offerProvider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      itemCount: offers.length + (offerProvider.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= offers.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold),
            ),
          );
        }
        return OfferCard(offer: offers[index]);
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label,
          style: TextStyle(
            color: selected ? AppTheme.deepBlack : AppTheme.textWhite,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: AppTheme.fontSizeSmall,
          )),
      selected: selected,
      selectedColor: AppTheme.primaryGold,
      backgroundColor: AppTheme.surfaceBlack,
      checkmarkColor: AppTheme.deepBlack,
      side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.5)),
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
