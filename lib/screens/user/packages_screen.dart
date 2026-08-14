import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/payment_provider.dart';
import '../../models/user_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../models/config_model.dart';
import '../../providers/offer_provider.dart';
import '../../models/offer_model.dart';

/// شاشة الباقات — مع دعم grace period + دفعة معلقة + السعر من Config
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  static const Map<int, List<Color>> _gradients = {
    0: [Color(0xFF424242), Color(0xFF616161)],
    1: [Color(0xFF8E8E8E), Color(0xFFBDBDBD)],
    2: [AppTheme.primaryGold, Color(0xFFFFD700)],
  };

  // ⭐ قسم الإعلان المميز المدفوع (بيع مباشر بدون الدخول على العرض — 2026-07-26)
  List<OfferModel> _activeOffers = [];
  bool _offersLoading = true;
  String? _selectedOfferId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AuthProvider>().userModel?.uid;
      if (uid != null) {
        context.read<PaymentProvider>().fetchPayments(uid);
        _loadActiveOffers(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final config  = context.watch<ConfigProvider>().config;
    final payProv = context.watch<PaymentProvider>();
    final user    = auth.userModel;
    final pkgMap  = config?.packages ?? {};

    final packages = [0, 1, 2]
        .map((id) => _PackageData.fromConfig(id, pkgMap[id.toString()]))
        .toList();

    // دفعات معلقة للمستخدم
    final pendingPayments = payProv.payments
        .where((p) => p.sts == 0 && p.tp == 0)
        .toList();

    // طلبات إعلان مميز معلقة (لكل عرض) — تمنع إعادة الطلب لنفس العرض قبل البت
    final pendingFeaturedIds = payProv.payments
        .where((p) => p.sts == 0 && p.tp == 1)
        .map((p) => (p.meta['offer_id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('الباقات والإعلان المميز'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        actions: [
          // زر "دفعاتي"
          TextButton.icon(
            onPressed: () => context.push('/user/my-payments'),
            icon: const Icon(Icons.receipt_long,
                color: AppTheme.primaryGold, size: 18),
            label: const Text('دفعاتي',
                style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // بطاقة الباقة الحالية
            if (user != null) _currentBadge(user),
            AppTheme.gapHeightMedium,

            // تنبيه دفعة معلقة
            if (pendingPayments.isNotEmpty) ...[
              _pendingPaymentBanner(pendingPayments.first.pkg),
              AppTheme.gapHeightMedium,
            ],

            // ⭐ الإعلان المميز المدفوع — بيع مباشر أول الشاشة (قرار المالك 2026-07-26)
            _featuredAdSection(config, pendingFeaturedIds),
            AppTheme.gapHeightXL,

            const Text(
              'اختر الباقة الأنسب لاحتياجك',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: AppTheme.fontSizeTitle,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'كلما زادت الباقة، زاد عدد العروض ومدة العرض',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
            ),
            AppTheme.gapHeightXL,

            ...packages.map((p) => _packageCard(
                  context, p, user,
                  config: config,
                  pendingPkgIds:
                      pendingPayments.map((pp) => pp.pkg).toSet(),
                  // أي طلب باقة معلق يحجب كل الأزرار — طلب واحد معلق بالمرة
                  anyPkgPending: pendingPayments.isNotEmpty,
                )),

            AppTheme.gapHeightXL,
            _infoBox(config),
          ],
        ),
      ),
    );
  }

  Future<void> _loadActiveOffers(String uid) async {
    try {
      final offers = await context.read<OfferProvider>().fetchUserOffers(uid);
      if (!mounted) return;
      setState(() {
        // العروض المنشورة فقط (sts=2) — قرار المالك: لا نعرض المعلّق/المنتهي
        _activeOffers = offers.where((o) => o.sts == 2).toList();
        _offersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _offersLoading = false);
    }
  }

  // ─── ⭐ بطاقة الإعلان المميز المدفوع — اختر العرض الخاص بك وتابع للدفع مباشرة ───
  Widget _featuredAdSection(ConfigModel? config, Set<String> pendingFeaturedIds) {
    final prices = config?.featuredAdPrices ??
        const {'w1': 50000, 'w2': 95000, 'w3': 135000, 'w4': 180000};
    int priceOf(int w) {
      final p = prices['w$w'];
      if (p is int) return p;
      return int.tryParse('$p') ?? 0;
    }

    const weekLabels = {1: 'أسبوع واحد', 2: 'أسبوعين', 3: '3 أسابيع', 4: '4 أسابيع'};

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.star, color: AppTheme.primaryGold, size: 22),
            AppTheme.gapWidthSmall,
            Text('إعلان مميز للعرض الخاص بك ✨',
                style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSubtitle, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'العرض المميز الخاص بك يظهر بقسم خاص بأعلى الرئيسية ونتائج البحث طوال المدة',
            style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
          ),
          AppTheme.gapHeightMedium,
          Row(
            children: [
              for (var wi = 1; wi <= 4; wi++)
                Expanded(
                  child: Column(children: [
                    Text(weekLabels[wi] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeXS)),
                    const SizedBox(height: 3),
                    // currency:1 → ل.س فقط (العملة الجديدة، بلا $)
                    Text(AppUtils.formatPrice(priceOf(wi), currency: 1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
                  ]),
                ),
            ],
          ),
          const Divider(height: 20, color: AppTheme.textGrey),
          if (_offersLoading)
            const Center(child: Padding(
              padding: AppTheme.paddingAllSmall,
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryGold)),
            ))
          else if (_activeOffers.isEmpty) ...[
            const Text('لا تملك عروضاً منشورة حالياً — أضف عرضاً أولاً لتروّجه ⭐',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
            AppTheme.gapHeightSmall,
            OutlinedButton.icon(
              onPressed: () => context.push('/user/add-offer'),
              icon: const Icon(Icons.add, color: AppTheme.primaryGold, size: 18),
              label: const Text('إضافة عرض', style: TextStyle(color: AppTheme.primaryGold)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              value: _selectedOfferId,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceBlack,
              style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.scaffoldBackground,
                hintText: 'اختر العرض المراد إعلانه ⭐',
                hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                border: OutlineInputBorder(borderRadius: AppTheme.radiusMedium),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _activeOffers.map((o) {
                final active = o.fmsEnd != null && o.fmsEnd!.isAfter(DateTime.now());
                final pend = pendingFeaturedIds.contains(o.id);
                final label = pend
                    ? '${o.ttl}  ⏳ طلبك قيد المراجعة'
                    : (active ? '${o.ttl}  ✓ مميز' : o.ttl);
                return DropdownMenuItem<String>(
                  value: o.id,
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedOfferId = v),
            ),
            AppTheme.gapHeightSmall,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedOfferId == null ||
                        pendingFeaturedIds.contains(_selectedOfferId)
                    ? null
                    : () {
                        final oid = _selectedOfferId!;
                        context.push('/user/featured-payment?offer=$oid');
                      },
                icon: const Icon(Icons.payment, color: AppTheme.deepBlack),
                label: const Text('تابع للدفع — تختار المدة وقناة الدفع بالخطوة التالية 💳',
                    style: TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSmall)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── بطاقة الباقة الحالية ───
  Widget _currentBadge(UserModel user) {
    final isPkgActive      = user.isPkgActive;
    final isInGrace        = user.isInGracePeriod;
    final isExpired        = user.bPkg > 0 && !isPkgActive && !isInGrace;

    Color borderColor = AppTheme.primaryGold.withOpacity(0.4);
    if (isInGrace)  borderColor = AppTheme.warningOrange.withOpacity(0.6);
    if (isExpired)  borderColor = AppTheme.errorRed.withOpacity(0.5);

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        Icon(
          isInGrace  ? Icons.hourglass_bottom :
          isExpired  ? Icons.warning_amber :
                       Icons.workspace_premium,
          color: isInGrace ? AppTheme.warningOrange :
                 isExpired  ? AppTheme.errorRed :
                              AppTheme.primaryGold,
          size: 32,
        ),
        AppTheme.gapWidthMedium,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isInGrace ? 'فترة السماح — باقة ${_pkgName(user.bPkg)}' :
                isExpired  ? 'انتهت الباقة — ${_pkgName(user.bPkg)}' :
                user.bPkg == 0 ? 'الباقة المجانية' :
                'باقة ${_pkgName(user.bPkg)} — نشطة',
                style: TextStyle(
                  color: isInGrace ? AppTheme.warningOrange :
                         isExpired  ? AppTheme.errorRed :
                                      AppTheme.primaryGold,
                  fontSize: AppTheme.fontSizeSubtitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppTheme.gapHeightXS,
              if (user.pkgEnd != null && user.bPkg > 0)
                Text(
                  isPkgActive
                      ? 'تنتهي: ${AppUtils.formatTimestamp(user.pkgEnd!)}'
                      : isInGrace
                          ? '⚠️ فترة السماح تنتهي: ${AppUtils.formatTimestamp(user.pkgGrace!)} (${user.graceDaysLeft} يوم متبق)'
                          : '⛔ انتهت — جدّد اشتراكك الآن',
                  style: TextStyle(
                    color: isInGrace ? AppTheme.warningOrange :
                           isExpired  ? AppTheme.errorRed :
                                        AppTheme.textGrey,
                    fontSize: AppTheme.fontSizeCaption,
                    fontWeight: (isInGrace || isExpired)
                        ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
            ],
          ),
        ),
        // زر تجديد سريع إذا انتهت أو في فترة السماح
        if ((isExpired || isInGrace) && user.bPkg > 0) ...[
          AppTheme.gapWidthSmall,
          ElevatedButton(
            onPressed: () => context.push('/user/payment?pkg=${user.bPkg}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isInGrace ? AppTheme.warningOrange : AppTheme.primaryGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('جدّد', style: TextStyle(fontSize: AppTheme.fontSizeSmall)),
          ),
        ],
      ]),
    );
  }

  // ─── تنبيه دفعة معلقة ───
  Widget _pendingPaymentBanner(int pkgId) {
    return Container(
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.infoBlue.withOpacity(0.1),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.infoBlue.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.pending_actions, color: AppTheme.infoBlue, size: 20),
        AppTheme.gapWidthSmall,
        Expanded(
          child: Text(
            'لديك دفعة معلقة للباقة ${_pkgName(pkgId)} — في انتظار موافقة الإدارة (عادة < 24 ساعة).',
            style:
                const TextStyle(color: AppTheme.infoBlue, fontSize: AppTheme.fontSizeSmall, height: 1.4),
          ),
        ),
        TextButton(
          onPressed: () => context.push('/user/my-payments'),
          child: const Text('متابعة',
              style: TextStyle(color: AppTheme.infoBlue, fontSize: AppTheme.fontSizeSmall)),
        ),
      ]),
    );
  }

  // ─── بطاقة باقة ───
  Widget _packageCard(
    BuildContext context,
    _PackageData pkg,
    UserModel? user, {
    ConfigModel? config,
    required Set<int> pendingPkgIds,
    required bool anyPkgPending,
  }) {
    final effectivePkg  = user?.effectivePkg ?? 0;
    final isCurrent     = pkg.id == effectivePkg && pkg.id > 0;
    final isFree        = pkg.id == 0;
    final isPending     = pendingPkgIds.contains(pkg.id);
    final gradient      = _gradients[pkg.id]!;

    // السعر من Config مباشرة — لا من URL
    final price = pkg.price;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusLarge,
        gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: AppTheme.paddingAllXL,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusLarge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pkg.name,
                      style: TextStyle(
                          color: gradient[1],
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    if (isCurrent)
                      _badge('باقتك الحالية', AppTheme.successGreen),
                    if (isCurrent && (user?.pkgXoff ?? 0) > 0)
                      _badge(
                          '🎯 السقف الفعلي: ${pkg.offers + (user?.pkgXoff ?? 0)} عرض (منها +${user?.pkgXoff ?? 0} مضافة بالتراكم)',
                          Colors.lightGreen),
                    if (isPending && !isCurrent)
                      _badge('دفعة معلقة ⏳', AppTheme.infoBlue),
                    if (user?.isInGracePeriod == true &&
                        pkg.id == user?.bPkg &&
                        !isCurrent)
                      _badge('فترة السماح', AppTheme.warningOrange),
                    // الشراء الأدنى مسموح — بنظام التجميع ينضاف سقف وأيام للرصيد
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    // 💱 PRICE-UNIT-001 (2026-08-15): `pkg.pr` بالدولار
                    // (قرار المالك: 10 و25) والعرض بالليرة عبر fx.usd_syp.
                    // ⚠️ كان هنا `?? 150` — افتراضي مخالف لقاعدة «لا شيء
                    // افتراضي»، وأقل بمئة ضعف من السعر الحقيقي (15000)
                    // ⇒ لو غاب الإعداد لرأى المستخدم 1,500 بدل 150,000.
                    // الآن الغياب يُعلَن نصاً ويُعطَّل زر الشراء.
                    isFree
                        ? 'مجاناً'
                        : (config?.packagePriceSyp(pkg.id) == null
                            ? 'السعر غير متاح'
                            : AppUtils.formatPrice(
                                config!.packagePriceSyp(pkg.id)!,
                                currency: 1)),
                    style: TextStyle(
                        color: gradient[1],
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  if (!isFree)
                    const Text('/ شهرياً',
                        style:
                            TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                ],
              ),
            ]),
            const Divider(color: AppTheme.textGrey, height: 24),
            _feature(Icons.list_alt, '${pkg.offers} عروض فعّالة'),
            _feature(Icons.calendar_today, 'مدة العرض ${pkg.duration} يوم'),
            _feature(Icons.hourglass_bottom, '${config?.pkgGraceDays ?? 3} أيام سماح بعد الانتهاء'),
            if (pkg.id >= 1) _feature(Icons.star, 'أولوية بالظهور'),
            if (pkg.id >= 2) _feature(Icons.support_agent, 'دعم فني مميّز'),
            if (pkg.id >= 2) _feature(Icons.handshake, 'شارة موثوق'),
            AppTheme.gapHeightLarge,
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _btnAction(
                    context, pkg, isCurrent, isFree, isPending || anyPkgPending, price),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPending
                      ? AppTheme.infoBlue.withOpacity(0.3)
                      : gradient[1],
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppTheme.surfaceBlack,
                  disabledForegroundColor: AppTheme.textGrey,
                ),
                child: Text(
                  isCurrent
                      ? 'باقتك الحالية ✓'
                      : isFree
                          ? 'الباقة الافتراضية'
                          : isPending
                              ? 'دفعة معلقة — قيد المراجعة'
                              : 'الاشتراك الآن',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback? _btnAction(BuildContext ctx, _PackageData pkg, bool isCurrent,
      bool isFree, bool isPending, double price) {
    // ✅ Fix for Bug #36: منع الاشتراك بنفس الباقة إذا كانت نشطة
    if (isCurrent || isFree) return null;
    
    // إذا كان هناك دفعة معلقة لهذه الباقة
    if (isPending) {
      return () => ctx.push('/user/my-payments');
    }
    
    // التحقق من أن المستخدم لا يملك بالفعل باقة أعلى أو مساوية
    final user = ctx.read<AuthProvider>().userModel;
    if (user != null && user.bPkg >= pkg.id && user.isPkgActive) {
      return null; // لا يمكن الاشتراك بنفس الباقة أو باقة أقل
    }
    
    // 💱 PRICE-UNIT-001: لا نفتح شاشة الدفع وسعر الصرف غائب — المستخدم
    // سيرفع إثباتاً ثم يُرفض خادمياً. التعطيل أوضح وأرحم (§13).
    final cfg = ctx.read<ConfigProvider>().config;
    if (cfg?.packagePriceSyp(pkg.id) == null) return null;

    // السعر يأتي من Config مباشرة — لا من URL قابل للتعديل
    return () => ctx.push('/user/payment?pkg=${pkg.id}');
  }

  Widget _badge(String label, Color color) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: AppTheme.radiusSmall,
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
      );

  Widget _feature(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, color: AppTheme.primaryGold, size: 18),
          AppTheme.gapWidthSmall,
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium))),
        ]),
      );

  Widget _infoBox(ConfigModel? config) => Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusMedium,
          border:
              Border.all(color: AppTheme.textGrey.withOpacity(0.3)),
        ),
                child: Row(children: [
          const Icon(Icons.info_outline, color: AppTheme.primaryGold, size: 20),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Text(
              'يتم تفعيل الباقة بعد موافقة الإدارة على إثبات الدفع (عادة < 24 ساعة). '
              'بعد انتهاء الباقة لديك ${config?.pkgGraceDays ?? 3} أيام سماح قبل التحول للمجانية.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
            ),
          ),
        ]),
      );

  static String _pkgName(int pkg) {
    switch (pkg) {
      case 1: return 'الفضية';
      case 2: return 'الذهبية';
      default: return 'المجانية';
    }
  }
}

class _PackageData {
  final int    id;
  final String name;
  final int    offers;
  final int    duration;
  final double price;

  _PackageData({
    required this.id,
    required this.name,
    required this.offers,
    required this.duration,
    required this.price,
  });

  factory _PackageData.fromConfig(int id, dynamic raw) {
    final m = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    const defaults = {
      0: {'nm': 'مجاني',  'o': 1,  'd': 30, 'pr': 0},
      1: {'nm': 'فضي',   'o': 15, 'd': 45, 'pr': 10},
      2: {'nm': 'ذهبي',  'o': 40, 'd': 60, 'pr': 25},
    };
    final def = defaults[id]!;
    return _PackageData(
      id:       id,
      name:     (m['nm'] ?? def['nm']) as String,
      offers:   (m['o']  ?? def['o'])  as int,
      duration: (m['d']  ?? def['d'])  as int,
      price:    ((m['pr'] ?? def['pr']) as num).toDouble(),
    );
  }
}
