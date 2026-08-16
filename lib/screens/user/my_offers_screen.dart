import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/offer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/constants/db_constants.dart';
import '../../models/offer_model.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/bottom_nav_bar.dart';

/// شاشة عروضي — تعرض كل عروض المستخدم مع فلترة بالحالة
/// + إمكانية التعديل/الترقية/مشاهدة التفاصيل.
class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key});

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<OfferModel> _myOffers = [];
  bool _loading = true;

  final List<_FilterTab> _filters = const [
    _FilterTab('الكل', -1),
    _FilterTab('قيد المراجعة', 1),
    _FilterTab('منشور', 2),
    _FilterTab('مرفوض', 3),
    _FilterTab('منتهي', 4),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _filters.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = context.read<AuthProvider>().userModel?.uid;
    if (uid == null || uid.isEmpty) return;
    setState(() => _loading = true);
    final offers = await context.read<OfferProvider>().fetchUserOffers(uid);
    if (!mounted) return;
    setState(() {
      _myOffers = offers;
      _loading = false;
    });
  }

  List<OfferModel> _filterOffers(List<OfferModel> offers, int status) {
    if (status == -1) return offers;
    return offers.where((o) => o.sts == status).toList();
  }

  /// 📊 CNT-001 (2026-08-15) بطلب المالك: «العدّاد بالنسبة لعروضي المنشورة
  /// غير ظاهر». الحساب كان محبوساً داخل `_tryAddOffer` فلا يراه المستخدم
  /// إلا عند بلوغ الحد. استُخرج هنا ليُعرض دائماً كشريط أعلى القائمة.
  ///
  /// يطابق منطق `create_offer_internal` تماماً: يَعُدّ الحالات
  /// {مسودة، مراجعة، منشور، محجوز} · يُعفي الطاقم (role>=4) · السقف من
  /// الباقة الفعالة (+ pkg_xoff المتراكم) وإلا 5 للوسيط و1 لغيره.
  ({int used, int limit, bool exempt}) get _quota {
    final user = context.read<AuthProvider>().userModel;
    final config = context.read<ConfigProvider>().config;
    if (user == null) return (used: 0, limit: 0, exempt: true);
    if (user.role >= 4) return (used: 0, limit: 0, exempt: true);

    const counted = {
      OfferStatus.draft,
      OfferStatus.review,
      OfferStatus.published,
      OfferStatus.reserved
    };
    final used =
        _myOffers.where((o) => o.iDel == 0 && counted.contains(o.sts)).length;

    final now = DateTime.now();
    var effectivePkg = 0;
    if (user.bPkg != 0 &&
        ((user.pkgEnd?.isAfter(now) ?? false) ||
            (user.pkgGrace?.isAfter(now) ?? false))) {
      effectivePkg = user.bPkg;
    }
    final pkgMap = config?.data['pkg'];
    final pkgEntry = pkgMap is Map ? pkgMap['$effectivePkg'] : null;
    final base = (pkgEntry is Map ? (pkgEntry['o'] as num?)?.toInt() : null) ??
        (user.role == 1 ? 5 : 1);
    // pkg_xoff: السقف المتراكم من الترقيات (نموذج التجميع)
    return (used: used, limit: base + (user.pkgXoff), exempt: false);
  }

  /// شريط العدّاد أعلى القائمة.
  Widget _quotaBar() {
    final q = _quota;
    if (q.exempt) return const SizedBox.shrink();
    final full = q.used >= q.limit;
    final ratio = q.limit == 0 ? 1.0 : (q.used / q.limit).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
            color: (full ? AppTheme.errorRed : AppTheme.primaryGold)
                .withOpacity(0.35)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.inventory_2_outlined,
              size: 18, color: full ? AppTheme.errorRed : AppTheme.primaryGold),
          AppTheme.gapWidthSmall,
          const Expanded(
            child: Text('عروضك المستخدمة من الحد الأقصى',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: AppTheme.fontSizeSmall,
                    fontWeight: FontWeight.w600)),
          ),
          Text('${q.used} / ${q.limit}',
              style: TextStyle(
                  color: full ? AppTheme.errorRed : AppTheme.primaryGold,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTheme.fontSizeBody)),
        ]),
        AppTheme.gapHeightXS,
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(
                full ? AppTheme.errorRed : AppTheme.primaryGold),
          ),
        ),
        if (full) ...[
          AppTheme.gapHeightXS,
          const Text('بلغت الحد الأقصى — اشترك بباقة لرفعه',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
        ],
      ]),
    );
  }

  /// بوابة قبولية مسبقة بطلب المالك: المنع يظهر عند الضغط على «إضافة عرض» مباشرةً،
  /// لا بعد تعبئة البيانات — مع فتح شاشة الاشتراك بالباقات فوراً.
  /// ⚠️ الحارس الحقيقي يبقى سيرفرياً (create_offer_internal) — هذه البوابة تحسين تجربة
  /// وتسويق، وتطبّق نفس قواعده تقريبياً: عدّاد sts في {draft,review,published,reserved}،
  /// إعفاء role>=4، fallback مستخدم=1 / وسيط=5، حصة الباقة الفعالة من config.pkg.
  /// (المحذوفة خلال 24 ساعة لا يعرفها العميل — يحسمها السيرفر عند النشر)
  Future<void> _tryAddOffer() async {
    final auth = context.read<AuthProvider>();
    final config = context.read<ConfigProvider>().config;
    final user = auth.userModel;

    var limited = false;
    var limit = 1;
    if (user != null && user.role < 4) {
      const counted = {OfferStatus.draft, OfferStatus.review, OfferStatus.published, OfferStatus.reserved};
      final used = _myOffers.where((o) => o.iDel == 0 && counted.contains(o.sts)).length;

      final now = DateTime.now();
      var effectivePkg = 0;
      if (user.bPkg != 0 &&
          ((user.pkgEnd?.isAfter(now) ?? false) || (user.pkgGrace?.isAfter(now) ?? false))) {
        effectivePkg = user.bPkg;
      }
      final pkgMap = config?.data['pkg'];
      final pkgEntry = pkgMap is Map ? pkgMap['$effectivePkg'] : null;
      limit = (pkgEntry is Map ? (pkgEntry['o'] as num?)?.toInt() : null) ?? (user.role == 1 ? 5 : 1);
      limited = used >= limit;
    }

    if (!limited) {
      await context.push('/user/add-offer');
      if (mounted) _refresh();
      return;
    }

    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
        title: const Text('وصلت لحد العروض المسموح', style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
          'تجاوزت عدد العروض المسموح بها لحسابك (الحد الحالي: $limit عرض).\n\n'
          'لإضافة المزيد من العروض، اشترك بإحدى الباقات واستفد من حصة أكبر ومزايا إضافية.',
          style: const TextStyle(color: AppTheme.textGrey, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لاحقاً', style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            child: const Text('الاشتراك بباقة',
                style: TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await context.push('/user/packages');
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('عروضي'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: AppTheme.primaryGold,
          labelColor: AppTheme.primaryGold,
          unselectedLabelColor: AppTheme.textGrey,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody),
          tabs: _filters
              .map((f) => Tab(
                    text:
                        '${f.label} (${_filterOffers(_myOffers, f.status).length})',
                  ))
              .toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('عرض جديد'),
        onPressed: _tryAddOffer,
      ),
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 1),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold),
            )
          : Column(children: [
              // 📊 CNT-001: العدّاد ظاهر دائماً فوق القائمة
              _quotaBar(),
              Expanded(
                child: RefreshIndicator(
                  color: AppTheme.primaryGold,
                  onRefresh: _refresh,
                  child: TabBarView(
                    controller: _tab,
                    children: _filters
                        .map((f) => _offersList(_filterOffers(_myOffers, f.status)))
                        .toList(),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _offersList(List<OfferModel> offers) {
    if (offers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open,
                size: 80, color: AppTheme.primaryGold.withOpacity(0.5)),
            AppTheme.gapHeightXL,
            const Text('لا توجد عروض في هذه الحالة',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
            AppTheme.gapHeightLarge,
            ElevatedButton.icon(
              onPressed: _tryAddOffer,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('أضف أول عرض لك'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: offers.length,
      itemBuilder: (context, i) => _offerCard(offers[i]),
    );
  }

  Widget _offerCard(OfferModel o) {
    final status = _statusInfo(o.sts);
    final hasImage = o.imgs.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: status.$2.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: AppTheme.radiusLarge,
        onTap: () => context.push('/offer/${o.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: status.$2.withOpacity(0.15),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(
                children: [
                  Icon(status.$3, color: status.$2, size: 16),
                  const SizedBox(width: 6),
                  Text(status.$1,
                      style: TextStyle(
                          color: status.$2,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTheme.fontSizeSmall)),
                  const Spacer(),
                  if (o.sts == 3 && o.rsn.isNotEmpty)
                    Tooltip(
                      message: 'سبب الرفض: ${o.rsn}',
                      child: const Icon(Icons.info_outline,
                          color: AppTheme.errorRed, size: 16),
                    ),
                ],
              ),
            ),
            Padding(
              padding: AppTheme.paddingAllMedium,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: AppTheme.radiusMedium,
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: hasImage
                          ? Image.network(o.imgs.first.toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _imgPlaceholder())
                          : _imgPlaceholder(),
                    ),
                  ),
                  AppTheme.gapWidthMedium,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.ttl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        AppTheme.gapHeightXS,
                        Text(
                          '${_formatPrice(o.prc)} ${o.cur == 0 ? '\$' : 'ل.س'}',
                          style: const TextStyle(
                              color: AppTheme.primaryGold,
                              fontWeight: FontWeight.bold,
                              fontSize: AppTheme.fontSizeMedium),
                        ),
                        AppTheme.gapHeightXS,
                        Row(
                          children: [
                            const Icon(Icons.remove_red_eye,
                                color: AppTheme.textGrey, size: 13),
                            const SizedBox(width: 3),
                            Text('${o.vws}',
                                style: const TextStyle(
                                    color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                            AppTheme.gapWidthSmall,
                            const Icon(Icons.favorite,
                                color: AppTheme.textGrey, size: 13),
                            const SizedBox(width: 3),
                            Text('${o.fvs}',
                                style: const TextStyle(
                                    color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.deepBlack, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.edit,
                      label: 'تعديل',
                      color: AppTheme.primaryGold,
                      onTap: () async {
                        final changed = await context.push('/user/edit-offer/${o.id}');
                        if (changed == true && mounted) _refresh();
                      },
                    ),
                  ),
                  Container(width: 1, height: 30, color: AppTheme.deepBlack),
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.rocket_launch,
                      label: 'ترقية',
                      color: Colors.purple,
                      onTap: () async {
                        final result = await context.push('/user/boost-offer/${o.id}');
                        if (result == true && mounted) _refresh();
                      },
                    ),
                  ),
                  Container(width: 1, height: 30, color: AppTheme.deepBlack),
                  Expanded(
                    child: _actionBtn(
                      icon: Icons.visibility,
                      label: 'عرض',
                      color: AppTheme.textWhite,
                      onTap: () => context.push('/offer/${o.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: AppTheme.deepBlack,
        child: const Icon(Icons.image_not_supported,
            color: AppTheme.textGrey, size: 30),
      );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            AppTheme.gapHeightXXS,
            Text(label, style: TextStyle(color: color, fontSize: AppTheme.fontSizeCaption)),
          ],
        ),
      ),
    );
  }

  String _formatPrice(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  (String, Color, IconData) _statusInfo(int s) {
    switch (s) {
      case 0:
        return ('مسودة', AppTheme.textGrey, Icons.edit_note);
      case 1:
        return ('قيد المراجعة', AppTheme.warningOrange, Icons.hourglass_empty);
      case 2:
        return ('منشور', AppTheme.successGreen, Icons.check_circle);
      case 3:
        return ('مرفوض', AppTheme.errorRed, Icons.cancel);
      case 4:
        return ('منتهي', AppTheme.textGrey, Icons.timer_off);
      case 5:
        return ('محجوز', AppTheme.infoBlue, Icons.lock_clock);
      case 6:
        return ('مكتمل', Colors.teal, Icons.done_all);
      default:
        return ('غير معروف', AppTheme.textGrey, Icons.help);
    }
  }
}

class _FilterTab {
  final String label;
  final int status;
  const _FilterTab(this.label, this.status);
}
